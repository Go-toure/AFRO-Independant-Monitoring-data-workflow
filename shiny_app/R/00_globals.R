# ============================================================
# PACKAGES, PATHS, CREDENTIALS & PALETTE
# ============================================================
# Moved out of shiny_app/app.R during the app.R modularization pass.
# This file lives in shiny_app/R/ , which Shiny's runApp() sources
# automatically before app.R itself runs (shiny::loadSupport()), so
# no explicit source() call is needed anywhere -- everything defined
# here is available to app.R exactly as if it were still inline.
# Content is verbatim from the original app.R (byte-identical). Moved here (rather than left inline in app.R) because several helpers now living in R/data_helpers.R and R/ai_assistant_tools.R reference these globals (CLEANED_RDS/CLEANED_PARQUET/CLEANED_CSV/RAW_RDS, LOGS_DIR, AI_ASSISTANT_ENABLED) -- and a function defined in R/ can only see globals that were also assigned in R/ or earlier, never ones left behind in app.R itself. Named with a 00_ prefix purely so it reads first in this folder; Shiny does not require that ordering since these are plain global assignments, not function calls, so every other R/ file can already see them by the time it is actually used.
# ============================================================

# ============================================================
# AFRO IM Dashboard — Beautiful Modern Edition
# WHO AFRO Independent Monitoring
# ============================================================

pkgs_needed <- c("shiny","bslib","bsicons","DT","plotly","dplyr",
                 "readr","lubridate","arrow","shinyjs","scales","processx",
                 "ellmer","shinychat")
new_pkgs <- pkgs_needed[!pkgs_needed %in% rownames(installed.packages())]
if (length(new_pkgs) > 0) install.packages(new_pkgs, quiet = TRUE)

suppressPackageStartupMessages({
  library(shiny);    library(bslib);     library(bsicons)
  library(DT);       library(plotly);    library(dplyr)
  library(readr);    library(lubridate); library(arrow)
  library(shinyjs);  library(scales)
  library(ellmer);   library(shinychat)
})

# ── CONFIG ────────────────────────────────────────────────────────────────────
# BASE_DIR is resolved by find_workflow_home(), defined once in the shared
# scripts/find_workflow_home.R (also sourced by scripts/run_workflow.R
# itself) -- kept in exactly one file so a path-resolution fix, like the
# one that created that file, never needs to be applied twice again and
# can never silently drift out of sync between the dashboard and the
# pipeline script it launches.
# Set IM_WORKFLOW_HOME via `setx IM_WORKFLOW_HOME "D:/new/path"` (Windows)
# only if you want to force a specific location; it is optional everywhere
# else now -- see find_workflow_home.R's own header comment for the full
# resolution order.
.globals_candidate_paths <- c(
  file.path("..", "scripts", "find_workflow_home.R"),  # cwd = shiny_app/  (normal: Shiny's runApp())
  file.path("scripts", "find_workflow_home.R")         # cwd = repo root   (fallback)
)
.globals_shared_file <- .globals_candidate_paths[file.exists(.globals_candidate_paths)][1]
if (is.na(.globals_shared_file)) {
  stop("Could not find scripts/find_workflow_home.R from working directory: ", getwd())
}
source(.globals_shared_file)
rm(.globals_candidate_paths, .globals_shared_file)

BASE_DIR     <- find_workflow_home()
WORKFLOW_DIR <- BASE_DIR
PYTHON_CMD   <- find_python_cmd()
# Installs this project's Python packages into PYTHON_CMD's venv on first
# app startup in a fresh container, if Connect Cloud hasn't already done
# it -- see ensure_python_packages()'s own comment in find_workflow_home.R.
# Runs once per container lifetime: after this, every subprocess call
# (Fetch Data, Upload SharePoint, ...) just finds the packages already there.
ensure_python_packages(PYTHON_CMD, BASE_DIR)
SCRIPTS_DIR <- file.path(BASE_DIR, "scripts")
FINAL_DIR   <- file.path(BASE_DIR, "data/final")
LOGS_DIR    <- file.path(BASE_DIR, "logs")
REPORTS_DIR <- file.path(BASE_DIR, "outputs/reports/IM_Intelligence_Report")
CONFIG_DIR  <- file.path(BASE_DIR, "config")

for (path in c(FINAL_DIR, LOGS_DIR, REPORTS_DIR))
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)

# ── AI Assistant credentials ─────────────────────────────────────────────────
# Loads config/secrets.env (git-ignored) the same way the Python pipeline
# scripts do via scripts/_env_loader.py: a real environment variable always
# wins, this file is just a convenience fallback for local runs.
secrets_env_file <- file.path(CONFIG_DIR, "secrets.env")
if (file.exists(secrets_env_file)) {
  for (ln in readLines(secrets_env_file, warn = FALSE)) {
    ln <- trimws(ln)
    if (!nzchar(ln) || startsWith(ln, "#") || !grepl("=", ln, fixed = TRUE)) next
    key <- trimws(sub("=.*$", "", ln))
    val <- trimws(sub("^[^=]*=", "", ln))
    val <- gsub('^["\']|["\']$', "", val)   # strip surrounding quotes, if any
    if (nzchar(key) && identical(Sys.getenv(key), ""))
      do.call(Sys.setenv, setNames(list(val), key))
  }
}
AI_ASSISTANT_ENABLED <- nzchar(Sys.getenv("ANTHROPIC_API_KEY"))

CLEANED_RDS     <- file.path(FINAL_DIR, "Regional_IM_repository_cleaned.rds")
CLEANED_PARQUET <- file.path(FINAL_DIR, "Regional_IM_repository_cleaned.parquet")
CLEANED_CSV     <- file.path(FINAL_DIR, "Regional_IM_repository_cleaned.csv")
RAW_RDS         <- file.path(FINAL_DIR, "Regional_IM_repository.rds")

C_ <- list(                          # palette
  blue   = "#005C97", blue2  = "#003F6B", blue3  = "#1A7BBF",
  teal   = "#00C9C8", teal2  = "#007B8A",
  green  = "#27AE60", green2 = "#1A7A44",
  orange = "#E8730A", orange2= "#B8520A",
  red    = "#C0392B", red2   = "#922B21",
  purple = "#8E44AD", purple2= "#5D2A7A",
  dark   = "#1A2637", dark2  = "#243447",
  bg     = "#F0F4F8", muted  = "#6C7A8D"
)

