#!/usr/bin/env Rscript
# ============================================================
# UNIFIED IM WORKFLOW LAUNCHER
# Orchestrates: Fetch -> Build Repository -> Clean Geonames -> Upload to SharePoint -> Reports (Optional)
# ============================================================

suppressPackageStartupMessages(suppressWarnings({
  library(logger)
  library(fs)
}))

# Configuration
# Set once via `setx IM_WORKFLOW_HOME "D:/new/path"` (Windows) if this
# project ever moves off this laptop/drive -- every script in the pipeline
# reads the same variable, so nothing else needs editing.
BASE_DIR <- Sys.getenv("IM_WORKFLOW_HOME", unset = "C:/Users/TOURE/Documents/im_workflow")
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
skip_lookup_refresh <- "--skip-lookup-refresh" %in% args
force_fetch <- "--force-fetch" %in% args
upload_only <- "--upload-only" %in% args
force_upload <- "--force-upload" %in% args

log_info("Options:")
log_info("  Skip lookup refresh: {skip_lookup_refresh}")
log_info("  Skip fetch: {skip_fetch}")
log_info("  Skip build: {skip_build}")
log_info("  Skip clean: {skip_clean}")
log_info("  Skip upload: {skip_upload}")
log_info("  Skip reports: {skip_reports}")
log_info("  Force fetch: {force_fetch}")
log_info("  Upload only: {upload_only}")
log_info("  Force upload (even if clean failed): {force_upload}")

# Record start time
start_time <- Sys.time()

# ============================================================
# RUN HISTORY (survives past this run's own console/log file)
# ============================================================
# Every full pipeline run appends ONE row to logs/run_history.csv, whether
# it finishes cleanly or stops early on a hard failure (Step 2) -- every
# quit() point below writes its own row before exiting, rather than relying
# on a single write at the very end that a hard stop would skip.
# logs/workflow_<date>.log already records what happened in prose for a
# single run; this file is the queryable, append-only record across every
# run, so "did last night's run finish?" or "how many runs failed this
# month?" don't require opening old text logs one at a time.
#
# run_id is shared with Fetch_im_data.py via the IM_RUN_ID environment
# variable (set below) so its own logs/fetch_run_history.csv and
# logs/fetch_form_history.csv rows for this run can be matched back to the
# row here.
run_id <- format(start_time, "%Y%m%d_%H%M%S")
Sys.setenv(IM_RUN_ID = run_id)

RUN_HISTORY_FILE <- file.path(LOGS_DIR, "run_history.csv")

step_status <- list(
  lookup_refresh = if (skip_lookup_refresh) "skipped" else "pending",
  fetch          = if (skip_fetch) "skipped" else "pending",
  build          = if (skip_build) "skipped" else "pending",
  clean          = if (skip_clean) "skipped" else "pending",
  upload         = if (skip_upload) "skipped" else "pending",
  reports        = if (skip_reports) "skipped" else "pending"
)

write_run_manifest <- function(overall_status, notes = "") {
  end_time_local <- Sys.time()
  duration_min <- round(as.numeric(difftime(end_time_local, start_time, units = "mins")), 2)

  row <- data.frame(
    run_id = run_id,
    start_time = format(start_time, "%Y-%m-%d %H:%M:%S"),
    end_time = format(end_time_local, "%Y-%m-%d %H:%M:%S"),
    duration_min = duration_min,
    lookup_refresh_status = step_status$lookup_refresh,
    fetch_status = step_status$fetch,
    build_status = step_status$build,
    clean_status = step_status$clean,
    upload_status = step_status$upload,
    reports_status = step_status$reports,
    overall_status = overall_status,
    force_fetch = force_fetch,
    upload_only = upload_only,
    force_upload = force_upload,
    notes = notes,
    stringsAsFactors = FALSE
  )

  tryCatch({
    write_header <- !file.exists(RUN_HISTORY_FILE)
    write.table(row, RUN_HISTORY_FILE, sep = ",", append = !write_header,
                row.names = FALSE, col.names = write_header, qmethod = "double")
  }, error = function(e) {
    # A logging problem must never take down an otherwise-working pipeline.
    log_warn("Could not write to run_history.csv: {e$message}")
  })
}

