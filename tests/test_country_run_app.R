# Offline tests for shiny_app/R/country_run.R  (helpers + a mock-session run with a fake runner).
# Needs: shiny, testthat, processx, jsonlite, arrow, readr, writexl.   Run from the repo root:
#   Rscript tests/test_country_run_app.R
suppressPackageStartupMessages({ library(shiny); library(testthat) })
CONFIG_DIR <- "config"
source("shiny_app/R/access_control.R")
source("shiny_app/R/country_run.R")

tmp  <- tempfile("crtest_"); dir.create(tmp)
root <- file.path(tmp, "runs"); dir.create(root)

# ── slots & scratch folders ─────────────────────────────────────────────────
test_that("slots are limited, released and swept", {
  a <- cr_try_acquire(root, max_runs = 2); b <- cr_try_acquire(root, max_runs = 2)
  expect_true(dir.exists(a) && dir.exists(b) && a != b)
  expect_null(cr_try_acquire(root, max_runs = 2))               # server full
  expect_equal(cr_active_count(root), 2L)
  cr_release_slot(a)
  expect_equal(cr_active_count(root), 1L)
  c3 <- cr_try_acquire(root, max_runs = 2)
  expect_true(dir.exists(c3))
  # a dead owner's folder is swept and frees its slot -- but never while it is brand new
  writeLines("999999", file.path(b, ".owner"))
  cr_sweep(root)
  expect_true(dir.exists(b))                                    # younger than the grace period: untouched
  Sys.setFileTime(b, Sys.time() - 300)
  cr_sweep(root)
  expect_false(dir.exists(b))
  # too-old folders are swept even if the owner is alive
  Sys.setFileTime(c3, Sys.time() - 7 * 3600)
  cr_sweep(root)
  expect_false(dir.exists(c3))
  expect_true(dir.exists(a))                                    # a: owner alive, young
  # one active run per form
  f1 <- cr_try_acquire(root, max_runs = 5, form_id = "10267")
  expect_true(cr_form_busy(root, "10267")); expect_false(cr_form_busy(root, "7178"))
  cr_release_slot(f1); expect_false(cr_form_busy(root, "10267"))
  cr_discard(f1)
  cr_discard(a); expect_false(dir.exists(a))
  cr_discard(root); expect_true(dir.exists(root))               # refuses anything not named run_*
})

test_that("log lines are filtered", {
  x <- c("[country-run] 1/3 Fetching the latest data ...",
         "[sharepoint] Using https://worldhealthorg.sharepoint.com/x",
         "Authorization: Bearer abc", "Traceback (most recent call last):",
         "password=hunter2", "TOKEN is xyz", "  ", "plain \033[31mred\033[0m text",
         strrep("long ", 60))
  y <- cr_clean_lines(x)
  expect_equal(y[1], "1/3 Fetching the latest data ...")
  expect_true("plain red text" %in% y)
  expect_false(any(grepl("sharepoint|Bearer|Traceback|hunter2|xyz", y, ignore.case = TRUE)))
  expect_true(all(nchar(y) <= 160))
  z <- cr_clean_lines(c("failed reading /tmp/im_country_runs/run_1/data/raw/1.parquet", "see C:\\Users\\x\\y.txt", "report 5/10/2024 ok", "step 2/3 done"))
  expect_equal(z, c("failed reading <path>", "see <path>", "report 5/10/2024 ok", "step 2/3 done"))
})

test_that("log filter: paths anywhere in a line, tracebacks, hosts, bad bytes", {
  x <- c("Permission denied: '/srv/connect/apps/42/data/final'",
         'File "/usr/lib/python3.11/site-packages/requests/api.py", line 59',
         "cannot open file (/home/rstudio/im/data/raw/4498.csv)", "path=/var/lib/x/y", "file:///srv/x/y",
         'wrote "C:\\Users\\TOURE\\x.csv"', "host='api.whonghub.org'", "ok: 5/10/2024 and 1/3 done",
         "caf\xe9 s\xff", "after bad bytes")
  y <- cr_clean_lines(x)
  expect_false(any(grepl("/srv|/usr|/home|/var|TOURE|whonghub|site-packages|api\\.py|file:", y)))
  expect_true(any(y == "ok: 5/10/2024 and 1/3 done"))              # dates / progress counters are untouched
  expect_true("after bad bytes" %in% y)                            # invalid bytes did not break the filter
})

