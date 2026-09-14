#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC: why does form 8832 fail on `Vaccine.type = case_when(...)`
# in regional_im_repository_builder.R?
#
# This is READ-ONLY. It does not write any files, does not touch
# data/raw or data/final, and does NOT run the full batch pipeline --
# it loads only the function/constant definitions from
# regional_im_repository_builder.R (everything before the
# "RUN FULL PIPELINE" driver line), then manually walks form 8832
# through the same early steps process_im_file() uses, printing
# column names/types/duplicates at each stage so we can see exactly
# what breaks assign_vaccine_types().
#
# Run with:  Rscript scripts\diagnose_8832.R
# Then paste the full console output back.
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

if (!file.exists(builder_script)) {
  stop("Could not find regional_im_repository_builder.R at: ", builder_script)
}

lines <- readLines(builder_script, warn = FALSE, encoding = "UTF-8")
cut_idx <- grep("^batch_run <- process_all_im_files", lines)[1]

if (is.na(cut_idx)) {
  stop("Could not find the 'batch_run <- process_all_im_files' marker line -- ",
       "the source file may have changed since this diagnostic was written.")
}

def_lines <- lines[seq_len(cut_idx - 1)]

env <- new.env()
eval(parse(text = def_lines), envir = env)

cat("Loaded", length(ls(env)), "functions/constants from regional_im_repository_builder.R\n")
cat("(batch runner NOT executed -- this is read-only)\n\n")

input_file <- file.path(BASE_DIR, "data", "raw", "8832.parquet")

if (!file.exists(input_file)) {
  stop("8832.parquet not found at: ", input_file)
}

file_name <- tools::file_path_sans_ext(basename(input_file))

show_dupes <- function(df, label) {
  d <- anyDuplicated(names(df))
  cat(sprintf("[%s] duplicated column names: %s\n", label, d))
  if (d > 0) {
    dup_names <- unique(names(df)[duplicated(names(df)) | duplicated(names(df), fromLast = TRUE)])
    cat("  -> duplicate name(s):", paste(dup_names, collapse = ", "), "\n")
  }
}

show_col <- function(df, cn, label) {
  if (!cn %in% names(df)) {
    cat(sprintf("  [%s] '%s': MISSING\n", label, cn))
    return(invisible())
  }
  matches <- sum(names(df) == cn)
  col_obj <- df[[cn]]
  vals <- tryCatch(utils::head(unique(as.character(col_obj)), 6), error = function(e) "<could not coerce to character>")
  cat(sprintf(
    "  [%s] '%s': %d column(s) with this name | class=%s | is.list=%s | sample values: %s\n",
    label, cn, matches, paste(class(col_obj), collapse = "/"), is.list(col_obj),
    paste(vals, collapse = " | ")
  ))
}

cols_to_check <- c("Country", "Response", "roundNumber", "Region", "District", "Type_Monitoring")

cat("=== STEP 1: read_input_data() ===\n")
data <- env$read_input_data(input_file)
cat("rows:", nrow(data), " cols:", ncol(data), "\n")
show_dupes(data, "raw")
for (cn in cols_to_check) show_col(data, cn, "raw")

cat("\n=== STEP 2: ensure Country exists ===\n")
if (!"Country" %in% names(data)) {
  cat("No 'Country' column -> setting to NA_character_ for all rows\n")
  data$Country <- NA_character_
}

cat("\n=== STEP 3: apply_country_specific_transformations() + rename_repetitive_columns() ===\n")
data <- env$apply_country_specific_transformations(data, file_name)
data <- env$rename_repetitive_columns(data)
show_dupes(data, "after rename")
for (cn in cols_to_check) show_col(data, cn, "after rename")

cat("\n=== STEP 4: select_columns_dynamically() + select() ===\n")
active_hh_patterns <- env$hh_patterns_standard
columns_to_select <- env$select_columns_dynamically(data, env$required_columns, active_hh_patterns)
cat("columns selected:", length(columns_to_select), " | duplicated in selection list:", anyDuplicated(columns_to_select), "\n")

GF <- data %>% env$safe_filter_data() %>% select(any_of(columns_to_select))
if (nrow(GF) == 0) {
  cat("Warning: 0 rows after safe_filter_data() -- falling back to unfiltered data (same as process_im_file)\n")
  GF <- data %>% select(any_of(columns_to_select))
}
cat("GF rows:", nrow(GF), " cols:", ncol(GF), "\n")
show_dupes(GF, "GF (post-select)")
for (cn in cols_to_check) show_col(GF, cn, "GF")

cat("\n=== STEP 5: standardize_districts() -> standardize_responses() -> assign_vaccine_types() ===\n")
cat("(this is where the real pipeline throws 'Vaccine.type = case_when(...)')\n\n")

result <- tryCatch({
  GJ <- GF %>% env$standardize_districts()
  cat("standardize_districts() OK\n")
  GO <- GJ %>% env$standardize_responses()
  cat("standardize_responses() OK\n")
  GK <- GO %>% env$assign_vaccine_types()
  cat("assign_vaccine_types() OK -- no error reproduced this run.\n")
  cat("\nVaccine.type value counts:\n")
  print(table(GK$Vaccine.type, useNA = "always"))
  "ok"
}, error = function(e) {
  cat("\n>>> REPRODUCED THE ERROR <<<\n")
  cat("Message: ", conditionMessage(e), "\n")
  cat("Call:    ")
  print(conditionCall(e))
  if (!is.null(rlang::last_trace)) {
    cat("\n--- rlang trace (if available) ---\n")
    tryCatch(print(rlang::last_trace()), error = function(e2) cat("(no rlang trace captured)\n"))
  }
  "error"
})

cat("\n=== Done. Please paste this entire output back. ===\n")
