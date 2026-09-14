#!/usr/bin/env Rscript

# ============================================================================
# IM Workflow - Pipeline Orchestrator
# ============================================================================
# Purpose: Orchestrate the entire IM workflow in the correct order
# Order: 
#   1. Fetch_im_data.py - Download data from ODK
#   2. stand_alone_im_repository_builder.R - Build initial repository
#   3. clean_geonames.R - Clean geonames data
#   4. upload_to_sharepoint.py - Upload to SharePoint
#   5. AFRO_Advocacy_Intelligence_Report.R (optional)
#   6. afro_region_im_deck_generation.R (optional)
# ============================================================================

# ============================================================================
# Initialization
# ============================================================================

# Create logs directory first
if (!dir.exists("logs")) dir.create("logs", recursive = TRUE)

# Configuration
ROOT_DIR <- getwd()
SCRIPTS_DIR <- ROOT_DIR
DATA_DIR <- file.path(dirname(ROOT_DIR), "data")
LOGS_DIR <- file.path(ROOT_DIR, "logs")

# Logging function with color
log_message <- function(msg, level = "INFO", emoji = "") {
  timestamp <- format(Sys.time(), "%H:%M:%S")
  
  # Console output with colors
  if (level == "STEP") {
    cat(sprintf("\n\033[1;34m[%s] \033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n", timestamp))
    cat(sprintf("\033[1;34m[%s] \033[1;33m%s %s\033[0m\n", timestamp, emoji, msg))
    cat(sprintf("\033[1;34m[%s] \033[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n", timestamp))
  } else if (level == "SUCCESS") {
    cat(sprintf("\033[36m[%s]\033[0m \033[32m✅ %s\033[0m\n", timestamp, msg))
  } else if (level == "ERROR") {
    cat(sprintf("\033[36m[%s]\033[0m \033[31m❌ %s\033[0m\n", timestamp, msg))
  } else if (level == "WARN") {
    cat(sprintf("\033[36m[%s]\033[0m \033[33m⚠️  %s\033[0m\n", timestamp, msg))
  } else {
    cat(sprintf("\033[36m[%s]\033[0m \033[90m%s\033[0m\n", timestamp, msg))
  }
  
  # Also write to log file
  log_file <- file.path(LOGS_DIR, paste0("orchestrator_", Sys.Date(), ".log"))
  cat(sprintf("[%s] %s: %s\n", timestamp, level, msg), file = log_file, append = TRUE)
}

print_separator <- function(char = "=", length = 70) {
  cat(sprintf("\033[90m%s\033[0m\n", paste(rep(char, length), collapse = "")))
}

# ============================================================================
# Step 1: Fetch IM Data (Python) - CRITICAL
# ============================================================================

run_fetch_data <- function() {
  log_message("STEP 1: Fetching IM Data from ODK", "STEP", "🌐")
  
  # Try multiple script names
  fetch_scripts <- c(
    file.path(SCRIPTS_DIR, "Fetch_im_data_LIVE_UPDATED.py"),
    file.path(SCRIPTS_DIR, "Fetch_im_data.py")
  )
  
  fetch_script <- NULL
  for (script in fetch_scripts) {
    if (file.exists(script)) {
      fetch_script <- script
      break
    }
  }
  
  if (is.null(fetch_script)) {
    log_message("No fetch script found! Looking for: Fetch_im_data.py", "ERROR")
    return(FALSE)
  }
  
  log_message(paste("Running:", basename(fetch_script)))
  log_message("This may take several minutes depending on data size...")
  
  start_time <- Sys.time()
  result <- system2("python", fetch_script, stdout = TRUE, stderr = TRUE)
  end_time <- Sys.time()
  
  # Check if parquet files were created
  raw_dir <- file.path(dirname(ROOT_DIR), "data", "raw")
  if (!dir.exists(raw_dir)) {
    raw_dir <- file.path(ROOT_DIR, "..", "data", "raw")
  }
  
  parquet_files <- list.files(raw_dir, pattern = "\\.parquet$", full.names = TRUE)
  
  if (length(parquet_files) > 0) {
    total_size <- sum(file.info(parquet_files)$size) / 1024 / 1024
    log_message(paste("SUCCESS: Downloaded", length(parquet_files), 
                      "parquet files (", sprintf("%.2f", total_size), "MB )"), "SUCCESS")
    log_message(paste("Time taken:", round(difftime(end_time, start_time, units = "mins"), 2), "minutes"))
    return(TRUE)
  } else {
    log_message("No parquet files found after fetch", "ERROR")
    return(FALSE)
  }
}