# ============================================================
# FAILURE ALERTING (for unattended overnight runs, Mon-Fri)
# ============================================================
# See scripts/send_failure_alert.py for the actual email-sending logic and
# how to enable it (config/secrets.env). Called only on a genuine hard
# failure (Repository Builder, or --upload-only failing) -- NOT on
# success_with_warnings, so a nightly run with e.g. a soft-failed fetch
# doesn't page anyone; that's what the dashboard / run_history.csv are for.
#
# ALERT_MARKER_FILE is deleted at the start of every run and only re-created
# on a successful send, so run_workflow_nightly.bat (the Task Scheduler
# entry point) can tell whether THIS script already emailed about a failure
# before deciding whether to send its own generic fallback alert -- that
# fallback exists for the case this script crashes before reaching any of
# the alert calls below at all.
ALERT_MARKER_FILE <- file.path(LOGS_DIR, "last_alert_sent.flag")
if (file.exists(ALERT_MARKER_FILE)) {
  tryCatch(file.remove(ALERT_MARKER_FILE), error = function(e) NULL)
}

send_failure_alert <- function(subject, body) {
  tryCatch({
    alert_script <- file.path(SCRIPTS_DIR, "send_failure_alert.py")
    if (!file.exists(alert_script)) {
      log_warn("Failure alert script not found: {alert_script}")
      return(invisible(FALSE))
    }

    # Body goes through a temp file, not a command-line argument -- a
    # multi-line string quoted directly on the Windows command line is
    # unreliable (embedded quotes/newlines break cmd.exe's parsing).
    body_file <- file.path(LOGS_DIR, paste0("alert_body_", run_id, ".txt"))
    writeLines(body, body_file)
    on.exit(unlink(body_file), add = TRUE)

    safe_subject <- gsub("\"", "'", subject)
    cmd <- sprintf(
      "python \"%s\" --base-dir \"%s\" --subject \"%s\" --body-file \"%s\"",
      alert_script, BASE_DIR, safe_subject, body_file
    )
    exit_status <- system(cmd)

    if (!is.na(exit_status) && exit_status == 0L) {
      file.create(ALERT_MARKER_FILE)
      log_info("Failure alert emailed.")
    } else {
      log_warn("Failure alert script did not confirm sending (exit status {exit_status}) - check ALERT_EMAIL_* in config/secrets.env.")
    }
  }, error = function(e) {
    # Alerting must never become a second thing that can break a run.
    log_warn("Could not send failure alert: {e$message}")
  })
  invisible(NULL)
}

# ============================================================
# FUNCTION: Run a shell command with LIVE console output
# ============================================================
# Plain system(cmd, intern = TRUE) captures the child process's output
# silently and only returns it once the child exits -- so a long-running
# step (fetching hundreds of thousands of records, building the repository,
# etc.) looks completely frozen in the console for its entire duration,
# even though it's actively working. system(cmd) (intern = FALSE) instead
# lets the child inherit this console's stdout/stderr directly, so its
# output streams live as it's produced. It still blocks until the child
# exits; its return value is the child's exit status (0 = success).

run_live <- function(cmd) {
  exit_status <- system(cmd)
  if (is.na(exit_status)) exit_status <- 1L
  exit_status
}

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
# FUNCTION: Run R script in separate process (prevents quit() from stopping workflow)
# ============================================================

run_r_script <- function(script_path, step_name) {
  log_info("\n[{step_name}] Running: {basename(script_path)}")

  if (!file.exists(script_path)) {
    log_warn("Script not found: {script_path}")
    return(FALSE)
  }

  # Run in a separate R process so quit() doesn't affect the main workflow.
  # Streamed live (run_live()) so long steps (e.g. Repository Builder on
  # 1M+ rows) show real-time progress instead of going silent until done --
  # full detail is still in the script's own log file (see the FAILED
  # message below), so we don't need to also replay it line-by-line here.
  cmd <- sprintf("Rscript \"%s\"", script_path)
  log_info("Executing: {cmd}")
  cat(sprintf("\n[%s] live output below:\n%s\n", step_name, strrep("-", 60)))

  exit_status <- run_live(cmd)

  cat(sprintf("%s\n", strrep("-", 60)))

  if (exit_status != 0L) {
    log_warn("  ✗ {step_name} FAILED (exit code: {exit_status}) - check its own log file for the real error")
    return(FALSE)
  }

  log_info("  ✓ {step_name} completed")
  return(TRUE)
}

