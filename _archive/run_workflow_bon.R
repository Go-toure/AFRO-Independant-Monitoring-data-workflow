#!/usr/bin/env Rscript
# ============================================================
# UNIFIED IM WORKFLOW LAUNCHER
# Orchestrates: Fetch -> Build Repository -> Clean Geonames -> Upload to SharePoint -> Reports (Optional)
# ============================================================

suppressPackageStartupMessages({
  library(logger)
  library(fs)
})

# Configuration
BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
LOGS_DIR <- file.path(BASE_DIR, "logs")
SCRIPTS_DIR <- file.path(BASE_DIR, "scripts")

# Create directories
dir.create(LOGS_DIR, showWarnings = FALSE, recursive = TRUE)

# Setup logging
log_file <- file.path(LOGS_DIR, paste0("workflow_", Sys.Date(), ".log"))
log_appender(appender_file(log_file))
log_threshold(INFO)

log_info("============================================================")
log_info("IM WORKFLOW LAUNCHER")
log_info("============================================================")
log_info("Start time: {Sys.time()}")
log_info("Working directory: {BASE_DIR}")

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
skip_fetch <- "--skip-fetch" %in% args
skip_build <- "--skip-build" %in% args
skip_clean <- "--skip-clean" %in% args
skip_upload <- "--skip-upload" %in% args
skip_reports <- "--skip-reports" %in% args
force_fetch <- "--force-fetch" %in% args
upload_only <- "--upload-only" %in% args

log_info("Options:")
log_info("  Skip fetch: {skip_fetch}")
log_info("  Skip build: {skip_build}")
log_info("  Skip clean: {skip_clean}")
log_info("  Skip upload: {skip_upload}")
log_info("  Skip reports: {skip_reports}")
log_info("  Force fetch: {force_fetch}")
log_info("  Upload only: {upload_only}")

# Record start time
start_time <- Sys.time()

# ============================================================
# FUNCTION: Upload to SharePoint
# ============================================================

upload_to_sharepoint <- function(upload_args = "--all") {
  log_info("\n[STEP 4] Uploading files to SharePoint...")
  
  upload_script <- file.path(SCRIPTS_DIR, "upload_to_sharepoint.py")
  
  if (!file.exists(upload_script)) {
    log_warn("SharePoint upload script not found: {upload_script}")
    log_info("Skipping SharePoint upload")
    return(FALSE)
  }
  
  # Run the Python upload script
  cmd <- sprintf("python \"%s\" %s", upload_script, upload_args)
  log_info("Running: {cmd}")
  
  result <- system(cmd, intern = TRUE, ignore.stderr = FALSE)
  
  # Check if upload was successful
  if (any(grepl("SUCCESS|ALL FILES UPLOADED", result, ignore.case = TRUE))) {
    log_info("SharePoint upload completed successfully")
    # Print the SharePoint URL from output
    sharepoint_url <- grep("https://.*sharepoint.*", result, value = TRUE)
    if (length(sharepoint_url) > 0) {
      log_info("Files available at: {sharepoint_url[1]}")
    }
    return(TRUE)
  } else if (any(grepl("No files found", result, ignore.case = TRUE))) {
    log_warn("No files found to upload. Run workflow first.")
    return(FALSE)
  } else {
    log_warn("SharePoint upload may have had issues")
    for (line in result) {
      if (grepl("FAIL|ERROR", line, ignore.case = TRUE)) {
        log_warn("{line}")
      }
    }
    return(FALSE)
  }
}

# ============================================================
# UPLOAD ONLY MODE
# ============================================================

if (upload_only) {
  log_info("\n============================================================")
  log_info("UPLOAD ONLY MODE")
  log_info("============================================================")
  
  upload_result <- upload_to_sharepoint("--all")
  
  if (upload_result) {
    log_info("Upload completed successfully")
    cat("\n============================================================\n")
    cat("UPLOAD COMPLETED SUCCESSFULLY\n")
    cat("============================================================\n")
  } else {
    log_error("Upload failed")
    quit(status = 1)
  }
  
  quit(status = 0)
}

# ============================================================
# STEP 1: Fetch Data (Python)
# ============================================================

if (!skip_fetch) {
  log_info("\n[STEP 1] Fetching IM data...")
  
  fetch_scripts <- c(
    file.path(SCRIPTS_DIR, "Fetch_im_data_LIVE_UPDATED.py"),
    file.path(SCRIPTS_DIR, "Fetch_im_data.py")
  )
  
  fetch_script <- fetch_scripts[file.exists(fetch_scripts)][1]
  
  if (!is.na(fetch_script)) {
    cmd <- sprintf("python \"%s\"", fetch_script)
    if (force_fetch) cmd <- paste(cmd, "--force-full")
    
    log_info("Running: {cmd}")
    result <- system(cmd, intern = TRUE)
    log_info("Fetch completed")
    
    # Check if files were created
    raw_dir <- file.path(BASE_DIR, "data/raw")
    if (dir.exists(raw_dir)) {
      parquet_files <- list.files(raw_dir, pattern = "\\.parquet$", full.names = FALSE)
      log_info("Found {length(parquet_files)} parquet files in data/raw/")
    }
  } else {
    log_warn("No fetch script found. Skipping...")
  }
} else {
  log_info("\n[STEP 1] Skipping data fetch (--skip-fetch)")
}

