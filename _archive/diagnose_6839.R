#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC: raw data structure of form 6839 (Ethiopia IM)
#
# This is READ-ONLY. It does not write to data/raw, data/final,
# or data/processed/qc, and does NOT run the batch pipeline.
# It reads 6839.parquet directly, profiles every one of its
# columns, and writes one small summary CSV to data/lookup/ so
# it can be inspected without pasting 696 columns into the console.
#
# It also runs a few targeted checks the user specifically asked
# about:
#   - is roundNumber captured per-household (inside the HH[n]/...
#     repeat group) instead of once per submission?
#   - does a genuine top-level 'Response' column exist at all?
#   - is the bare 'roundNumber' column (if any) a plain character
#     column, or did it come through as a list-column (which would
#     explain a `roundNumber = case_when(...)` type error even
#     though the case_when() logic itself is trivial)?
#
# Run with:  Rscript scripts\diagnose_6839.R
# Then either paste the console output back, or share the CSV at
# data/lookup/6839_structure_dump.csv.
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(tibble)
  library(arrow)
})

BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
input_file <- file.path(BASE_DIR, "data", "raw", "6839.parquet")
out_dir <- file.path(BASE_DIR, "data", "lookup")

if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(input_file)) stop("6839.parquet not found at: ", input_file)

cat("Reading 6839.parquet -- 174k rows x 696 cols, this can take a minute...\n")
t0 <- Sys.time()
data <- arrow::read_parquet(input_file) %>% as_tibble()
cat("Read in", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "sec.\n")
cat("rows:", nrow(data), " cols:", ncol(data), "\n\n")

# ------------------------------------------------------------
# Helpers that work whether a column is a normal vector or a
# list-column (repeat/select_multiple fields sometimes come
# through as list-columns from arrow).
# ------------------------------------------------------------
safe_sample_values <- function(x, n = 5) {
  if (is.list(x)) {
    non_empty <- Filter(function(v) length(v) > 0 && !all(is.na(unlist(v))), x)
    if (length(non_empty) == 0) return("")
    vals <- vapply(utils::head(non_empty, n), function(v) paste(as.character(unlist(v)), collapse = "|"), character(1))
    return(paste(vals, collapse = " ~~ "))
  }
  x <- x[!is.na(x)]
  if (length(x) == 0) return("")
  paste(as.character(utils::head(unique(x), n)), collapse = " ~~ ")
}

safe_n_unique <- function(x) {
  if (is.list(x)) {
    return(length(unique(vapply(x, function(v) paste(as.character(unlist(v)), collapse = "|"), character(1)))))
  }
  length(unique(x))
}

safe_pct_na <- function(x) {
  if (is.list(x)) {
    return(round(100 * mean(vapply(x, function(v) length(v) == 0 || all(is.na(unlist(v))), logical(1))), 2))
  }
  round(100 * mean(is.na(x)), 2)
}

# ------------------------------------------------------------
# FULL COLUMN STRUCTURE DUMP -> CSV
# ------------------------------------------------------------
cat("Profiling all", ncol(data), "columns (this is the slow part)...\n")
col_info <- tibble(
  index = seq_along(names(data)),
  column_name = names(data),
  r_class = vapply(data, function(x) paste(class(x), collapse = "/"), character(1)),
  is_list_column = vapply(data, is.list, logical(1)),
  is_hh_repeat_column = str_detect(names(data), "^HH\\[[0-9]+\\]"),
  n_unique = vapply(data, safe_n_unique, integer(1)),
  pct_na = vapply(data, safe_pct_na, numeric(1)),
  sample_values = vapply(data, safe_sample_values, character(1))
)

structure_out <- file.path(out_dir, "6839_structure_dump.csv")
write_csv(col_info, structure_out)
cat("Wrote full column structure (", nrow(col_info), "columns) to:\n  ", structure_out, "\n\n")

top_level <- col_info %>% filter(!is_hh_repeat_column)
cat("Top-level (non 'HH[n]/...') columns:", nrow(top_level), "\n")
cat("HH-repeat-group columns ('HH[n]/...'):", nrow(col_info) - nrow(top_level), "\n\n")

print_bucket <- function(df, title, pattern) {
  cat("\n=== Columns matching /", pattern, "/i ===\n", sep = "")
  hits <- df %>% filter(str_detect(column_name, regex(pattern, ignore_case = TRUE)))
  if (nrow(hits) == 0) {
    cat("  (none)\n")
  } else {
    print(as.data.frame(hits %>% select(column_name, r_class, is_hh_repeat_column, n_unique, pct_na, sample_values)))
  }
  invisible(hits)
}