# ============================================================
# FUNCTION: Source R script safely (for scripts without quit())
# ============================================================

source_safely <- function(script_path, step_name) {
  log_info("\n[{step_name}] Running: {basename(script_path)}")
  
  if (!file.exists(script_path)) {
    log_warn("Script not found: {script_path}")
    return(FALSE)
  }
  
  tryCatch({
    source(script_path)
    log_info("  ✓ {step_name} completed successfully")
    return(TRUE)
  }, error = function(e) {
    log_warn("  ✗ {step_name} failed: {e$message}")
    return(FALSE)
  })
}

# ============================================================
# FUNCTION: Run Optional Reports (Non-blocking)
# ============================================================

run_optional_reports <- function() {
  log_info("\n[STEP 5] Generating optional reports...")

  # Report 0: Phase 1 IM Intelligence Analysis Engine
  # Creates the root-cause, SM effectiveness, operational failure and district
  # risk tables (outputs/phase1_intelligence). Must run BEFORE the Advocacy
  # Intelligence Report, which reads these tables as its input.
  report0_script <- file.path(SCRIPTS_DIR, "afro_im_intilligence_analysis_engine.R")
  engine_ok <- source_safely(report0_script, "Phase 1 IM Intelligence Analysis Engine")

  if (!engine_ok) {
    log_warn("Phase 1 Intelligence Engine failed - downstream reports may use stale/missing input tables")
  }

  # Report 1: AFRO Advocacy Intelligence Report
  # Builds the regional tables, premium PNG plots, Excel workbook and Word
  # brief (outputs/reports/IM_Intelligence_Report) from the Phase 1 tables above.
  report1_script <- file.path(SCRIPTS_DIR, "AFRO_Advocacy_Intelligence_Report.R")
  report1_ok <- source_safely(report1_script, "AFRO Advocacy Intelligence Report")

  # Report 2: AFRO Region IM Deck Generation
  # Builds the PowerPoint deck from the plots/Excel produced above.
  report2_script <- file.path(SCRIPTS_DIR, "afro_region_im_deck_generation.R")
  report2_ok <- source_safely(report2_script, "AFRO Region IM Deck Generation")

  log_info("Optional reports processing completed")

  list(engine_ok = engine_ok, report1_ok = report1_ok, report2_ok = report2_ok)
}

# ============================================================
# UPLOAD ONLY MODE
# ============================================================

if (upload_only) {
  log_info("\n============================================================")
  log_info("UPLOAD ONLY MODE")
  log_info("============================================================")

  upload_result <- upload_to_sharepoint("--all")
  step_status$upload <- if (upload_result) "ok" else "failed"

  if (upload_result) {
    log_info("Upload completed successfully")
    cat("\n============================================================\n")
    cat("UPLOAD COMPLETED SUCCESSFULLY\n")
    cat("============================================================\n")
  } else {
    log_error("Upload failed")
    write_run_manifest("failed", "upload-only mode - upload failed")
    send_failure_alert(
      subject = sprintf("[IM Workflow] FAILED - upload-only run (run %s)", run_id),
      body = sprintf(
        "The IM workflow's --upload-only run (%s) failed to upload to SharePoint.\n\nCheck the log for the real error: %s\n\nNo other pipeline steps ran in this mode.",
        run_id, log_file
      )
    )
    quit(status = 1)
  }

  write_run_manifest("success", "upload-only mode")
  quit(status = 0)
}