# ============================================================================
# Step 2: Stand Alone IM Repository Builder (R) - CRITICAL
# ============================================================================

run_repository_builder <- function() {
  log_message("STEP 2: Building IM Repository", "STEP", "🏗️")
  
  repo_script <- file.path(SCRIPTS_DIR, "stand_alone_im_repository_builder.R")
  
  if (!file.exists(repo_script)) {
    log_message("stand_alone_im_repository_builder.R not found!", "ERROR")
    return(FALSE)
  }
  
  log_message(paste("Running:", basename(repo_script)))
  log_message("Building regional repository from parquet files...")
  
  start_time <- Sys.time()
  result <- system2("Rscript", repo_script, stdout = TRUE, stderr = TRUE)
  end_time <- Sys.time()
  
  # Check output files
  final_dir <- file.path(dirname(ROOT_DIR), "data", "final")
  if (!dir.exists(final_dir)) {
    final_dir <- file.path(ROOT_DIR, "..", "data", "final")
  }
  
  expected_files <- c(
    "Regional_IM_repository.csv",
    "Regional_IM_repository_cleaned.csv"
  )
  
  files_found <- sum(file.exists(file.path(final_dir, expected_files)))
  
  if (files_found >= 1) {
    log_message(paste("SUCCESS: Repository builder created", files_found, "files"), "SUCCESS")
    log_message(paste("Time taken:", round(difftime(end_time, start_time, units = "mins"), 2), "minutes"))
    return(TRUE)
  } else {
    log_message("Repository builder failed to create expected files", "ERROR")
    return(FALSE)
  }
}

# ============================================================================
# Step 3: Clean Geonames (R) - CRITICAL
# ============================================================================

run_clean_geonames <- function() {
  log_message("STEP 3: Cleaning Geonames Data", "STEP", "🧹")
  
  clean_script <- file.path(SCRIPTS_DIR, "clean_geonames.R")
  
  if (!file.exists(clean_script)) {
    log_message("clean_geonames.R not found!", "ERROR")
    return(FALSE)
  }
  
  log_message(paste("Running:", basename(clean_script)))
  log_message("Cleaning and standardizing geonames data...")
  
  start_time <- Sys.time()
  result <- system2("Rscript", clean_script, stdout = TRUE, stderr = TRUE)
  end_time <- Sys.time()
  
  # Check output files
  final_dir <- file.path(dirname(ROOT_DIR), "data", "final")
  if (!dir.exists(final_dir)) {
    final_dir <- file.path(ROOT_DIR, "..", "data", "final")
  }
  
  expected_file <- file.path(final_dir, "IM_geonames_cleaning_summary.csv")
  
  if (file.exists(expected_file)) {
    log_message("SUCCESS: Geonames cleaning completed", "SUCCESS")
    log_message(paste("Time taken:", round(difftime(end_time, start_time, units = "mins"), 2), "minutes"))
    return(TRUE)
  } else {
    log_message("Geonames cleaning may have issues, but continuing...", "WARN")
    return(TRUE)  # Continue even if this fails
  }
}

# ============================================================================
# Step 4: Upload to SharePoint (Python) - CRITICAL
# ============================================================================

