# ============================================================
# Step 6a (opt-in): export the cleaned IM repository for AFRO-Dash
# ============================================================
# Reads  data/final/Regional_IM_repository_cleaned.rds
# Writes <AFRO-Dash>/input/AFRO_IM_data.rds   (read by the "IM Overview" tab)
#
#   * column names are lower-cased (what the dashboard expects)
#   * the file carries an "im_published_at" attribute (shown as "Last Data Update")
#   * written atomically (temp file, then rename) so a half-written file can never
#     reach the dashboard
#   * refuses to overwrite a good file with an empty / obviously broken one
#
# Run by:  Rscript scripts/run_workflow.R --push-afro-dash
# Alone :  Rscript scripts/export_afro_dash_data.R
#
# Environment overrides
#   IM_WORKFLOW_HOME      workflow folder (default: the folder above scripts/)
#   AFRO_DASH_REPO        AFRO-Dash git folder (default: sibling "AFRO-Dash")
#   AFRO_DASH_INPUT_DIR   write here instead of <AFRO-Dash>/input
# ============================================================

.this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
base_dir <- Sys.getenv("IM_WORKFLOW_HOME", unset = "")
if (!nzchar(base_dir)) {
  base_dir <- if (length(.this_file)) dirname(dirname(normalizePath(.this_file))) else getwd()
}
dash_repo <- Sys.getenv("AFRO_DASH_REPO", unset = "")
if (!nzchar(dash_repo)) dash_repo <- file.path(dirname(normalizePath(base_dir)), "AFRO-Dash")
out_dir <- Sys.getenv("AFRO_DASH_INPUT_DIR", unset = "")
if (!nzchar(out_dir)) out_dir <- file.path(dash_repo, "input")

src <- file.path(base_dir, "data", "final", "Regional_IM_repository_cleaned.rds")
dst <- file.path(out_dir, "AFRO_IM_data.rds")

say  <- function(...) cat("[export-afro-dash]", ..., "\n")
fail <- function(...) { say("ERROR:", ...); quit(status = 1) }

if (!file.exists(src)) fail("source file not found:", src)
if (!dir.exists(out_dir)) fail("AFRO-Dash input folder not found:", out_dir,
                               "(set AFRO_DASH_REPO or AFRO_DASH_INPUT_DIR)")

df <- tryCatch(readRDS(src), error = function(e) fail("cannot read", src, "-", conditionMessage(e)))
df <- as.data.frame(df, stringsAsFactors = FALSE)
names(df) <- tolower(names(df))

# ---- sanity checks (never publish a broken file) ----------------------------------------
required <- c("country", "district", "u5_present", "u5_fm")
miss <- setdiff(required, names(df))
if (length(miss)) fail("required column(s) missing:", paste(miss, collapse = ", "))
if (nrow(df) < 1000) fail("only", nrow(df), "rows - refusing to publish (expected thousands)")
if (sum(!is.na(df$country)) == 0) fail("country column is empty")

if (file.exists(dst)) {
  old <- tryCatch(readRDS(dst), error = function(e) NULL)
  if (!is.null(old) && nrow(df) < 0.5 * nrow(old))
    fail(sprintf("new file has %d rows vs %d in the published one - looks truncated; refusing",
                 nrow(df), nrow(old)))
}

attr(df, "im_published_at") <- Sys.time()

tmp <- paste0(dst, ".tmp")
saveRDS(df, tmp, compress = "xz")
if (!file.rename(tmp, dst)) {
  ok <- file.copy(tmp, dst, overwrite = TRUE); unlink(tmp)
  if (!ok) fail("could not write", dst)
}
say(sprintf("wrote %s  (%s rows, %s columns, %.1f MB)", dst,
            format(nrow(df), big.mark = ","), ncol(df), file.size(dst) / 1e6))
quit(status = 0)
