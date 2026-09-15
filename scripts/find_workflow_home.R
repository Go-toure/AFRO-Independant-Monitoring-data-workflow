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


# ============================================================
# SHARED: find a working `python` command on whatever machine/container
# this code is running on.
# ============================================================
# Posit Connect Cloud's provisioned Python environments only put `python3`
# on PATH -- there is no plain `python` symlink -- while this laptop (and
# most local Windows setups) only has `python` on PATH, not `python3`.
# Every script in this pipeline that shells out to a .py file
# (Fetch_im_data.py, upload_to_sharepoint.py, refresh_preparedness_lookup.py,
# send_failure_alert.py) used to hardcode "python", which is exactly why
# those calls started failing with "sh: 1: python: not found" (exit code
# 127) as soon as Connect Cloud actually provisioned a Python environment
# for this content (see the manifest.json "python" section fix) -- that
# fixed the *presence* of the packages, but not the command name used to
# invoke them. This tries both, in the order most likely to be right for
# a fresh container, and fails loudly (a clear stop(), not a silent
# fallback) if truly neither is on PATH.
find_python_cmd <- function() {
  for (cmd in c("python3", "python")) {
    if (nzchar(Sys.which(cmd))) return(cmd)
  }
  stop("Could not find 'python3' or 'python' on PATH -- every pipeline ",
       "step that shells out to a Python script needs one of these to exist.")
}


# ============================================================
# SHARED: make sure the resolved python has this project's Python package
# dependencies installed, installing them on first use if not.
# ============================================================
# Posit Connect Cloud creates a real, writable Python venv for content that
# declares one in manifest.json (see generate_shiny_manifest.R) and wires
# it up via RETICULATE_PYTHON -- but as of Connect Cloud 2026.08.1, that
# venv comes up EMPTY for a Shiny (R) app: the requirements.txt-driven pip
# install that self-hosted Posit Connect's own docs describe simply never
# runs for this content type (confirmed via a build log showing an R
# package list but no Python/pip section at all). Rather than depend on
# Connect Cloud ever fixing that, install the packages ourselves, once, the
# first time anything needs them -- the venv persists for the life of the
# container, so every pipeline step after the first one in a given session
# just finds them already there and skips straight through.
ensure_python_packages <- function(python_cmd, base_dir) {
  check_code <- suppressWarnings(system2(
    python_cmd,
    c("-c", shQuote("import requests, pandas, pyarrow, openpyxl, yaml")),
    stdout = FALSE, stderr = FALSE
  ))
  if (identical(check_code, 0L)) return(invisible(TRUE))

  req_file <- file.path(base_dir, "requirements.txt")
  if (!file.exists(req_file)) {
    cat("[SETUP] Python packages missing and no requirements.txt found at",
        req_file, "-- cannot self-install.\n")
    return(invisible(FALSE))
  }

  # Discovered on Connect Cloud 2026.09: this venv's python3 doesn't even
  # have `pip` as an importable module ("No module named pip") -- the venv
  # was created without it. Bootstrap pip first, trying two methods before
  # giving up: (1) the standard library's own ensurepip module, which is
  # the normal way to put pip into a pip-less venv; (2) if ensurepip itself
  # was stripped from this Python build too, fetch get-pip.py and run it
  # in-process with the same interpreter -- that script only needs urllib,
  # which is always present, to install pip from scratch.
  pip_check_code <- suppressWarnings(system2(
    python_cmd, c("-m", "pip", "--version"), stdout = FALSE, stderr = FALSE
  ))
  if (!identical(pip_check_code, 0L)) {
    cat("[SETUP]", python_cmd, "has no pip -- bootstrapping via ensurepip...\n")
    ensurepip_code <- suppressWarnings(system2(
      python_cmd, c("-m", "ensurepip", "--upgrade"), stdout = FALSE, stderr = FALSE
    ))
    if (!identical(ensurepip_code, 0L)) {
      cat("[SETUP] ensurepip unavailable too -- falling back to get-pip.py...\n")
      get_pip_code <- system2(
        python_cmd,
        c("-c", shQuote(paste(
          "import urllib.request;",
          "exec(urllib.request.urlopen('https://bootstrap.pypa.io/get-pip.py').read())"
        )))
      )
      if (!identical(get_pip_code, 0L)) {
        cat("[SETUP] WARNING: could not bootstrap pip by any method --",
            "Python-dependent steps may still fail this run.\n")
        return(invisible(FALSE))
      }
    }
    cat("[SETUP] pip bootstrapped successfully.\n")
  }

  cat("[SETUP] Python packages missing from", python_cmd,
      "-- installing from", req_file, "(one-time, persists for this container)...\n")
  install_code <- system2(
    python_cmd, c("-m", "pip", "install", "--quiet", "-r", shQuote(req_file))
  )
  if (!identical(install_code, 0L)) {
    cat("[SETUP] WARNING: pip install exited with status", install_code,
        "-- Python-dependent steps may still fail this run.\n")
    return(invisible(FALSE))
  }

  cat("[SETUP] Python packages installed successfully.\n")
  invisible(TRUE)
}
