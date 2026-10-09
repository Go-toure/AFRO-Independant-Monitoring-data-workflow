# Session-level tests for ac_session_init() using shiny::testServer.
# Needs: shiny, bslib, shinyjs, testthat.   Run:  Rscript tests/test_access_session.R
suppressPackageStartupMessages({ library(shiny); library(testthat) })
CONFIG_DIR <- "config"
source("shiny_app/R/access_control.R")

with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA)
  do.call(Sys.setenv, as.list(vars))
  on.exit(for (n in names(old)) if (is.na(old[[n]])) Sys.unsetenv(n) else do.call(Sys.setenv, setNames(list(old[[n]]), n)))
  force(code)
}

# A tiny server: the same wiring app.R uses, plus a data load and a guarded action.
make_server <- function(df) {
  function(input, output, session) {
    auth <- ac_session_init(input, output, session)
    rv <- reactiveValues(data = NULL, ran = 0L, dl_ok = NA)
    load_scoped <- function() ac_scope_data(df, auth$user())
    observe({ req(auth$user()); rv$data <- load_scoped() })
    observeEvent(input$run_fetch, { if (!auth$is_admin()) return(); rv$ran <- rv$ran + 1L })
    observeEvent(input$try_dl, { rv$dl_ok <- auth$form_ok(input$try_dl) })
  }
}

df <- data.frame(country = c("ANGOLA", "NIGERIA", "ANGOLA", "GHANA"), v = 1:4, stringsAsFactors = FALSE)
secrets <- c(IM_ADMIN_CODES = "ADMIN-ONE-0001", IM_COUNTRY_CODES = "AGO=ang-1234-code;NGA+GHA=nga-gha-9-code")

test_that("enforced mode: nothing loads before sign-in", {
  with_env(secrets, testServer(make_server(df), {
    session$flushReact()
    expect_null(rv$data)
    expect_null(auth$user())
  }))
})

test_that("wrong code is refused, no data", {
  with_env(secrets, testServer(make_server(df), {
    session$setInputs(auth_code = "wrong", auth_submit = 1)
    expect_null(auth$user())
    expect_null(rv$data)
  }))
})

test_that("country code: scoped data, admin action ignored, other form refused", {
  with_env(secrets, testServer(make_server(df), {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    tv <- list(user = auth$user(), data = rv$data)
    expect_equal(tv$user$role, "country")
    expect_equal(tv$data$v, c(1L, 3L))
    expect_true(all(tv$data$country == "ANGOLA"))
    session$setInputs(run_fetch = 1)           # forged click on an admin button
    expect_equal(rv$ran, 0L)
    session$setInputs(try_dl = "10267"); expect_true(rv$dl_ok)
    session$setInputs(try_dl = "7178");  expect_false(rv$dl_ok)
  }))
})

test_that("multi-country code", {
  with_env(secrets, testServer(make_server(df), {
    session$setInputs(auth_code = "nga-gha-9-code", auth_submit = 1)
    expect_equal(sort(rv$data$v), c(2L, 4L))
  }))
})

test_that("admin code: everything, admin action allowed, any form", {
  with_env(secrets, testServer(make_server(df), {
    session$setInputs(auth_code = "ADMIN-ONE-0001", auth_submit = 1)
    tv <- list(user = auth$user(), data = rv$data)
    expect_equal(tv$user$role, "admin")
    expect_equal(nrow(tv$data), 4L)
    session$setInputs(run_fetch = 1)
    expect_equal(rv$ran, 1L)
    session$setInputs(try_dl = "7178"); expect_true(rv$dl_ok)
  }))
})

test_that("a signed-in session cannot switch role by submitting another code", {
  with_env(secrets, testServer(make_server(df), {
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 1)
    session$setInputs(auth_code = "ADMIN-ONE-0001", auth_submit = 2)
    expect_equal(auth$user()$role, "country")
    expect_equal(rv$data$v, c(1L, 3L))
  }))
})

test_that("explicit open mode: admin without a code (legacy local behaviour)", {
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "", IM_ACCESS_MODE = "open"), testServer(make_server(df), {
    session$flushReact()
    tv <- list(user = auth$user(), data = rv$data)
    expect_equal(tv$user$role, "admin")
    expect_equal(nrow(tv$data), 4L)
  }))
})