# ============================================================
# STEP 0: Refresh preparedness lookup (campaign calendar)
# ============================================================
# Downloads the current "Status of campaign preparedness" table
# (Finished + In Progress rounds only) from the WHO AFRO Power BI
# dashboard and replaces data/lookup/lookup.xlsx with it, BEFORE the
# fetch/build steps run -- otherwise the whole pipeline (including the
# calendar-first Ethiopia/6839 attribution logic in
# regional_im_repository_builder.R) works off whatever lookup.xlsx was
# last downloaded by hand, which can silently go stale as new rounds
# are added to the calendar.
#
# Soft-fail by design (like Clean Geonames below): the refresh script
# validates its own download and refuses to overwrite lookup.xlsx if
# anything looks wrong (wrong filter applied, truncated export, etc.),
# so a failure here just means the run proceeds on the PREVIOUS
# lookup.xlsx rather than corrupting the campaign calendar. Not treated
# as a hard stop the way a failed Repository Builder (Step 2) is,
# since a slightly stale calendar degrades gracefully (the existing
# 6839 audit trail / stale_fallback_flag will surface anything that
# actually depends on a missing round), while blocking the whole
# pipeline on a dashboard hiccup would not.

if (!skip_lookup_refresh) {
  log_info("\n[STEP 0] Refreshing preparedness lookup (campaign calendar)...")

  lookup_refresh_script <- file.path(SCRIPTS_DIR, "refresh_preparedness_lookup.py")

  if (file.exists(lookup_refresh_script)) {
    cmd <- sprintf("python \"%s\" --base-dir \"%s\"", lookup_refresh_script, BASE_DIR)
    log_info("Running: {cmd}")
    cat(sprintf("\n[STEP 0] Refreshing preparedness lookup -- live output below:\n%s\n", strrep("-", 60)))

    lookup_refresh_exit_status <- run_live(cmd)

    cat(sprintf("%s\n", strrep("-", 60)))

    if (lookup_refresh_exit_status != 0L) {
      log_warn("Lookup refresh failed or was rejected by its own validation - continuing with the PREVIOUS lookup.xlsx")
      cat("\n[WARN] [STEP 0] Preparedness lookup refresh FAILED - the pipeline will use the PREVIOUS lookup.xlsx.\n")
      cat("    Re-run with: python scripts\\refresh_preparedness_lookup.py --debug  to see what broke.\n")
      step_status$lookup_refresh <- "failed_soft"
    } else {
      log_info("  ✓ Preparedness lookup refreshed")
      step_status$lookup_refresh <- "ok"
    }
  } else {
    log_warn("Lookup refresh script not found: {lookup_refresh_script} - continuing with the existing lookup.xlsx")
    step_status$lookup_refresh <- "failed_soft"
  }
} else {
  log_info("\n[STEP 0] Skipping preparedness lookup refresh (--skip-lookup-refresh)")
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
    cat(sprintf("\n[STEP 1] Fetching IM data -- live output below:\n%s\n", strrep("-", 60)))

    # Streamed live (run_live()) instead of captured silently, so per-form
    # fetch progress shows up in this console in real time instead of
    # going silent for the whole run.
    fetch_exit_status <- run_live(cmd)

    cat(sprintf("%s\n", strrep("-", 60)))

    if (fetch_exit_status != 0L) {
      log_warn("Fetch step exited with a non-zero status ({fetch_exit_status}) - check logs/fetch_log.txt for details")
      step_status$fetch <- "failed_soft"
    } else {
      log_info("Fetch completed")
      step_status$fetch <- "ok"
    }

    # Check if files were created
    raw_dir <- file.path(BASE_DIR, "data/raw")
    if (dir.exists(raw_dir)) {
      parquet_files <- list.files(raw_dir, pattern = "\\.parquet$", full.names = FALSE)
      log_info("Found {length(parquet_files)} parquet files in data/raw/")
    }
  } else {
    log_warn("No fetch script found. Skipping...")
    step_status$fetch <- "failed_soft"
  }
} else {
  log_info("\n[STEP 1] Skipping data fetch (--skip-fetch)")
}

# ============================================================
# STEP 2: Build Regional Repository (R) - Using separate process
# ============================================================

