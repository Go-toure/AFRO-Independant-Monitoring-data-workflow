# Offline tests for the raw-download request validation + SharePoint path guard.
# Run from the repo root:  Rscript tests/test_rawdl_guard.R
suppressPackageStartupMessages(library(testthat))
source("shiny_app/R/data_source_sharepoint.R")
source("shiny_app/R/data_download_raw.R")

test_that("sp_path_ok: legitimate paths pass", {
  expect_true(sp_path_ok(RAW_STATE_FOLDER))
  expect_true(sp_path_ok(paste0(RAW_STATE_FOLDER, "/10267.parquet")))
  expect_true(sp_path_ok(sp_partition_folder("4498")))
  expect_true(sp_path_ok(paste0(sp_partition_folder("4498"), "/4498_2023.parquet")))
  expect_true(sp_path_ok(paste(SP_TARGET_FOLDER, SP_REMOTE_CSV, sep = "/")))
})

test_that("sp_path_ok: traversal and tricks are refused", {
  bad <- c("", NA, "/abs/path", "a/../b", "a/./b", "..", ".", "a/..", "a//b", "a/b/", "a\\b", "a?x=1", "a#f", "a%2e%2e/b",
           "C:/x", "a\nb", "a\tb", "a:b", "a|b", "a\"b", "a/ ../b", "a/.. /b", "a/...", strrep("a", 500))
  for (b in bad) expect_false(sp_path_ok(b), info = paste0("[", b, "]"))
  expect_false(sp_path_ok(NULL)); expect_false(sp_path_ok(c("a", "b"))); expect_false(sp_path_ok(1))
  expect_false(sp_path_ok(paste0(sp_partition_folder("10267"), "/10267_x/../../../4498.parquet")))
})

test_that("low-level helpers never reach the network for a refused path", {
  # No httr2 call can happen: a refused path returns before any request is built.
  expect_equal(sp_list_folder("t", "d", "a/../b"), list())
  expect_false(sp_download_file("t", "d", "a/../b", tempfile()))
  expect_null(sp_get_item_metadata("t", "d", "../x"))
})

test_that("request validators", {
  expect_true(.rd_form_ok("10267")); expect_false(.rd_form_ok("1026a")); expect_false(.rd_form_ok("../1"))
  expect_false(.rd_form_ok("")); expect_false(.rd_form_ok(NA_character_)); expect_false(.rd_form_ok(NULL))
  expect_false(.rd_form_ok("123456789")); expect_false(.rd_form_ok(c("1", "2")))
  expect_true(.rd_year_ok(NULL)); expect_true(.rd_year_ok("2024"))
  for (y in c("x/../../../4498", "20245", "202", "2024.parquet", "", "__ALL__", "２０２４", NA_character_)) expect_false(.rd_year_ok(y), info = y)
  expect_true(.rd_year_arg_ok("__ALL__")); expect_true(.rd_year_arg_ok("")); expect_true(.rd_year_arg_ok("2023"))
  expect_false(.rd_year_arg_ok("../../1"))
  expect_true(.rd_text_ok("Yes")); expect_true(.rd_text_ok("CHD-2023-10-1_nOPV")); expect_true(.rd_text_ok(NULL))
  expect_false(.rd_text_ok(strrep("a", 101))); expect_false(.rd_text_ok("a\nb")); expect_false(.rd_text_ok(c("a", "b")))
})

# Mocked backend: records every SharePoint call the builders would make.
calls <- character()
with_mocks <- function(code) {
  calls <<- character()
  assign("sharepoint_credentials_available", function() TRUE, envir = globalenv())
  assign("sp_get_graph_token",   function() { calls <<- c(calls, "token"); "tok" }, envir = globalenv())
  assign("sp_resolve_drive_id",  function(token) { calls <<- c(calls, "drive"); "drv" }, envir = globalenv())
  assign("sp_list_folder",       function(token, drive_id, folder_path) { calls <<- c(calls, paste0("list:", folder_path)); list() }, envir = globalenv())
  assign("sp_download_file",     function(token, drive_id, remote_path, local_path) { calls <<- c(calls, paste0("dl:", remote_path)); FALSE }, envir = globalenv())
  force(code)
}

test_that("forged values never produce a SharePoint call", {
  with_mocks({
    expect_equal(list_available_years("../4498"), character(0))
    expect_equal(list_available_responses("10267", "x/../../../4498"), character(0))
    expect_equal(list_available_rounds("10267", "2024", strrep("a", 500)), character(0))
    expect_equal(list_available_rounds("10267", "../..", "Yes"), character(0))
    for (fmt in c("../../etc", "docx", NA, ""))
      expect_false(build_form_download("10267", fmt)$ok)
    expect_false(build_form_download("10267", c("csv", "xlsx"))$ok)
    expect_false(build_form_download("10267", "csv", year = "x/../../../4498")$ok)
    expect_false(build_form_download("10267", "csv", year = "2024", response = "a\nb")$ok)
    expect_false(build_form_download("../10267", "csv")$ok)
    expect_false(build_form_download("10267;rm", "parquet")$ok)
    expect_equal(calls, character(0))
  })
})

test_that("valid requests still reach SharePoint (and only the intended paths)", {
  with_mocks({
    r <- build_form_download("10267", "csv", year = "2024")
    expect_false(r$ok)                                   # mock returns nothing; we only look at the paths
    expect_true(length(calls) > 0)
    paths <- sub("^(list|dl):", "", grep("^(list|dl):", calls, value = TRUE))
    expect_true(all(startsWith(paths, RAW_STATE_FOLDER)))
    expect_false(any(grepl("\\.\\.", paths)))
    list_available_years("10267")
    expect_true(any(grepl("partitions/10267$", calls)))
  })
})

cat("\nraw-download guard tests finished\n")