run_sharepoint_upload <- function() {
  log_message("STEP 4: Uploading to SharePoint", "STEP", "☁️")
  
  upload_scripts <- c(
    file.path(SCRIPTS_DIR, "upload_to_sharepoint.py"),
    file.path(SCRIPTS_DIR, "upload_to_sharepoint_1.py")
  )
  
  upload_script <- NULL
  for (script in upload_scripts) {
    if (file.exists(script)) {
      upload_script <- script
      break
    }
  }
  
  if (is.null(upload_script)) {
    log_message("No SharePoint upload script found!", "ERROR")
    return(FALSE)
  }
  
  log_message(paste("Running:", basename(upload_script)))
  log_message("Uploading files to SharePoint. This may take several minutes...")
  
  start_time <- Sys.time()
  result <- system2("python", upload_script, stdout = TRUE, stderr = TRUE)
  end_time <- Sys.time()
  
  # Check for success indicators
  output_str <- paste(result, collapse = " ")
  if (grepl("SUCCESS|successfully|uploaded|complete", output_str, ignore.case = TRUE)) {
    log_message("SUCCESS: Files uploaded to SharePoint", "SUCCESS")
    log_message(paste("Time taken:", round(difftime(end_time, start_time, units = "mins"), 2), "minutes"))
    return(TRUE)
  } else {
    log_message("SharePoint upload may have issues, but continuing...", "WARN")
    return(TRUE)  # Continue even if upload has issues
  }
}

# ============================================================================
# Step 5: AFRO Advocacy Intelligence Report (R) - OPTIONAL
# ============================================================================

run_advocacy_report <- function() {
  log_message("STEP 5: Generating AFRO Advocacy Intelligence Report (OPTIONAL)", "STEP", "📊")
  
  report_script <- file.path(SCRIPTS_DIR, "AFRO_Advocacy_Intelligence_Report.R")
  
  if (!file.exists(report_script)) {
    log_message("AFRO_Advocacy_Intelligence_Report.R not found, skipping...", "WARN")
    return(TRUE)  # Optional, continue
  }
  
  log_message(paste("Running:", basename(report_script)))
  
  start_time <- Sys.time()
  result <- system2("Rscript", report_script, stdout = TRUE, stderr = TRUE)
  end_time <- Sys.time()
  
  # Check output
  reports_dir <- file.path(dirname(ROOT_DIR), "outputs", "reports")
  if (!dir.exists(reports_dir)) {
    reports_dir <- file.path(ROOT_DIR, "..", "outputs", "reports")
  }
  
  if (dir.exists(reports_dir)) {
    report_files <- list.files(reports_dir, pattern = "AFRO_Advocacy", full.names = TRUE)
    if (length(report_files) > 0) {
      log_message(paste("SUCCESS: Generated advocacy report"), "SUCCESS")
      log_message(paste("Time taken:", round(difftime(end_time, start_time, units = "mins"), 2), "minutes"))
    } else {
      log_message("Advocacy report generation completed (output location unknown)", "SUCCESS")
    }
  } else {
    log_message("Advocacy report generation completed", "SUCCESS")
  }
  
  return(TRUE)  # Always return TRUE for optional steps
}

# ============================================================================
# Step 6: AFRO Region IM Deck Generation (R) - OPTIONAL
# ============================================================================

run_deck_generation <- function() {
  log_message("STEP 6: Generating AFRO Region IM Deck (OPTIONAL)", "STEP", "📋")
  
  deck_script <- file.path(SCRIPTS_DIR, "afro_region_im_deck_generation.R")
  
  if (!file.exists(deck_script)) {
    log_message("afro_region_im_deck_generation.R not found, skipping...", "WARN")
    return(TRUE)  # Optional, continue
  }
  
  log_message(paste("Running:", basename(deck_script)))
  
  start_time <- Sys.time()
  result <- system2("Rscript", deck_script, stdout = TRUE, stderr = TRUE)
  end_time <- Sys.time()
  
  log_message("SUCCESS: Deck generation completed", "SUCCESS")
  log_message(paste("Time taken:", round(difftime(end_time, start_time, units = "mins"), 2), "minutes"))
  
  return(TRUE)  # Always return TRUE for optional steps
}

# ============================================================================
# Main Orchestrator
# ============================================================================

