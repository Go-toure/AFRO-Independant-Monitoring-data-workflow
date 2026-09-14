# Full workflow (fetch, build, clean, upload)
Rscript scripts/run_workflow.R

# Skip fetch (use existing data)
Rscript scripts/run_workflow.R --skip-fetch

# Skip upload (don't push to SharePoint)
Rscript scripts/run_workflow.R --skip-upload

# Upload only (just push existing files to SharePoint)
Rscript scripts/run_workflow.R --upload-only

# Force full fetch
Rscript scripts/run_workflow.R --force-fetch