test_that("only country secrets set: nobody becomes admin (fails closed)", {
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "AGO=ang-1234-code"), testServer(make_server(df), {
    session$setInputs(auth_code = "ADMIN-ONE-0001", auth_submit = 1)
    expect_null(auth$user())
    Sys.sleep(1.2)                                   # the wrong code started a 1 s lock
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 2)
    expect_equal(auth$user()$role, "country")
  }))
})

test_that("no secrets on a (non-Windows) server: nobody gets in", {
  skip_if(.Platform$OS.type == "windows")
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "", IM_ACCESS_MODE = ""), testServer(make_server(df), {
    session$flushReact()
    expect_null(auth$user()); expect_null(rv$data)
    session$setInputs(auth_code = "anything-at-all-123", auth_submit = 1)
    expect_null(auth$user()); expect_null(rv$data)
  }))
})

test_that("malformed secret never opens the dashboard", {
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "garbage-without-equals", IM_ACCESS_MODE = "open"), testServer(make_server(df), {
    session$flushReact()
    expect_null(auth$user())
    session$setInputs(auth_code = "garbage-without-equals", auth_submit = 1)
    expect_null(auth$user())
  }))
})

test_that("too-short configured codes cannot be used", {
  with_env(c(IM_ADMIN_CODES = "abc", IM_COUNTRY_CODES = ""), testServer(make_server(df), {
    session$setInputs(auth_code = "abc", auth_submit = 1)
    expect_null(auth$user())
  }))
})

test_that("lockout: a submission during the lock is ignored; 5 failures close the session", {
  with_env(secrets, testServer(make_server(df), {
    session$setInputs(auth_code = "wrong-code-0001", auth_submit = 1)       # fail 1 -> 1 s lock
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 2)         # inside the lock: ignored
    expect_null(auth$user())
    Sys.sleep(1.2)
    session$setInputs(auth_code = "ang-1234-code", auth_submit = 3)
    expect_equal(auth$user()$role, "country")
  }))
})

test_that("five wrong codes close the session; sanitized errors are switched on", {
  old <- options(ac.lock_scale = 0, shiny.sanitize.errors = FALSE); on.exit(options(old), add = TRUE)
  with_env(secrets, testServer(make_server(df), {
    expect_true(isTRUE(getOption("shiny.sanitize.errors")))
    for (i in 1:4) { session$setInputs(auth_code = paste0("wrong-code-000", i), auth_submit = i); expect_false(session$isClosed()) }
    session$setInputs(auth_code = "wrong-code-0005", auth_submit = 5)
    expect_true(session$isClosed())
    expect_null(auth$user())
  }))
})

test_that("sanitized errors are also on when unconfigured, off only in open mode", {
  skip_if(.Platform$OS.type == "windows")
  old <- options(shiny.sanitize.errors = FALSE); on.exit(options(old), add = TRUE)
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "", IM_ACCESS_MODE = ""), testServer(make_server(df), {
    expect_true(isTRUE(getOption("shiny.sanitize.errors")))
  }))
  options(shiny.sanitize.errors = FALSE)
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "", IM_ACCESS_MODE = "open"), testServer(make_server(df), {
    expect_false(isTRUE(getOption("shiny.sanitize.errors")))
  }))
})

test_that("an over-long code is rejected BEFORE any comparison happens", {
  n_cmp <- 0L
  orig <- ac_ct_equal
  assign("ac_ct_equal", function(a, b) { n_cmp <<- n_cmp + 1L; orig(a, b) }, envir = globalenv())
  on.exit(assign("ac_ct_equal", orig, envir = globalenv()), add = TRUE)
  r <- ac_authenticate(strrep("a", AC_MAX_CODE_LEN + 1L), "ADMIN-ONE-0001", ac_country_codes("AGO=ang-1234-code"),
                       ac_country_forms(), mode = "enforced")
  expect_null(r); expect_equal(n_cmp, 0L)
  ac_authenticate("ADMIN-ONE-0001", "ADMIN-ONE-0001", ac_country_codes("AGO=ang-1234-code"), ac_country_forms(), mode = "enforced")
  expect_gt(n_cmp, 0L)                                   # sanity: the counter does see normal comparisons
})

test_that("a huge code costs nothing and is refused", {
  with_env(secrets, testServer(make_server(df), {
    t0 <- Sys.time()
    session$setInputs(auth_code = strrep("a", 1e6), auth_submit = 1)
    expect_null(auth$user())
    expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  }))
})

cat("\nsession tests finished\n")
