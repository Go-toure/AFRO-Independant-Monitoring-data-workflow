#!/usr/bin/env Rscript
# ============================================================
# PER-COUNTRY RUN  (dashboard "My data" tab)
# ============================================================
#   Rscript scripts/run_country_workflow.R --home <scratch dir> --form-id <id>
#
# Fetches ONE country's form, builds a one-form repository from it and cleans
# the geonames -- the same three steps as the regional pipeline, but:
#   * everything happens inside a private, throw-away scratch folder (--home);
#     the regional data/ and logs/ folders are never touched;
#   * IM_READ_ONLY_SHAREPOINT=1, so SharePoint can be READ (to resume from the
#     published raw state) but nothing is ever written, created or deleted
#     there (enforced in scripts/_sharepoint_client.py);
#   * the dashboard's access codes / API keys are removed from the environment
#     of every child process;
#   * only short, filtered progress lines reach stdout (the dashboard shows
#     them to the country user); full step logs stay in <home>/logs/ and are
#     never displayed unfiltered.
#
# Exit status 0 = the cleaned file exists; 1 = something failed (stdout says
# what). <home>/run_result.json is always written.
#
# Hidden test options: --repo <dir> (use another checkout's scripts/),
# --timeouts fetch,build,clean (minutes).
# ============================================================

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NA_character_) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[i + 1L]
}

this_file <- normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1]), mustWork = FALSE)
repo_dir <- normalizePath(get_arg("--repo", dirname(dirname(this_file))), mustWork = FALSE)
scripts_dir <- file.path(repo_dir, "scripts")

say <- function(...) { cat("[country-run] ", ..., "\n", sep = ""); flush.console() }

# ── arguments ───────────────────────────────────────────────────────────────
home    <- get_arg("--home")
form_id <- get_arg("--form-id")
if (is.na(home) || !nzchar(home)) { say("ERROR: --home is required"); quit(status = 2) }
if (is.na(form_id) || !grepl("^[0-9]{1,8}$", form_id)) { say("ERROR: --form-id must be a number"); quit(status = 2) }

dir.create(home, showWarnings = FALSE, recursive = TRUE)
home <- normalizePath(home, mustWork = TRUE)
# Never run inside the real workflow / repo folder.
if (identical(home, repo_dir) || file.exists(file.path(home, ".git")) ||
    file.exists(file.path(home, "shiny_app")) || file.exists(file.path(home, "scripts", "Fetch_im_data.py"))) {
  say("ERROR: --home must be an empty scratch folder, not the workflow folder")
  quit(status = 2)
}

timeouts <- suppressWarnings(as.numeric(strsplit(get_arg("--timeouts", "45,40,25"), ",")[[1]]))
if (length(timeouts) != 3L || anyNA(timeouts)) timeouts <- c(45, 40, 25)

result_file <- file.path(home, "run_result.json")
started <- Sys.time()
steps <- list(fetch = "pending", build = "pending", clean = "pending")

