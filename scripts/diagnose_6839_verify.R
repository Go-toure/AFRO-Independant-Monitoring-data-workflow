#!/usr/bin/env Rscript
# ============================================================
# VERIFY: end-to-end test of the form 6839 (Ethiopia) fix in
# regional_im_repository_builder.R.
#
# READ-ONLY. Sources only the function/constant definitions (not
# the batch driver), then runs the REAL process_im_file() on
# 6839.parquet, writing only to a TEMP folder -- your real
# data/final and data/processed/qc are untouched.
#
# Prints: success/failure, row counts before/after the
# Response/roundNumber whitelist, and the distribution of
# Response / roundNumber / Vaccine.type in the surviving rows, so
# we can confirm the ~112K unrecoverable place-name rows were
# dropped and the ~62K clean rows came through correctly mapped.
#
# Run with:  Rscript scripts\diagnose_6839_verify.R
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(tibble)
  library(arrow)
})

BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
builder_script <- file.path(BASE_DIR, "scripts", "regional_im_repository_builder.R")
input_file <- file.path(BASE_DIR, "data", "raw", "6839.parquet")

lines <- readLines(builder_script, warn = FALSE, encoding = "UTF-8")
cut_idx <- grep("^batch_run <- process_all_im_files", lines)[1]
if (is.na(cut_idx)) stop("Could not find the 'batch_run <- process_all_im_files' marker line.")
def_lines <- lines[seq_len(cut_idx - 1)]

env <- new.env()
eval(parse(text = def_lines), envir = env)
cat("Loaded", length(ls(env)), "functions/constants from regional_im_repository_builder.R\n\n")

file_name <- tools::file_path_sans_ext(basename(input_file))

cat("=== Sanity check: derive_ethiopia_6839_response_round() in isolation ===\n")
raw <- arrow::read_parquet(input_file) %>% as_tibble()
fixed <- env$derive_ethiopia_6839_response_round(raw)
cat("Rows total:", nrow(fixed), "\n")
cat("Rows with a resolved (non-NA) Response:", sum(!is.na(fixed$Response)), "\n")
cat("Rows with a resolved (non-NA) roundNumber:", sum(!is.na(fixed$roundNumber)), "\n\n")

cat("Resolved Response value counts:\n")
print(table(fixed$Response, useNA = "always"))
cat("\nResolved roundNumber value counts:\n")
print(table(fixed$roundNumber, useNA = "always"))

cat("\n=== Full end-to-end process_im_file() (writes to a TEMP folder only) ===\n")
tmp_out <- file.path(tempdir(), "diagnose_6839_out")
tmp_qc <- file.path(tempdir(), "diagnose_6839_qc")
dir.create(tmp_out, showWarnings = FALSE, recursive = TRUE)
dir.create(tmp_qc, showWarnings = FALSE, recursive = TRUE)

result <- tryCatch({
  res <- env$process_im_file(
    input_file = input_file,
    output_folder = tmp_out,
    qc_output_folder = tmp_qc,
    lookup_table = env$lookup_table
  )
  if (is.null(res$data)) {
    cat(">>> process_im_file() returned NULL data. <<<\n")
    NULL
  } else {
    cat("process_im_file() SUCCEEDED end-to-end.\n")
    cat("rows_output (aggregated Country/Region/District/Response/Vaccine.type/roundNumber groups):",
        nrow(res$data), "\n")
    cat("rows_qc:", if (is.null(res$qc)) 0 else nrow(res$qc), "\n\n")
    cat("Vaccine.type distribution in output:\n")
    print(table(res$data$Vaccine.type, useNA = "always"))
    cat("\nroundNumber distribution in output:\n")
    print(table(res$data$roundNumber, useNA = "always"))
    cat("\nDistinct Response values in output:\n")
    print(sort(unique(res$data$Response)))
    cat("\nSample rows:\n")
    print(as.data.frame(utils::head(res$data %>% select(Country, Region, District, Response, Vaccine.type, roundNumber, u5_present, u5_FM, Number_of_HH_visited), 10)))
    res
  }
}, error = function(e) {
  cat("\n>>> FAILED in process_im_file() <<<\n")
  cat("Message: ", conditionMessage(e), "\n")
  cat("Call:    ")
  print(conditionCall(e))
  NULL
})

cat("\n=== Done. ===\n")
if (!is.null(result)) {
  cat("Form 6839 processes cleanly with the new Response/roundNumber fix.\n")
} else {
  cat("Still failing -- please paste the full output back.\n")
}