test_that("sweep only touches folders this module created", {
  r2 <- file.path(tmp, "runs2"); dir.create(r2)
  mine_dead   <- file.path(r2, "run_20260101_000000_abcdef12"); dir.create(mine_dead); writeLines("999999", file.path(mine_dead, ".owner"))
  mine_noown  <- file.path(r2, "run_20260101_000001_abcdef12"); dir.create(mine_noown)
  foreign     <- file.path(r2, "run_my_analysis_results"); dir.create(foreign); writeLines("x", file.path(foreign, "keep.txt"))
  for (d in c(mine_dead, mine_noown, foreign)) Sys.setFileTime(d, Sys.time() - 3600)
  cr_sweep(r2)
  expect_false(dir.exists(mine_dead))                              # dead owner, old enough: removed
  expect_true(dir.exists(mine_noown))                              # no owner file: not "dead"
  expect_true(file.exists(file.path(foreign, "keep.txt")))         # foreign name: never touched
  Sys.setFileTime(mine_noown, Sys.time() - 7 * 3600); cr_sweep(r2)
  expect_false(dir.exists(mine_noown))                             # but ancient ones go
})

test_that("export errors are generic, expected ones are kept", {
  home2 <- file.path(tmp, "run_err"); dir.create(file.path(home2, "data/final"), recursive = TRUE)
  writeLines("not a parquet", file.path(home2, "data/final/Regional_IM_repository_cleaned.parquet"))
  r <- cr_export(home2, "clean", "xlsx", tempfile())
  expect_false(r$ok); expect_false(grepl("parquet|Arrow|/", r$message)); expect_match(r$message, "could not be prepared")
  expect_match(cr_export(file.path(tmp, "nope"), "clean", "csv", tempfile())$message, "not available yet")
})

# ── exports ─────────────────────────────────────────────────────────────────
home <- file.path(tmp, "run_x"); dir.create(file.path(home, "data/final"), recursive = TRUE); dir.create(file.path(home, "data/raw"), recursive = TRUE)
clean_df <- data.frame(country = c("ANGOLA", "ANGOLA"), v = 1:2, note = c("a,b", "c"), stringsAsFactors = FALSE)
readr::write_csv(clean_df, file.path(home, "data/final/Regional_IM_repository_cleaned.csv"))
arrow::write_parquet(clean_df, file.path(home, "data/final/Regional_IM_repository_cleaned.parquet"))
arrow::write_parquet(data.frame(a = 1:3, b = letters[1:3]), file.path(home, "data/raw/10267.parquet"))

test_that("cleaned export in every format", {
  for (fmt in c("csv", "parquet", "rds", "xlsx")) {
    out <- tempfile(fileext = paste0(".", fmt))
    r <- cr_export(home, "clean", fmt, out)
    expect_true(r$ok, info = fmt)
    expect_true(file.exists(out) && file.size(out) > 0, info = fmt)
  }
  out <- tempfile(fileext = ".rds"); cr_export(home, "clean", "rds", out)
  expect_equal(readRDS(out)$v, 1:2)                              # converted from the parquet
  out <- tempfile(fileext = ".xlsx"); cr_export(home, "clean", "xlsx", out)
  expect_equal(as.data.frame(readxl::read_excel(out))$note, c("a,b", "c"))
})