json_str <- function(x) paste0('"', gsub('(["\\\\])', "\\\\\\1", gsub("[\r\n]+", " ", as.character(x))), '"')
write_result <- function(ok, message = "", rows = NA) {
  fin <- function(p) file.exists(file.path(home, p))
  files <- c(cleaned_csv     = "data/final/Regional_IM_repository_cleaned.csv",
             cleaned_parquet = "data/final/Regional_IM_repository_cleaned.parquet",
             cleaned_rds     = "data/final/Regional_IM_repository_cleaned.rds",
             raw_parquet     = file.path("data/raw", paste0(form_id, ".parquet")))
  have <- names(files)[vapply(files, fin, logical(1))]
  txt <- sprintf(
    '{"ok": %s, "form_id": %s, "message": %s, "started": %s, "finished": %s, "fetch": %s, "build": %s, "clean": %s, "rows": %s, "files": [%s]}',
    if (ok) "true" else "false", json_str(form_id), json_str(message),
    json_str(format(started, "%Y-%m-%d %H:%M:%S")), json_str(format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    json_str(steps$fetch), json_str(steps$build), json_str(steps$clean),
    if (is.na(rows)) "null" else as.character(rows),
    paste(json_str(have), collapse = ", "))
  writeLines(txt, result_file)
}
fail <- function(msg) {
  say("FAILED: ", msg)
  write_result(FALSE, msg)
  quit(status = 1)
}

# ── scratch layout ──────────────────────────────────────────────────────────
for (d in c("data/raw", "data/final", "data/lookup", "data/processed/qc", "logs", "outputs", "scripts", "config"))
  dir.create(file.path(home, d), showWarnings = FALSE, recursive = TRUE)
# find_workflow_home() accepts IM_WORKFLOW_HOME only when scripts/run_workflow.R exists inside it.
writeLines("# stub: marks this scratch folder as a workflow home (see scripts/find_workflow_home.R)",
           file.path(home, "scripts", "run_workflow.R"))
src <- file.path(repo_dir, "config", "config.yaml")
if (file.exists(src)) file.copy(src, file.path(home, "config", "config.yaml"), overwrite = TRUE)
# secrets.env: copy ONLY what the fetch needs (SHAREPOINT_* read access, ONA_* data source) --
# an allowlist, so dashboard access codes, the AI key, mail/alert settings and any future secret
# stay behind (the child scripts load this file themselves).
src <- file.path(repo_dir, "config", "secrets.env")
if (file.exists(src)) {
  keep <- tryCatch(readLines(src, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  keep <- sub("^\ufeff", "", keep)                                   # a BOM must not hide the first key
  keep <- keep[grepl("^\\s*(SHAREPOINT_|ONA_)[A-Z0-9_]*\\s*=", keep)]          # allowlist, not a blocklist
  writeLines(keep, file.path(home, "config", "secrets.env"))
}

# ── environment for every child process ─────────────────────────────────────
Sys.setenv(IM_WORKFLOW_HOME = home, IM_READ_ONLY_SHAREPOINT = "1", IM_COUNTRY_RUN = "1")
Sys.setenv(IM_RUN_ID = paste0("country_", form_id, "_", format(started, "%Y%m%d_%H%M%S")))
# Blank (not unset): a child that loads a secrets file with "set if missing" semantics must not refill them.
Sys.setenv(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "", ANTHROPIC_API_KEY = "")

source(file.path(scripts_dir, "find_workflow_home.R"))   # defines find_python_cmd() only
python_cmd <- tryCatch(find_python_cmd(), error = function(e) NA_character_)
if (is.na(python_cmd)) fail("Python is not available on this server.")
rscript_cmd <- file.path(R.home("bin"), "Rscript")

# ── progress filtering: nothing sensitive reaches the country user ─────────
BLOCKED <- paste0("(?i)sharepoint|graph\\.microsoft|https?://|file:|token|secret|passw|tenant|client[_ -]?(id|secret)|",
                  "api[_ -]?key|authorization|bearer|\\.env|traceback|site[_ -]?id|drive[_ -]?id|raw_state|lookup_state|",
                  "site-packages|^File \"|\\.py\\b|host=|\\.(org|com|net|int|io|gov|edu)\\b")
PATHLIKE <- "(?:[A-Za-z]:)?[\\\\/](?=[^\\s'\"()<>]*[A-Za-z_])[^\\s'\"()<>]+[\\\\/]\\S*"
sanitize_line <- function(x) {
  tryCatch({
    x <- iconv(as.character(x), from = "", to = "ASCII", sub = "")     # invalid bytes must never break the run
    if (is.na(x)) return(NA_character_)
    x <- gsub("\033\\[[0-9;]*[A-Za-z]", "", x)
    x <- trimws(gsub("[^\\x20-\\x7E]", "", x, perl = TRUE))
    if (!nzchar(x) || grepl(BLOCKED, x, perl = TRUE)) return(NA_character_)
    x <- gsub(home, "<work>", x, fixed = TRUE)
    x <- gsub(repo_dir, "<app>", x, fixed = TRUE)
    x <- gsub(PATHLIKE, "<path>", x, perl = TRUE)
    if (nchar(x) > 140L) x <- paste0(substr(x, 1L, 137L), "...")
    x
  }, error = function(e) NA_character_)
}
sanitize_tail <- function(file, n = 8L) {
  if (!file.exists(file)) return(character())
  l <- tryCatch(readLines(file, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  l <- vapply(utils::tail(l, 60L), sanitize_line, character(1), USE.NAMES = FALSE)
  utils::tail(l[!is.na(l)], n)
}

# ── run one step as a child process with a heartbeat and a timeout ─────────
run_step <- function(label, cmd, cmd_args, log_name, timeout_min) {
  logf <- file.path(home, "logs", log_name)
  say(label, " ...")
  p <- processx::process$new(cmd, cmd_args, stdout = logf, stderr = "2>&1",
                             wd = home, cleanup_tree = TRUE)
  t0 <- Sys.time(); last_beat <- t0; last_shown <- ""
  while (p$is_alive()) {
    Sys.sleep(2)
    el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    if (el > timeout_min) {
      try(p$kill_tree(), silent = TRUE)
      say(label, ": stopped after ", timeout_min, " minutes (time limit)")
      return(124L)
    }
    if (as.numeric(difftime(Sys.time(), last_beat, units = "secs")) >= 20) {
      last_beat <- Sys.time()
      # Only a plain "still working" heartbeat: the child scripts' own lines (memory stats, process
      # notes, ...) are internal detail and are not shown to country users.
      say(label, " ... still working (", sprintf("%.0f", el * 60), "s)")
    }
  }
  st <- p$get_exit_status()
  if (is.na(st)) st <- 1L
  st
}

# ── STEP 0: campaign calendar ───────────────────────────────────────────────
helper <- file.path(scripts_dir, "country_run_helper.py")
if (file.exists(helper)) {
  st <- run_step("Preparing", python_cmd,
                 c(helper, "seed-lookup", "--home", home,
                   "--repo-lookup", file.path(Sys.getenv("IM_SOURCE_HOME", repo_dir), "data", "lookup", "lookup.xlsx")),
                 "step0_lookup.txt", 5)
  for (l in sanitize_tail(file.path(home, "logs", "step0_lookup.txt"), 3L)) say(sub("^\\[country-run\\] ?", "", l))
}

# ── STEP 1: fetch ───────────────────────────────────────────────────────────
fetch_script <- file.path(scripts_dir, "Fetch_im_data.py")
if (!file.exists(fetch_script)) fail("The fetch script is missing on this server.")
st <- run_step("1/3 Fetching the latest data", python_cmd,
               c(fetch_script, "--base-dir", home, "--form-ids", form_id),
               "step1_fetch.txt", timeouts[1])
raw_file <- file.path(home, "data", "raw", paste0(form_id, ".parquet"))
if (st == 0L && file.exists(raw_file)) {
  steps$fetch <- "ok"
  say("1/3 Fetch complete")
} else if (file.exists(raw_file)) {
  steps$fetch <- "warning"
  say("1/3 The data source could not be refreshed; continuing with the latest published data")
  for (l in sanitize_tail(file.path(home, "logs", "step1_fetch.txt"), 4L)) say("   ", l)
} else {
  steps$fetch <- "failed"
  for (l in sanitize_tail(file.path(home, "logs", "step1_fetch.txt"), 8L)) say("   ", l)
  fail("No data could be fetched for this form.")
}

# ── STEP 2: build the (one-form) repository ─────────────────────────────────
build_script <- file.path(scripts_dir, "regional_im_repository_builder.R")
if (!file.exists(build_script)) fail("The build script is missing on this server.")
st <- run_step("2/3 Processing the data", rscript_cmd, build_script, "step2_build.txt", timeouts[2])
if (st != 0L) {
  steps$build <- "failed"
  for (l in sanitize_tail(file.path(home, "logs", "step2_build.txt"), 8L)) say("   ", l)
  fail("Processing the data failed.")
}
steps$build <- "ok"
say("2/3 Processing complete")

# ── STEP 3: clean geonames ──────────────────────────────────────────────────
clean_script <- file.path(scripts_dir, "clean_geonames.R")
if (!file.exists(clean_script)) fail("The cleaning script is missing on this server.")
st <- run_step("3/3 Cleaning the data", rscript_cmd, clean_script, "step3_clean.txt", timeouts[3])
cleaned_csv <- file.path(home, "data", "final", "Regional_IM_repository_cleaned.csv")
if (st != 0L || !file.exists(cleaned_csv)) {
  steps$clean <- "failed"
  for (l in sanitize_tail(file.path(home, "logs", "step3_clean.txt"), 8L)) say("   ", l)
  fail("Cleaning the data failed.")
}
steps$clean <- "ok"

rows <- NA
sm <- file.path(home, "data", "final", "IM_processing_summary.csv")
if (file.exists(sm)) rows <- tryCatch(sum(utils::read.csv(sm)$rows_output, na.rm = TRUE), error = function(e) NA)
write_result(TRUE, "Done", rows)
say("DONE - your cleaned data is ready to download", if (!is.na(rows)) paste0(" (", format(rows, big.mark = ","), " rows)") else "")
quit(status = 0)