if (!skip_build) {
  log_info("\n[STEP 2] Building regional IM repository...")
  
  builder_script <- file.path(SCRIPTS_DIR, "regional_im_repository_builder.R")
  
  if (file.exists(builder_script)) {
    # Run in separate process to prevent quit() from stopping the workflow
    success <- run_r_script(builder_script, "Repository Builder")
    if (!success) {
      log_error("Repository builder failed!")
      cat("\n[ERROR] [STEP 2] Repository Builder FAILED - see scripts/logs for the real error. Workflow stopped.\n")
      step_status$build <- "failed"
      write_run_manifest("failed", "Repository Builder failed - workflow stopped at Step 2")
      send_failure_alert(
        subject = sprintf("[IM Workflow] FAILED - Repository Builder (run %s)", run_id),
        body = sprintf(
          "The IM workflow run %s failed at Step 2 (Repository Builder).\n\nThe pipeline stopped here - Clean Geonames, Upload, and Reports did NOT run this time.\n\nExisting data files were left untouched (see the validate-before-publish check in regional_im_repository_builder.R).\n\nCheck the log for the real error: %s",
          run_id, log_file
        )
      )
      quit(status = 1)
    }
    step_status$build <- "ok"
  } else {
    log_error("Builder script not found: {builder_script}")
    cat("\n[ERROR] [STEP 2] Builder script not found: ", builder_script, " - Workflow stopped.\n", sep = "")
    step_status$build <- "failed"
    write_run_manifest("failed", "Builder script not found - workflow stopped at Step 2")
    send_failure_alert(
      subject = sprintf("[IM Workflow] FAILED - Repository Builder script missing (run %s)", run_id),
      body = sprintf(
        "The IM workflow run %s could not find regional_im_repository_builder.R at:\n%s\n\nThe pipeline stopped at Step 2 - nothing after it ran.",
        run_id, builder_script
      )
    )
    quit(status = 1)
  }
} else {
  log_info("\n[STEP 2] Skipping repository build (--skip-build)")
}

# ============================================================
# STEP 3: Clean Geonames (R) - Using source safely
# ============================================================

# Tracks whether data/final holds a file that was actually (re)written by
# THIS run. Used by Step 4 to avoid silently uploading a stale file to
# SharePoint when Clean Geonames failed. Defaults to TRUE when the step is
# skipped outright (--skip-clean), since that's an intentional choice to
# upload whatever is already on disk.
clean_ok <- TRUE

if (!skip_clean) {
  log_info("\n[STEP 3] Cleaning geonames...")

  clean_script <- file.path(SCRIPTS_DIR, "clean_geonames.R")
  # Use run_r_script (separate process) instead of source_safely:
  # clean_geonames.R calls quit() at the end, which would kill this
  # parent process if sourced directly, preventing Steps 4 & 5 from running.
  success <- run_r_script(clean_script, "Clean Geonames")
  clean_ok <- success
  step_status$clean <- if (success) "ok" else "failed_soft"
  if (!success) {
    log_warn("Geonames cleaning had issues, but workflow continues")
    cat("\n[WARN] [STEP 3] Clean Geonames FAILED - downstream steps will use the PREVIOUS cleaned file, if any.\n")
    cat("    Check logs/im_geonames_clean.log for the real error (common cause: the CSV is open in Excel,\n")
    cat("    locked by OneDrive/cloud sync, or held open by a running Shiny app session).\n")
  }

} else {
  log_info("\n[STEP 3] Skipping geonames cleaning (--skip-clean)")
}

# ============================================================
# STEP 4: Upload to SharePoint
# ============================================================

if (!skip_upload) {
  if (!clean_ok && !force_upload) {
    log_warn("Skipping SharePoint upload: Clean Geonames failed this run, so data/final still holds the previous file.")
    cat("\n[WARN] [STEP 4] Skipping SharePoint upload - Clean Geonames failed, so data/final still holds the PREVIOUS run's file.\n")
    cat("    Fix the lock issue and re-run, or pass --force-upload to push the stale file anyway.\n")
    step_status$upload <- "skipped_clean_failed"
  } else {
    if (!clean_ok && force_upload) {
      cat("\n[WARN] [STEP 4] Clean Geonames failed, but --force-upload was set - uploading the PREVIOUS (stale) file anyway.\n")
    }
    upload_result <- upload_to_sharepoint("--all")
    step_status$upload <- if (upload_result) "ok" else "failed_soft"
    if (!upload_result) {
      log_warn("SharePoint upload had issues, but workflow continues")
    }
  }
} else {
  log_info("\n[STEP 4] Skipping SharePoint upload (--skip-upload)")
}

