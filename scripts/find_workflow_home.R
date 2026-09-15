# ============================================================
# SHARED: locate the pipeline's repo root (BASE_DIR) on whatever
# machine/container this code happens to be running on.
# ============================================================
# Used by BOTH shiny_app/R/00_globals.R (the Shiny dashboard itself) and
# this file's sibling, run_workflow.R (run standalone via Rscript, or
# spawned by the dashboard as a subprocess) -- kept in exactly ONE place
# so a path-resolution fix, like the one that created this file, never
# needs to be applied twice again and can silently drift out of sync.
#
# Resolution order:
#   1. IM_WORKFLOW_HOME, but only if it actually contains scripts/run_workflow.R --
#      this guards against a stale/wrong value (e.g. a leftover container path
#      from a previous Connect Cloud deployment) silently pointing at nothing.
#   2. Search upward from the current working directory for a folder that
#      contains scripts/run_workflow.R. Both the Shiny dashboard (runApp()
#      sets the working directory to shiny_app/) and run_workflow.R itself,
#      when launched by the dashboard as a subprocess (which inherits the
#      dashboard's working directory), land one level below the repo root --
#      so on Connect Cloud, where the whole repo is checked out fresh into a
#      new, unpredictable path on every deploy, this finds the real repo
#      root with no manually set variable needed at all.
#   3. This laptop's known local path, as a last-resort fallback so nothing
#      breaks if both of the above somehow fail.
# Set IM_WORKFLOW_HOME via `setx IM_WORKFLOW_HOME "D:/new/path"` (Windows)
# only if you want to force a specific location; it is optional everywhere
# else now.
find_workflow_home <- function() {
  env_val <- Sys.getenv("IM_WORKFLOW_HOME", unset = "")
  if (nzchar(env_val) && file.exists(file.path(env_val, "scripts", "run_workflow.R")))
    return(normalizePath(env_val, mustWork = FALSE))

  dir <- getwd()
  for (i in 1:6) {
    if (file.exists(file.path(dir, "scripts", "run_workflow.R")))
      return(normalizePath(dir, mustWork = FALSE))
    parent <- dirname(dir)
    if (identical(parent, dir)) break  # reached filesystem root
    dir <- parent
  }

  "C:/Users/TOURE/Documents/im_workflow"
}
