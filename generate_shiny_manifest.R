# One-off script: regenerates shiny_app/manifest.json -- the manifest
# Connect Cloud actually reads for THIS content (primary file
# shiny_app/app.R, appmode "shiny"). This is a separate file from the
# repo-root manifest.json (which is scoped to run_workflow.qmd / the
# Quarto content) -- see generate_manifest.R's own comment for that half
# of the story.
#
# Why this needs regenerating: the dashboard's own "Run Full Pipeline"
# button invokes scripts/run_workflow.R as a subprocess (via processx),
# not via source() or library() from app.R. rsconnect's dependency
# scanner only sees files it can actually reach from appDir, so a plain
# writeManifest() scoped to shiny_app/ alone never notices anything
# run_workflow.R itself needs (e.g. the `logger` package) -- exactly the
# same class of blind spot the qmd manifest had before, just mirrored
# for the Shiny side. Fix: stage shiny_app/'s own files AND every file
# the pipeline touches into one isolated folder, then scan that.
#
# Run this from the repo root, either:
#   - In PowerShell:
#       cd C:\Users\TOURE\Documents\Gith_repositories\AFRO-Independant-Monitoring-data-workflow
#       & "C:\Program Files\R\R-4.4.1\bin\x64\Rscript.exe" generate_shiny_manifest.R
#   - Or from an R console already `setwd()`'d to that folder:
#       source("generate_shiny_manifest.R")

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  cat("Installing rsconnect...\n")
  install.packages("rsconnect")
}

repo_root <- normalizePath(".")
stopifnot(file.exists(file.path(repo_root, "shiny_app", "app.R")))  # sanity check: are we in the repo root?

# shiny_app's own files, staged at the root of the scan folder (so
# app.R is directly where rsconnect expects a Shiny primary doc).
shiny_r_files <- list.files(file.path(repo_root, "shiny_app", "R"), pattern = "\\.R$", full.names = FALSE)
stopifnot(length(shiny_r_files) > 0)

# Everything the pipeline itself touches -- identical list to
# generate_manifest.R's pipeline_files (minus run_workflow.qmd, which is
# irrelevant here), since run_workflow.R is the same script either way.
pipeline_files <- c(
  "requirements.txt",
  "config/config.yaml",
  "config/secrets.env.example",
  "scripts/run_workflow.R",
  "scripts/connect_cloud_diagnostics.R",
  "scripts/connect_cloud_run_pipeline.R",
  "scripts/regional_im_repository_builder.R",
  "scripts/clean_geonames.R",
  "scripts/AFRO_Advocacy_Intelligence_Report.R",
  "scripts/afro_im_intilligence_analysis_engine.R",
  "scripts/afro_region_im_deck_generation.R",
  "scripts/Fetch_im_data.py",
  "scripts/refresh_preparedness_lookup.py",
  "scripts/upload_to_sharepoint.py",
  "scripts/send_failure_alert.py",
  "scripts/_env_loader.py",
  "scripts/_sharepoint_client.py"
)

missing <- pipeline_files[!file.exists(file.path(repo_root, pipeline_files))]
if (length(missing) > 0) {
  stop("These expected files are missing -- fix the list before continuing:\n",
       paste(" -", missing, collapse = "\n"))
}

# A sibling of the repo, not nested inside it -- guarantees nothing else
# in the repo (the qmd, _archive/, old diagnose_*.R scripts, etc.) can
# accidentally end up in the scanned tree.
stage_dir <- file.path(dirname(repo_root), "_connect_cloud_shiny_stage")
if (dir.exists(stage_dir)) unlink(stage_dir, recursive = TRUE)
dir.create(stage_dir, recursive = TRUE)

cat("Staging shiny_app/app.R + R/ (", length(shiny_r_files), "files) into:", stage_dir, "\n")
file.copy(file.path(repo_root, "shiny_app", "app.R"), file.path(stage_dir, "app.R"), overwrite = TRUE)
dir.create(file.path(stage_dir, "R"), showWarnings = FALSE)
for (f in shiny_r_files) {
  file.copy(file.path(repo_root, "shiny_app", "R", f), file.path(stage_dir, "R", f), overwrite = TRUE)
}

cat("Staging", length(pipeline_files), "pipeline files into the same folder\n")
for (f in pipeline_files) {
  dest <- file.path(stage_dir, f)
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(repo_root, f), dest, overwrite = TRUE)
}

old_wd <- setwd(stage_dir)
on.exit(setwd(old_wd), add = TRUE)

cat("\nGenerating manifest.json from the isolated staging folder...\n")
rsconnect::writeManifest(
  appDir = ".",
  appPrimaryDoc = "app.R"
)

manifest_path <- file.path(stage_dir, "manifest.json")
stopifnot(file.exists(manifest_path))

pkgs <- names(jsonlite::fromJSON(manifest_path)$packages)
cat("\nCaptured", length(pkgs), "R package dependencies:\n")
cat(paste(" -", sort(pkgs)), sep = "\n")

if ("logger" %in% pkgs) {
  cat("\nGood -- 'logger' is now in the list.\n")
} else {
  cat("\nWARNING: 'logger' is STILL missing from the scan. Tell Claude\n")
  cat("before committing this manifest -- something else is wrong.\n")
}

dest_manifest <- file.path(repo_root, "shiny_app", "manifest.json")
file.copy(manifest_path, dest_manifest, overwrite = TRUE)
cat("\nCopied manifest.json into:", dest_manifest, "\n")
cat("Next: git add shiny_app/manifest.json generate_shiny_manifest.R, commit, push, and retry the pipeline button on Connect Cloud.\n"