round_cols    <- print_bucket(col_info, "round",    "round")
response_cols <- print_bucket(col_info, "response", "response")
vaccine_cols  <- print_bucket(col_info, "vaccine",  "vaccine")
date_cols     <- print_bucket(col_info, "date",     "date")
type_mon_cols <- print_bucket(col_info, "type",     "type.?monitoring")

cat("\n=== Standard required_columns exact-match presence check ===\n")
required_columns_check <- c(
  "Country", "Region", "District", "Response", "roundNumber",
  "Type_Monitoring", "date_monitored", "HH_count", "Total_U5_Present",
  "TotalFM", "sum_missed_children", "Total_Absent", "Total_refusal"
)
for (rc in required_columns_check) {
  cat(sprintf("  %-22s exact match: %s\n", rc, rc %in% names(data)))
}

# ------------------------------------------------------------
# DEDICATED CHECK: does roundNumber live inside the HH[n] repeat
# group (per-household) instead of / in addition to top level?
# ------------------------------------------------------------
hh_round_cols <- col_info %>%
  filter(is_hh_repeat_column, str_detect(column_name, regex("round", ignore_case = TRUE))) %>%
  pull(column_name)

cat("\n=== HH-repeat-level roundNumber-like columns:", length(hh_round_cols), "===\n")
if (length(hh_round_cols) > 0) {
  print(hh_round_cols)
  cat("\nFirst 15 rows across these columns (checking within-row consistency across households):\n")
  print(as.data.frame(data %>% select(all_of(hh_round_cols)) %>% utils::head(15)))
} else {
  cat("  (none found)\n")
}

hh_response_cols <- col_info %>%
  filter(is_hh_repeat_column, str_detect(column_name, regex("response", ignore_case = TRUE))) %>%
  pull(column_name)

cat("\n=== HH-repeat-level Response-like columns:", length(hh_response_cols), "===\n")
if (length(hh_response_cols) > 0) {
  print(hh_response_cols)
} else {
  cat("  (none found)\n")
}

# ------------------------------------------------------------
# DEDICATED CHECK: the exact bare 'roundNumber' / 'Response'
# columns, if they exist -- these are what the pipeline's
# find_similar_column() would pick up first.
# ------------------------------------------------------------
cat("\n=== DEDICATED CHECK: bare 'roundNumber' column ===\n")
if ("roundNumber" %in% names(data)) {
  rn <- data[["roundNumber"]]
  cat("class:", paste(class(rn), collapse = "/"), " | is.list:", is.list(rn), "\n")
  if (is.list(rn)) {
    cat("This IS a list-column -- likely why `roundNumber = case_when(...)` fails.\n")
    non_empty_idx <- which(vapply(rn, function(v) length(v) > 0, logical(1)))
    show_idx <- utils::head(non_empty_idx, 10)
    for (i in show_idx) cat(sprintf("  row %d: %s\n", i, paste(unlist(rn[[i]]), collapse = ", ")))
  } else {
    cat("Unique values (up to 30):\n")
    print(utils::head(sort(unique(as.character(rn))), 30))
    cat("Value counts:\n")
    print(table(as.character(rn), useNA = "always"))
  }
} else {
  cat("No bare 'roundNumber' column exists at the top level.\n")
}

cat("\n=== DEDICATED CHECK: bare 'Response' column ===\n")
if ("Response" %in% names(data)) {
  rv <- data[["Response"]]
  cat("class:", paste(class(rv), collapse = "/"), " | is.list:", is.list(rv), "\n")
  if (!is.list(rv)) {
    cat("Unique values (up to 30):\n")
    print(utils::head(sort(unique(as.character(rv))), 30))
  } else {
    cat("This IS a list-column.\n")
  }
} else {
  cat("No bare 'Response' column exists at the top level.\n")
}

cat("\n=== Type_Monitoring value counts (if present) ===\n")
if ("Type_Monitoring" %in% names(data)) {
  print(table(as.character(data$Type_Monitoring), useNA = "always"))
} else {
  cat("Type_Monitoring column not present.\n")
}

cat("\n=== Country / geography top-level columns (Country, Region, District, or similar) ===\n")
geo_cols <- top_level %>% filter(str_detect(column_name, regex("^(country|region|district)$", ignore_case = TRUE)))
print(as.data.frame(geo_cols %>% select(column_name, r_class, n_unique, pct_na, sample_values)))

cat("\n=== ALL top-level (non-repeat) column names (", nrow(top_level), " total) ===\n", sep = "")
print(top_level$column_name)

cat("\nDone. Structure CSV written to:\n  ", structure_out, "\n")
cat("Please paste back the console output above (or share the CSV).\n")
