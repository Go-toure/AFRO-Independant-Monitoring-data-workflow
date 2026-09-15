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

# This Shiny (R) app shells out to Python scripts (Fetch_im_data.py,
# upload_to_sharepoint.py, ...) that need real packages (requests, pandas,
# pyarrow, openpyxl, PyYAML -- see requirements.txt). Without passing
# `python` here, writeManifest() only ever writes an R "packages" section,
# so Connect Cloud never provisions ANY Python environment for this piece
# of content at all -- which is exactly why those subprocess calls have
# been failing with "No module named requests" even after the base-dir
# fix. Passing `python` here makes writeManifest() also add a top-level
# "python" section (version + package_manager.package_file =
# "requirements.txt"), which is what actually triggers Connect Cloud to
# run `pip install -r requirements.txt` for this content on top of the
# R environment -- see docs.posit.co/connect/admin/python/package-management/.
python_bin <- Sys.which("python")
if (!nzchar(python_bin)) {
  stop("Could not find 'python' on PATH -- needed so writeManifest() can ",
       "detect a Python environment and add the manifest's \"python\" ",
       "section. Run this from a shell where the same `python` used by ",
       "run_workflow.R's subprocess calls is on PATH.")
}
cat("\nUsing python binary for dependency detection:", python_bin, "\n")

cat("\nGenerating manifest.json from the isolated staging folder...\n")
# NOTE: writeManifest()'s own `python` argument only populates a "python"
# section in manifest.json when it detects the app's R code actually calls
# reticulate (see github.com/rstudio/rsconnect issue #330, "reticulate is
# in use, but python was not specified"). This app has no reticulate usage
# at all -- it shells out to Python via processx, not reticulate -- so
# passing `python` here has no effect and no section gets written. Kept
# anyway (harmless) in case a future rsconnect version changes this; the
# manual injection below is what actually does the work regardless.
rsconnect::writeManifest(
  appDir = ".",
  appPrimaryDoc = "app.R",
  python = python_bin
)

manifest_path <- file.path(stage_dir, "manifest.json")
stopifnot(file.exists(manifest_path))

manifest_obj <- jsonlite::fromJSON(manifest_path)

if (is.null(manifest_obj$python)) {
  # Build the "python" section ourselves and splice it into the raw JSON
  # text (NOT by re-serializing the parsed object with jsonlite::write_json
  # -- round-tripping the full manifest through fromJSON()/toJSON() risks
  # subtly reshaping the "packages"/"files" sections, e.g. unboxing
  # single-element lists differently than rsconnect's own serializer did).
  # Connect only needs version + package_manager.package_file to know to
  # run `pip install -r requirements.txt` for this content -- see
  # docs.posit.co/connect/admin/python/package-management/.
  py_version_raw <- system2(python_bin, "--version", stdout = TRUE, stderr = TRUE)
  py_version <- trimws(sub("(?i)^python\\s+", "", py_version_raw[1], perl = TRUE))

  pip_version_raw <- tryCatch(
    system2(python_bin, c("-m", "pip", "--version"), stdout = TRUE, stderr = TRUE),
    error = function(e) ""
  )
  pip_version <- sub("^pip\\s+([0-9][0-9.]*).*", "\\1", pip_version_raw[1])
  if (!grepl("^[0-9]", pip_version)) pip_version <- "24.0"  # harmless fallback -- Connect provisions its own pip regardless

  cat("\nDetected Python", py_version, "/ pip", pip_version,
      "-- injecting a \"python\" section into manifest.json\n")

  manifest_text <- paste(readLines(manifest_path, warn = FALSE), collapse = "\n")

  python_block <- sprintf(
    paste0('"python": {\n    "version": "%s",\n    "package_manager": {\n',
           '      "name": "pip",\n      "version": "%s",\n',
           '      "package_file": "requirements.txt"\n    }\n  },\n  '),
    py_version, pip_version
  )

  anchor <- '"metadata":'
  if (!grepl(anchor, manifest_text, fixed = TRUE)) {
    stop("Could not find the \"metadata\" anchor in manifest.json to inject ",
         "the python section -- tell Claude, manifest format may have changed.")
  }
  manifest_text <- sub(anchor, paste0(python_block, anchor), manifest_text, fixed = TRUE)
  writeLines(manifest_text, manifest_path)

  # Sanity check only -- re-parse to confirm the injected text is still
  # valid JSON and now has what we just added. Never re-written from this
  # parsed copy (see note above).
  manifest_obj <- jsonlite::fromJSON(manifest_path)
}

if (is.null(manifest_obj$python)) {
  cat("\nWARNING: manifest.json still has NO \"python\" section -- Connect\n")
  cat("Cloud will NOT provision Python for this content. Tell Claude before\n")
  cat("committing this manifest.\n")
} else {
  cat("\nGood -- manifest.json now has a \"python\" section:\n")
  cat("  version:", manifest_obj$python$version, "\n")
  cat("  package_file:", manifest_obj$python$package_manager$package_file, "\n")
}

pkgs <- names(manifest_obj$packages)
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
cat("Next: git add shiny_app/manifest.json generate_shiny_manifest.R, commit, push, and retry the pipeline button on Connect Cloud.\n")