test_that("raw export in every format", {
  for (fmt in c("csv", "parquet", "rds", "xlsx")) {
    out <- tempfile(fileext = paste0(".", fmt))
    expect_true(cr_export(home, "raw", fmt, out, "10267")$ok, info = fmt)
  }
  out <- tempfile(fileext = ".csv"); cr_export(home, "raw", "csv", out, "10267")
  expect_equal(nrow(readr::read_csv(out, show_col_types = FALSE)), 3L)
})

test_that("export failures are reported, never thrown", {
  out <- tempfile()
  expect_false(cr_export(home, "raw", "csv", out, "7178")$ok)           # no such raw file
  expect_false(cr_export(home, "raw", "csv", out, "../x")$ok)           # path trick refused
  expect_false(cr_export(home, "raw", "csv", out, NULL)$ok)
  expect_false(cr_export(home, "clean", "docx", out)$ok)
  expect_false(cr_export(file.path(tmp, "nope"), "clean", "csv", out)$ok)
  old <- CR_EXCEL_MAX_ROWS; assign("CR_EXCEL_MAX_ROWS", 1L, envir = globalenv())
  r <- cr_export(home, "clean", "xlsx", out)
  assign("CR_EXCEL_MAX_ROWS", old, envir = globalenv())
  expect_false(r$ok); expect_match(r$message, "more than Excel")
})

test_that("download names are safe", {
  expect_equal(cr_download_name("clean", "csv", "COTE D IVOIRE", as.Date("2026-10-08")), "IM_COTE_D_IVOIRE_cleaned_2026-10-08.csv")
  expect_equal(cr_download_name("raw", "xlsx", "../../etc/passwd", as.Date("2026-10-08")), "IM_etc_passwd_raw_2026-10-08.xlsx")
  expect_equal(cr_download_name("raw", "csv", "", as.Date("2026-10-08")), "IM_country_raw_2026-10-08.csv")
})

# ── mock session with a fake runner ─────────────────────────────────────────
fake_runner <- file.path(tmp, "fake_runner.R")
writeLines(c(
  'a <- commandArgs(TRUE); home <- a[match("--home", a) + 1]; fid <- a[match("--form-id", a) + 1]',
  'cat("[country-run] 1/3 Fetching the latest data ...\\n"); flush.console()',
  'cat("[sharepoint] https://worldhealthorg.sharepoint.com token=abc\\n")',
  'cat("some child output that is not a runner line\\n")',
  'if (Sys.getenv("FAKE_MODE") == "fail") { cat("[country-run] FAILED: boom\\n"); writeLines(\'{"ok": false, "message": "boom"}\', file.path(home, "run_result.json")); quit(status = 1) }',
  'stopifnot(Sys.getenv("IM_ADMIN_CODES") == "", Sys.getenv("IM_COUNTRY_CODES") == "", Sys.getenv("ANTHROPIC_API_KEY") == "")',
  'dir.create(file.path(home, "data/final"), recursive = TRUE); dir.create(file.path(home, "data/raw"), recursive = TRUE)',
  'd <- data.frame(country = "ANGOLA", v = 1:2)',
  'write.csv(d, file.path(home, "data/final/Regional_IM_repository_cleaned.csv"), row.names = FALSE)',
  'arrow::write_parquet(d, file.path(home, "data/raw", paste0(fid, ".parquet")))',
  'writeLines(\'{"ok": true, "message": "Done", "rows": 2}\', file.path(home, "run_result.json"))',
  'cat("[country-run] DONE - your cleaned data is ready to download (2 rows)\\n")'
), fake_runner)

secrets <- c(IM_ADMIN_CODES = "ADMIN-ONE-0001", IM_COUNTRY_CODES = "AGO=ang-1234-code;NGA=nga-5678-code",
             IM_ADMIN_CODES_BACKUP = "")
