# ============================================================
# DATA LOADING & GENERAL HELPERS
# ============================================================
# Moved out of shiny_app/app.R during the app.R modularization pass.
# This file lives in shiny_app/R/ , which Shiny's runApp() sources
# automatically before app.R itself runs (shiny::loadSupport()), so
# no explicit source() call is needed anywhere -- everything defined
# here is available to app.R exactly as if it were still inline.
# Content is verbatim from the original app.R (byte-identical).
# ============================================================

# ── DATA LOADING ──────────────────────────────────────────────────────────────
load_im_data <- function() {
  for (f in c(CLEANED_RDS, CLEANED_PARQUET, CLEANED_CSV, RAW_RDS)) {
    if (!file.exists(f)) next
    df <- tryCatch(switch(tools::file_ext(f),
      rds     = readRDS(f),
      parquet = as.data.frame(arrow::read_parquet(f)),
      csv     = as.data.frame(readr::read_csv(f, show_col_types = FALSE))
    ), error = function(e) NULL)
    if (!is.null(df)) {
      names(df) <- tolower(names(df))
      if ("region"       %in% names(df) && !"province"     %in% names(df)) df <- rename(df, province     = region)
      if ("vaccine.type" %in% names(df) && !"vaccine_type" %in% names(df)) df <- rename(df, vaccine_type = `vaccine.type`)
      if (!"cv" %in% names(df) && all(c("u5_fm","u5_present") %in% names(df)))
        df$cv <- ifelse(df$u5_present > 0, df$u5_fm / df$u5_present, NA_real_)
      if ("cv" %in% names(df)) df$cv <- pmin(pmax(df$cv, 0), 1)
      for (dc in intersect(c("round_start_date","start_date_im_end","start_date"), names(df)))
        df[[dc]] <- tryCatch(as.Date(df[[dc]]), error = function(e) as.Date(NA))
      return(df)
    }
  }
  NULL
}

# ── HELPERS ───────────────────────────────────────────────────────────────────
fmt_pct <- function(x, d=1) ifelse(is.na(x), "—", paste0(round(x*100, d), "%"))
fmt_num <- function(x)       format(round(as.numeric(x)), big.mark=",", scientific=FALSE)

date_col_of <- function(df)
  intersect(c("round_start_date","start_date_im_end","start_date"), names(df))[1]

get_log_lines <- function(n = 500) {
  fls <- sort(list.files(LOGS_DIR, pattern="^workflow_.*\\.log$", full.names=TRUE))
  if (!length(fls)) return("── No workflow logs found ──")
  paste(tail(tryCatch(readLines(tail(fls,1)), error=function(e) character(0)), n), collapse="\n")
}

last_run_info <- function() {
  fls <- sort(list.files(LOGS_DIR, pattern="^workflow_.*\\.log$", full.names=TRUE))
  if (!length(fls)) return(list(time="Never", status="idle", log=""))
  latest <- tail(fls, 1)
  lns    <- tryCatch(readLines(latest), error=function(e) character(0))
  list(
    time   = format(file.mtime(latest), "%Y-%m-%d  %H:%M"),
    status = if (any(grepl("WORKFLOW COMPLETED", lns))) "ok"
             else if (any(grepl("ERROR|failed", lns, ignore.case=TRUE))) "error"
             else "warn",
    log    = paste(tail(lns, 500), collapse="\n")
  )
}

# String concatenation helper
`%+%` <- function(a, b) paste0(a, b)
