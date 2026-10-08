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
secrets <- c(IM_ADMIN_CODES = "ADMIN-ONE", IM_COUNTRY_CODES = "AGO=ang-1234;NGA+GHA=nga-gha-9")

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
    session$setInputs(auth_code = "ang-1234", auth_submit = 1)
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
    session$setInputs(auth_code = "nga-gha-9", auth_submit = 1)
    expect_equal(sort(rv$data$v), c(2L, 4L))
  }))
})

test_that("admin code: everything, admin action allowed, any form", {
  with_env(secrets, testServer(make_server(df), {
    session$setInputs(auth_code = "ADMIN-ONE", auth_submit = 1)
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
    session$setInputs(auth_code = "ang-1234", auth_submit = 1)
    session$setInputs(auth_code = "ADMIN-ONE", auth_submit = 2)
    expect_equal(auth$user()$role, "country")
    expect_equal(rv$data$v, c(1L, 3L))
  }))
})

test_that("open mode (no secrets): admin without a code (legacy local behaviour)", {
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = ""), testServer(make_server(df), {
    session$flushReact()
    tv <- list(user = auth$user(), data = rv$data)
    expect_equal(tv$user$role, "admin")
    expect_equal(nrow(tv$data), 4L)
  }))
})

test_that("only country secrets set: nobody becomes admin (fails closed)", {
  with_env(c(IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "AGO=ang-1234"), testServer(make_server(df), {
    session$setInputs(auth_code = "ADMIN-ONE", auth_submit = 1)
    expect_null(auth$user())
    session$setInputs(auth_code = "ang-1234", auth_submit = 2)
    expect_equal(auth$user()$role, "country")
  }))
})

cat("\nsession tests finished\n")
