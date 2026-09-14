#!/usr/bin/env Rscript

# IM Workflow Diagnostic Tool
# Run this to verify your setup before running the main pipeline

cat("\n")
cat("=" %>% paste(rep(60), collapse = ""))
cat("\nIM WORKFLOW DIAGNOSTIC TOOL\n")
cat("=" %>% paste(rep(60), collapse = ""))
cat("\n\n")

# Check R packages
required_packages <- c("dplyr", "tidyr", "readr", "jsonlite", "arrow", "openxlsx", "lubridate", "logger")
cat("Checking required R packages:\n")
for (pkg in required_packages) {
  if (require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat(sprintf("  ✓ %s (version %s)\n", pkg, packageVersion(pkg)))
  } else {
    cat(sprintf("  ✗ %s - NOT INSTALLED\n", pkg))
    cat(sprintf("    Install with: install.packages('%s')\n", pkg))
  }
}

# Check Python
cat("\nChecking Python environment:\n")
python_path <- Sys.which("python")
if (python_path != "") {
  cat(sprintf("  ✓ Python found at: %s\n", python_path))
  python_version <- system2("python", "--version", stdout = TRUE, stderr = TRUE)
  cat(sprintf("    Version: %s\n", python_version[1]))
} else {
  cat("  ✗ Python not found in PATH\n")
}

# Check directory structure
cat("\nChecking directory structure:\n")
root_dir <- "C:/Users/TOURE/Documents/im_workflow"
required_dirs <- c("config", "data/raw", "data/processed", "data/final", "data/lookup", "logs", "outputs", "scripts")

for (dir in required_dirs) {
  full_path <- file.path(root_dir, dir)
  if (dir.exists(full_path)) {
    cat(sprintf("  ✓ %s\n", dir))
  } else {
    cat(sprintf("  ✗ %s - MISSING\n", dir))
  }
}

# Check data files
cat("\nChecking data files:\n")
raw_dir <- file.path(root_dir, "data/raw")
if (dir.exists(raw_dir)) {
  parquet_files <- list.files(raw_dir, pattern = "\\.parquet$")
  json_files <- list.files(raw_dir, pattern = "\\.json$")
  
  cat(sprintf("  Parquet files: %d\n", length(parquet_files)))
  if (length(parquet_files) > 0) {
    cat(sprintf("    First few: %s\n", paste(head(parquet_files, 3), collapse = ", ")))
  }
  
  cat(sprintf("  JSON files: %d\n", length(json_files)))
} else {
  cat("  ✗ Raw data directory not found\n")
}

# Check lookup files
cat("\nChecking lookup files:\n")
lookup_file <- file.path(root_dir, "data/lookup/lookup.xlsx")
if (file.exists(lookup_file)) {
  file_size <- file.info(lookup_file)$size
  cat(sprintf("  ✓ lookup.xlsx found (%.2f MB)\n", file_size / 1024 / 1024))
} else {
  cat("  ✗ lookup.xlsx not found\n")
}

# Check scripts
cat("\nChecking script files:\n")
scripts_dir <- file.path(root_dir, "scripts")
if (dir.exists(scripts_dir)) {
  r_scripts <- list.files(scripts_dir, pattern = "\\.R$")
  py_scripts <- list.files(scripts_dir, pattern = "\\.py$")
  
  cat(sprintf("  R scripts: %d\n", length(r_scripts)))
  cat(sprintf("  Python scripts: %d\n", length(py_scripts)))
  
  # Check for main pipeline script
  if ("run_pipeline.R" %in% r_scripts) {
    cat("  ✓ run_pipeline.R found\n")
  } else {
    cat("  ✗ run_pipeline.R not found - please save the main script\n")
  }
} else {
  cat("  ✗ Scripts directory not found\n")
}

cat("\n" %>% paste(rep(60), collapse = ""))
cat("\nDIAGNOSTIC COMPLETE\n")
cat("=" %>% paste(rep(60), collapse = ""))
cat("\n\n")