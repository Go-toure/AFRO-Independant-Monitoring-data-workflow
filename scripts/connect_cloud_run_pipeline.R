# ============================================================
# Runs the actual IM workflow pipeline for the run_workflow.qmd Connect
# Cloud deployment. Kept in its own file (rather than inline in the .qmd)
# for the same reason as connect_cloud_diagnostics.R -- see that file's
# header comment.
# ============================================================

# This deployed document's own directory IS the workflow's BASE_DIR on
# Connect Cloud -- data/, config/, scripts/, outputs/, logs/ all deploy
# alongside it from the same git repo (data/outputs/logs start out empty
# here since they're git-ignored; the pipeline's own SharePoint recovery
# steps -- Fetch_im_data.py's raw_state sync, refresh_preparedness_lookup's
# lookup_state sync, run_workflow.R's sp_recover_baseline_file() -- are
# exactly what repopulate them on a from-scratch container like this one).
# run_workflow.R reads its BASE_DIR from the IM_WORKFLOW_HOME env var,
# defaulting to a Windows-only laptop path -- set it here so the exact
# same, unmodified script works on both.
base_dir <- getwd()
if (!nzchar(Sys.getenv("IM_WORKFLOW_HOME"))) {
  Sys.setenv(IM_WORKFLOW_HOME = base_dir)
}

workflow_script <- file.path(base_dir, "scripts", "run_workflow.R")
stopifnot(file.exists(workflow_script))

# run_workflow.R calls quit() at several points, including on a clean
# success -- sourcing it directly into this chunk would kill this
# Quarto render's own R session before it could finish producing this
# report. Running it as its own Rscript subprocess (the same trick
# run_workflow.R itself already uses internally for the R sub-steps that
# call quit() -- see run_r_script()) keeps it isolated: quit() only ends
# the child process, and this chunk gets the child's captured output and
# exit code back cleanly.
#
# Args: start with "--skip-fetch" for the first few scheduled runs on
# Connect Cloud (cheaper, and doesn't need ONA_API_TOKEN yet) -- once
# those are confirmed working end-to-end, drop it for the real full
# production run (fetch + build + clean + reports + upload).
workflow_args <- c("--skip-fetch")

result <- system2(
  "Rscript",
  args = c(shQuote(workflow_script), workflow_args),
  stdout = TRUE, stderr = TRUE
)

cat(result, sep = "\n")

exit_status <- attr(result, "status")
if (is.null(exit_status)) exit_status <- 0L

if (exit_status != 0L) {
  stop(sprintf(
    "run_workflow.R exited with non-zero status %s -- see the captured output above for the real error.",
    exit_status
  ))
}

cat("\nrun_workflow.R completed successfully (exit status 0).\n")