# ============================================================
# STEP 5: Optional Reports (Non-blocking)
# ============================================================

if (!skip_reports) {
  reports_result <- run_optional_reports()
  results_ok <- unlist(reports_result)
  step_status$reports <- if (all(results_ok)) {
    "ok"
  } else if (any(results_ok)) {
    "partial"
  } else {
    "failed_soft"
  }
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

# log_info()/log_warn() (from the `logger` package) run every message
# through glue::glue() to resolve "{...}" placeholders. That means any
# variable interpolated into a log message -- not just a literal string we
# wrote ourselves -- gets re-parsed for braces. A generated report or
# output filename is exactly the kind of value that can accidentally
# contain a stray "{" or "}" (e.g. left over from a templating step), and
# an unresolvable placeholder inside one makes glue() throw, which is an
# uncaught error this far down the script -- Rscript then exits non-zero
# even though every real step already finished, silently turning a fully
# successful run into a reported failure. .log_safe() doubles any brace so
# glue treats it as literal text instead of a placeholder to resolve.
.log_safe <- function(x) gsub("([{}])", "\\1\\1", x)

# List output files
# The listing below is purely informational -- it must never be able to
# turn an already-successful run into a reported failure, so it's wrapped
# in tryCatch on top of the brace-escaping above (belt and suspenders
# against whatever else a dynamically generated filename could contain).
tryCatch({
  final_dir <- file.path(BASE_DIR, "data/final")
  if (dir.exists(final_dir)) {
    output_files <- list.files(final_dir, pattern = "\\.(csv|rds|parquet|xlsx|txt)$", full.names = FALSE)
    log_info("\nOutput files ({length(output_files)}):")
    for (f in head(output_files, 20)) {
      fp <- file.path(final_dir, f)
      if (file.exists(fp)) {
        size_mb <- round(file.size(fp) / 1024 / 1024, 2)
        log_info("  - {.log_safe(f)} ({size_mb} MB)")
      }
    }
    if (length(output_files) > 20) {
      log_info("  ... and {length(output_files) - 20} more files")
    }
  }
}, error = function(e) {
  log_warn("Could not list output files (non-blocking, run already succeeded): {.log_safe(conditionMessage(e))}")
})

# List report outputs
tryCatch({
  reports_dir <- file.path(BASE_DIR, "outputs", "reports")
  if (dir.exists(reports_dir)) {
    report_files <- list.files(reports_dir, pattern = "\\.(xlsx|docx|pdf|html|md)$", full.names = FALSE, recursive = TRUE)
    if (length(report_files) > 0) {
      log_info("\nReport files ({length(report_files)}):")
      for (f in head(report_files, 10)) {
        log_info("  - {.log_safe(f)}")
      }
      if (length(report_files) > 10) {
        log_info("  ... and {length(report_files) - 10} more")
      }
    }
  }
}, error = function(e) {
  log_warn("Could not list report files (non-blocking, run already succeeded): {.log_safe(conditionMessage(e))}")
})

log_info("============================================================")

# Print to console as well
cat("\n")
cat("============================================================\n")
cat("[OK] IM WORKFLOW COMPLETED\n")
cat("============================================================\n")
cat(sprintf("Execution time: %.2f minutes\n", execution_time))
cat(sprintf("Log file: %s\n", log_file))
cat(sprintf("Output directory: %s\n", final_dir))
cat("============================================================\n")

# Any soft-fail (a step that warned but let the pipeline continue) means the
# run technically completed, but not cleanly -- worth its own status rather
# than being indistinguishable from a fully clean run in the history.
any_soft_fail <- any(unlist(step_status) %in% c("failed_soft", "partial", "skipped_clean_failed"))
write_run_manifest(if (any_soft_fail) "success_with_warnings" else "success", "")

# Return success
quit(status = 0)
