# ============================================================
# Environment diagnostics for the run_workflow.qmd Connect Cloud
# deployment. Kept in its own file (rather than inline in the .qmd) after
# hitting a known Posit Connect Cloud bug where an oversized inline R code
# chunk in a Quarto document produces a misleading, unrelated error (e.g.
# a spurious "missing dependency" complaint) instead of the real one --
# see https://forum.posit.co/t/interactive-quarto-document-r-server-shiny-is-published-as-quarto-static-then-fails-asking-for-a-python-requirements-txt/217155
# Keeping each .qmd chunk to a single source() call sidesteps that bug
# regardless of the exact size threshold that triggers it.
# ============================================================

cat("R version:      ", R.version.string, "\n")
cat("Platform:        ", R.version$platform, "\n")
cat("Working directory:", getwd(), "\n\n")

rscript_path <- Sys.which("Rscript")
cat("Rscript found at:", if (nzchar(rscript_path)) rscript_path else "NOT FOUND", "\n")

python_path <- Sys.which("python3")
if (!nzchar(python_path)) python_path <- Sys.which("python")
cat("python found at: ", if (nzchar(python_path)) python_path else "NOT FOUND", "\n")

if (nzchar(python_path)) {
  py_version <- tryCatch(
    system2(python_path, "--version", stdout = TRUE, stderr = TRUE),
    error = function(e) paste("ERROR:", conditionMessage(e))
  )
  cat("python version:  ", paste(py_version, collapse = " "), "\n")

  # The pipeline's Python scripts need these specific packages -- worth
  # knowing up front whether they're already on the image or still need
  # requirements.txt declared for this Connect Cloud deployment.
  pkg_check <- tryCatch(
    system2(python_path, c("-c",
      shQuote("import importlib,sys; mods=['pandas','requests','pyarrow','openpyxl']; [print(m, '->', 'OK' if importlib.util.find_spec(m) else 'MISSING') for m in mods]")
    ), stdout = TRUE, stderr = TRUE),
    error = function(e) paste("ERROR:", conditionMessage(e))
  )
  cat(paste(pkg_check, collapse = "\n"), "\n")
}

cat("\nIM_WORKFLOW_HOME (as inherited, before this document sets it):",
    Sys.getenv("IM_WORKFLOW_HOME", unset = "(not set)"), "\n")

for (v in c("SHAREPOINT_TENANT_ID", "SHAREPOINT_CLIENT_ID", "SHAREPOINT_CLIENT_SECRET",
            "GPEI_API_TOKEN", "ONA_API_TOKEN")) {
  cat(sprintf("%-24s %s\n", v, if (nzchar(Sys.getenv(v))) "set" else "NOT SET"))
}