# ============================================================
# STEP 2: Build Regional Repository (R)
# ============================================================

if (!skip_build) {
  log_info("\n[STEP 2] Building regional IM repository...")
  
  builder_script <- file.path(SCRIPTS_DIR, "regional_im_repository_builder.R")
  
  if (file.exists(builder_script)) {
    log_info("Sourcing: {builder_script}")
    source(builder_script)
    log_info("Repository builder completed")
  } else {
    log_error("Builder script not found: {builder_script}")
    quit(status = 1)
  }
} else {
  log_info("\n[STEP 2] Skipping repository build (--skip-build)")
}

# ============================================================
# STEP 3: Clean Geonames (R)
# ============================================================

if (!skip_clean) {
  log_info("\n[STEP 3] Cleaning geonames...")
  
  clean_script <- file.path(SCRIPTS_DIR, "clean_geonames.R")
  
  if (file.exists(clean_script)) {
    log_info("Sourcing: {clean_script}")
    source(clean_script)
    log_info("Geonames cleaning completed")
  } else {
    log_warn("Clean script not found: {clean_script}")
  }
} else {
  log_info("\n[STEP 3] Skipping geonames cleaning (--skip-clean)")
}

# ============================================================
# STEP 4: Upload to SharePoint
# ============================================================

if (!skip_upload) {
  upload_result <- upload_to_sharepoint("--all")
  if (!upload_result) {
    log_warn("SharePoint upload had issues, but workflow continues")
  }
} else {
  log_info("\n[STEP 4] Skipping SharePoint upload (--skip-upload)")
}

# ============================================================
# STEP 5: Optional Reports (Non-blocking)
# ============================================================

if (!skip_reports) {
  log_info("\n[STEP 5] Generating optional reports...")
  
  # Report 1: AFRO Advocacy Intelligence Report
  report1_script <- file.path(SCRIPTS_DIR, "AFRO_Advocacy_Intelligence_Report.R")
  
  if (file.exists(report1_script)) {
    log_info("Sourcing: {report1_script}")
    tryCatch({
      source(report1_script)
      log_info("  ✓ AFRO Advocacy Intelligence Report completed")
    }, error = function(e) {
      log_warn("  ✗ AFRO Advocacy Intelligence Report failed: {e$message}")
    })
  } else {
    log_info("  - AFRO_Advocacy_Intelligence_Report.R not found, skipping")
  }
  
  # Report 2: AFRO Region IM Deck Generation
  report2_script <- file.path(SCRIPTS_DIR, "afro_region_im_deck_generation.R")
  
  if (file.exists(report2_script)) {
    log_info("Sourcing: {report2_script}")
    tryCatch({
      source(report2_script)
      log_info("  ✓ AFRO Region IM Deck Generation completed")
    }, error = function(e) {
      log_warn("  ✗ AFRO Region IM Deck Generation failed: {e$message}")
    })
  } else {
    log_info("  - afro_region_im_deck_generation.R not found, skipping")
  }
  
  log_info("Optional reports processing completed")
} else {
  log_info("\n[STEP 5] Skipping optional reports (--skip-reports)")
}

# ============================================================
# SUMMARY
# ============================================================

end_time <- Sys.time()
execution_time <- difftime(end_time, start_time, units = "mins")

log_info("\n============================================================")
log_info("WORKFLOW COMPLETED")
log_info("End time: {end_time}")
log_info("Execution time: {round(execution_time, 2)} minutes")
log_info("Log file: {log_file}")

# List output files
final_dir <- file.path(BASE_DIR, "data/final")
if (dir.exists(final_dir)) {
  output_files <- list.files(final_dir, pattern = "\\.(csv|rds|parquet|xlsx|txt)$", full.names = FALSE)
  log_info("\nOutput files ({length(output_files)}):")
  for (f in output_files) {
    fp <- file.path(final_dir, f)
    size_mb <- round(file.size(fp) / 1024 / 1024, 2)
    log_info("  - {f} ({size_mb} MB)")
  }
}

log_info("============================================================")

# Print to console as well
cat("\n")
cat("============================================================\n")
cat("IM WORKFLOW COMPLETED\n")
cat("============================================================\n")
cat(sprintf("Execution time: %.2f minutes\n", execution_time))
cat(sprintf("Log file: %s\n", log_file))
cat(sprintf("Output directory: %s\n", final_dir))
cat("============================================================\n")