with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA)
  do.call(Sys.setenv, as.list(vars))
  on.exit(for (n in names(old)) if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(old[[n]]), n)))
  force(code)
}
server <- function(input, output, session) {
  auth <- ac_session_init(input, output, session)
  cr   <- cr_session_init(input, output, session, auth, source_home = tmp, script = fake_runner, root = root)
}
wait_for <- function(session, cr, secs = 60) {
  t0 <- Sys.time()
  while (identical(cr$status, "running") && as.numeric(difftime(Sys.time(), t0, units = "secs")) < secs) {
    Sys.sleep(0.4); session$elapse(1000)
  }
}
dl_file <- function(session, id) {                                  # run a downloadHandler's content()
  session$output[[id]]
}

test_that("country user: run -> filtered log -> ready -> downloads", {
  with_env(secrets, testServer(server, {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    session$flushReact()
    session$setInputs(cr_form = "10267", cr_fmt = "csv")
    session$setInputs(cr_run = 1)
    expect_equal(cr$status, "running")
    wait_for(session, cr)
    expect_equal(cr$status, "ok")
    expect_true(any(grepl("Fetching the latest data", cr$log)))
    expect_true(any(grepl("DONE", cr$log)))
    expect_false(any(grepl("sharepoint|token", cr$log, ignore.case = TRUE)))
    expect_false(any(grepl("child output", cr$log)))                # only "[country-run]" lines are shown
    expect_equal(cr_active_count(root), 0L)                         # slot released
    f <- session$getOutput("cr_dl_clean")
    expect_true(file.exists(f) && grepl("ANGOLA", paste(readLines(f), collapse = "")))
    fr <- session$getOutput("cr_dl_raw")
    expect_true(file.exists(fr) && nrow(read.csv(fr)) == 2L)
  }))
})

test_that("country user cannot run another country's form", {
  with_env(secrets, testServer(server, {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    session$setInputs(cr_form = "7178", cr_fmt = "csv", cr_run = 1)  # Nigeria's form
    expect_equal(cr$status, "idle")
    expect_null(cr$proc)
  }))
})

test_that("admin cannot use the country runner; signed-out cannot either", {
  with_env(secrets, testServer(server, {
    session$setInputs(cr_form = "10267", cr_fmt = "csv", cr_run = 1)   # not signed in
    expect_equal(cr$status, "idle")
    session$setInputs(auth_code = "ADMIN-ONE-0001", auth_submit = 1)
    session$setInputs(cr_run = 2)
    expect_equal(cr$status, "idle")
  }))
})

test_that("downloads are empty unless a run succeeded", {
  with_env(secrets, testServer(server, {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    session$setInputs(cr_form = "10267", cr_fmt = "csv")
    f <- session$getOutput("cr_dl_clean")
    expect_true(!file.exists(f) || file.size(f) == 0L)
  }))
})

test_that("failed run is reported and filtered", {
  with_env(c(secrets, FAKE_MODE = "fail"), testServer(server, {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    session$setInputs(cr_form = "10267", cr_fmt = "csv", cr_run = 1)
    wait_for(session, cr)
    expect_equal(cr$status, "error")
    expect_true(any(grepl("FAILED: boom", cr$log)))
    expect_false(any(grepl("sharepoint", cr$log, ignore.case = TRUE)))
    expect_equal(cr_active_count(root), 0L)
  }))
})

test_that("a second run for the same form is refused", {
  with_env(secrets, testServer(server, {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    other <- cr_try_acquire(root, 5L, form_id = "10267")            # e.g. the same code in another tab
    session$setInputs(cr_form = "10267", cr_fmt = "csv", cr_run = 1)
    expect_equal(cr$status, "idle")
    cr_release_slot(other); cr_discard(other)
  }))
})

test_that("a full server refuses politely", {
  with_env(secrets, testServer(server, {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    s1 <- cr_try_acquire(root, 1L); expect_true(!is.null(s1))
    Sys.setenv(IM_COUNTRY_MAX_RUNS = "1")
    session$setInputs(cr_form = "10267", cr_fmt = "csv", cr_run = 1)
    expect_equal(cr$status, "idle")
    Sys.unsetenv("IM_COUNTRY_MAX_RUNS"); cr_discard(s1)
  }))
})

cat("\ncountry-run app tests finished\n")