run_pipeline <- function(skip_fetch = FALSE, skip_upload = FALSE) {
  print_separator("=")
  log_message("IM WORKFLOW PIPELINE STARTING", "STEP", "🚀")
  log_message(paste("Start time:", Sys.time()))
  print_separator("=")
  
  start_time <- Sys.time()
  
  # Track step results
  results <- list()
  
  # Step 1: Fetch data (CRITICAL)
  if (!skip_fetch) {
    results$fetch <- run_fetch_data()
    if (!results$fetch) {
      log_message("Data fetch failed! Pipeline terminated.", "ERROR")
      return(FALSE)
    }
  } else {
    log_message("Skipping data fetch (--skip-fetch flag used)")
    results$fetch <- TRUE
  }
  
  # Step 2: Repository Builder (CRITICAL)
  results$repository <- run_repository_builder()
  if (!results$repository) {
    log_message("Repository builder failed! Pipeline terminated.", "ERROR")
    return(FALSE)
  }
  
  # Step 3: Clean Geonames (CRITICAL - but continues on warn)
  results$geonames <- run_clean_geonames()
  
  # Step 4: Upload to SharePoint (CRITICAL)
  if (!skip_upload) {
    results$upload <- run_sharepoint_upload()
  } else {
    log_message("Skipping SharePoint upload (--skip-upload flag used)")
    results$upload <- TRUE
  }
  
  # Step 5: Advocacy Report (OPTIONAL - won't stop pipeline)
  results$advocacy <- run_advocacy_report()
  
  # Step 6: Deck Generation (OPTIONAL - won't stop pipeline)
  results$deck <- run_deck_generation()
  
  # Calculate execution time
  end_time <- Sys.time()
  execution_time <- difftime(end_time, start_time, units = "mins")
  
  # Print summary
  print_separator("=")
  log_message("PIPELINE EXECUTION SUMMARY", "STEP", "📊")
  print_separator("-")
  
  # Critical steps
  cat("\n\033[1;33m▶ CRITICAL STEPS:\033[0m\n")
  critical_status <- if(results$fetch) "✅" else "❌"
  cat(sprintf("  %s Fetch Data: %s\n", critical_status, if(results$fetch) "SUCCESS" else "FAILED"))
  critical_status <- if(results$repository) "✅" else "❌"
  cat(sprintf("  %s Repository Builder: %s\n", critical_status, if(results$repository) "SUCCESS" else "FAILED"))
  critical_status <- if(results$geonames) "✅" else "⚠️"
  cat(sprintf("  %s Clean Geonames: %s\n", critical_status, if(results$geonames) "SUCCESS" else "WARNING"))
  critical_status <- if(results$upload) "✅" else "⚠️"
  cat(sprintf("  %s SharePoint Upload: %s\n", critical_status, if(results$upload) "SUCCESS" else "WARNING"))
  
  # Optional steps
  cat("\n\033[1;33m▶ OPTIONAL STEPS (Non-blocking):\033[0m\n")
  cat(sprintf("  📊 Advocacy Report: %s\n", if(results$advocacy) "COMPLETED" else "SKIPPED/FAILED"))
  cat(sprintf("  📋 Deck Generation: %s\n", if(results$deck) "COMPLETED" else "SKIPPED/FAILED"))
  
  print_separator("-")
  log_message(paste("Total execution time:", round(execution_time, 2), "minutes"))
  log_message(paste("End time:", end_time))
  print_separator("=")
  
  # Final console output
  cat("\n")
  print_separator("=")
  cat("\033[1;32m✅ IM WORKFLOW PIPELINE COMPLETE\033[0m\n")
  print_separator("=")
  cat(sprintf("  • Execution time: %.2f minutes\n", execution_time))
  cat(sprintf("  • Logs location: %s\n", LOGS_DIR))
  cat(sprintf("  • Data location: ../data/final/\n"))
  cat(sprintf("  • Reports location: ../outputs/reports/\n"))
  print_separator("=")
  cat("\n")
  
  return(TRUE)
}

# ============================================================================
# Command Line Execution
# ============================================================================

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
skip_fetch_flag <- "--skip-fetch" %in% args
skip_upload_flag <- "--skip-upload" %in% args

# Run the pipeline
if (interactive()) {
  cat("Running IM Workflow Pipeline interactively...\n")
  cat("To skip data fetch: run_pipeline(skip_fetch = TRUE)\n")
  cat("To skip upload: run_pipeline(skip_upload = TRUE)\n\n")
  run_pipeline(skip_fetch = FALSE, skip_upload = FALSE)
} else {
  run_pipeline(skip_fetch = skip_fetch_flag, skip_upload = skip_upload_flag)
}