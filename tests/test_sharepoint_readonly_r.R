# R-side read-only guard for SharePoint writers (sharepoint_recovery.R).  Run from the repo root:
#   Rscript tests/test_sharepoint_readonly_r.R      (needs a real httr2, i.e. >= 1.0)
suppressWarnings(source("scripts/sharepoint_recovery.R"))
library(testthat)
Sys.setenv(SHAREPOINT_TENANT_ID = "t", SHAREPOINT_CLIENT_ID = "c", SHAREPOINT_CLIENT_SECRET = "s")
f <- tempfile(); writeLines("x", f)

hits <- character()
recorder <- function(req) {
  hits <<- c(hits, paste(if (is.null(req$method)) "GET" else req$method, req$url))
  httr2::response_json(status_code = 200, body = list(access_token = "tok", id = "d1", value = list()))
}

test_that("normal mode: a backup does reach the network", {
  Sys.unsetenv("IM_READ_ONLY_SHAREPOINT"); hits <<- character()
  httr2::with_mocked_responses(recorder, try(suppressMessages(sp_backup_file(f, "a/b/c.txt")), silent = TRUE))
  expect_true(length(hits) > 0)
})

test_that("read-only mode: not a single request is made by any writer", {
  Sys.setenv(IM_READ_ONLY_SHAREPOINT = "1"); hits <<- character()
  httr2::with_mocked_responses(recorder, {
    expect_null(sp_backup_file(f, "a/b/c.txt"))
    expect_true(sp_ensure_folder("tok", "d1", "a/b/c")$ok)
    expect_equal(sp_prune_old_versions("tok", "d1", "a/b/c.txt", 1L), 0L)
  })
  expect_equal(hits, character())
  Sys.unsetenv("IM_READ_ONLY_SHAREPOINT")
})
cat("\nR read-only tests finished\n")
