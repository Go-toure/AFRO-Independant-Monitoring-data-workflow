# ============================================================
# DOWNLOAD RAW FORM DATA (Pipeline tab)
# ============================================================
# R/UI counterpart to scripts/fetch_sharepoint_csvs.py: lets someone pull
# one form's raw data straight from SharePoint's raw_state folder without
# leaving the app, in csv/xlsx/rds/parquet, with the same "split into one
# file per calendar year once it's too big for one Excel sheet" behavior
# that script and the pipeline's own CSV/Parquet partitioning already use.
#
# Deliberately does NOT shell out to fetch_sharepoint_csvs.py: two of the
# four formats here (.rds, and the Excel engine) are R-native, and every
# format this needs (csv, parquet) already has a matching file sitting in
# raw_state, so a plain Graph list/download (via R/data_source_sharepoint.R's
# sp_list_folder()/sp_download_file()) is simpler and avoids a Python
# subprocess round-trip just to move bytes this app can already fetch
# itself with the credentials it already has.
#
# Every file this writes lives under R's own tempdir() -- never a fixed
# path on any one person's machine -- so this works identically on Posit
# Connect Cloud or a local run, and never collides between two people
# downloading different forms from the same running app at once (each
# call gets its own work_dir, tagged with form id + format + timestamp).
#
# Row-count vs. format:
#   parquet -- always the single combined {form_id}.parquet. Parquet has no
#              practical row limit, so there's nothing to partition, even
#              for a "heavy" form (the pipeline itself keeps a combined
#              Parquet for every form, heavy or not -- see Fetch_im_data.py's
#              upload_raw_to_sharepoint()).
#   csv     -- whatever the pipeline already put in raw_state: a single
#              combined {form_id}.csv for a normal form, or the existing
#              per-year {form_id}_{year}.csv files (zipped) for a "heavy"
#              one -- Fetch_im_data.py never uploads a combined CSV for a
#              heavy form in the first place (it would exceed Excel's row
#              limit), so there is no combined CSV to fall back to there.
#   xlsx    -- the one format Excel's ~1,048,575-row-per-sheet limit
#              actually constrains. A "heavy" form always gets one .xlsx
#              per year (zipped), built from the same per-year Parquet
#              partitions the pipeline already maintains under
#              raw_state/partitions/{form_id}/. A normal form gets one
#              combined .xlsx; if its row count still somehow exceeds the
#              limit (shouldn't happen -- see _PARTITION_ROW_THRESHOLD's
#              own reasoning in Fetch_im_data.py), it falls back to
#              splitting by the same _submission_time year key rather than
#              failing outright.
#   rds     -- always one combined .rds. RDS has no row-count ceiling and
#              an R user opening this almost always wants one data.frame,
#              not several files to rbind by hand -- so unlike xlsx, a
#              "heavy" form's year partitions are read and combined with
#              dplyr::bind_rows() before being saved as a single file.

# Same raw_state root every other part of this workflow already uses (see
# scripts/Fetch_im_data.py's SP_RAW_FOLDER).
RAW_STATE_FOLDER <- "7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/raw_state"

# Excel's hard per-sheet row limit (including the header row) -- one data
# row less, since the header takes the first slot. Same constant
# scripts/Fetch_im_data.py's _CSV_EXPORT_MAX_ROWS and
# scripts/fetch_sharepoint_csvs.py's _EXCEL_ROW_LIMIT are built around.
RAW_DL_EXCEL_ROW_LIMIT <- 1048575L

sp_partition_folder <- function(form_id) {
  paste0(RAW_STATE_FOLDER, "/partitions/", form_id)
}

.sp_item_name <- function(item) {
  if (is.null(item$name)) "" else item$name
}

# Every form id currently sitting in raw_state, read straight from what's
# actually there right now -- never a hardcoded list, so it can never drift
# out of sync as forms are added or retired from the pipeline's own
# config. A combined per-form Parquet file is named exactly "{form_id}.parquet"
# (a bare integer stem) -- this excludes both the year-partition twins like
# "4498_2020.parquet" and the "partitions" subfolder itself, which would
# otherwise also show up in this same folder listing.
list_available_form_ids <- function() {
  if (!sharepoint_credentials_available()) return(character(0))
  tryCatch({
    token    <- sp_get_graph_token()
    drive_id <- sp_resolve_drive_id(token)
    items    <- sp_list_folder(token, drive_id, RAW_STATE_FOLDER)
    names    <- vapply(items, .sp_item_name, character(1))
    m        <- grepl("^[0-9]+\\.parquet$", names)
    ids      <- as.integer(sub("\\.parquet$", "", names[m]))
    as.character(sort(ids))
  }, error = function(e) character(0))
}

# TRUE if this form has year-partitioned Parquet files on SharePoint (i.e.
# the pipeline treats it as a "heavy" form -- see Fetch_im_data.py's
# _is_form_partitioned()). Mirrors that check by looking for the same
# partitions/{form_id}/ folder the pipeline itself writes to and recovers
# from.
form_is_partitioned <- function(token, drive_id, form_id) {
  length(sp_list_folder(token, drive_id, sp_partition_folder(form_id))) > 0
}

.partition_year_files <- function(token, drive_id, form_id) {
  items <- sp_list_folder(token, drive_id, sp_partition_folder(form_id))
  names <- vapply(items, .sp_item_name, character(1))
  sort(names[grepl(paste0("^", form_id, "_[0-9]{4}\\.parquet$"), names)])
}

# Downloads either the single combined Parquet (normal form) or every
# year-partition Parquet (heavy form) into work_dir and returns them all
# read in as one combined data.frame (dplyr::bind_rows() across years, so
# a schema change between years doesn't break the combine). NULL on total
# failure (nothing could be downloaded/read).
fetch_form_dataframe <- function(token, drive_id, form_id, heavy, work_dir) {
  if (!heavy) {
    remote <- paste0(RAW_STATE_FOLDER, "/", form_id, ".parquet")
    local  <- file.path(work_dir, paste0(form_id, ".parquet"))
    if (!sp_download_file(token, drive_id, remote, local)) return(NULL)
    return(tryCatch(as.data.frame(arrow::read_parquet(local)), error = function(e) NULL))
  }
  year_files <- .partition_year_files(token, drive_id, form_id)
  if (!length(year_files)) return(NULL)
  frames <- list()
  for (nm in year_files) {
    local  <- file.path(work_dir, nm)
    remote <- paste0(sp_partition_folder(form_id), "/", nm)
    if (!sp_download_file(token, drive_id, remote, local)) next
    df <- tryCatch(as.data.frame(arrow::read_parquet(local)), error = function(e) NULL)
    if (!is.null(df)) frames[[nm]] <- df
  }
  if (!length(frames)) return(NULL)
  dplyr::bind_rows(frames)
}

.zip_files <- function(paths, zip_path, work_dir) {
  zip::zip(zip_path, files = basename(paths), root = work_dir)
  zip_path
}

build_parquet_download <- function(token, drive_id, form_id, heavy, work_dir) {
  remote <- paste0(RAW_STATE_FOLDER, "/", form_id, ".parquet")
  local  <- file.path(work_dir, paste0(form_id, ".parquet"))
  if (!sp_download_file(token, drive_id, remote, local))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Could not download ", form_id, ".parquet from SharePoint.")))
  list(ok = TRUE, path = local, message = NULL)
}

build_csv_download <- function(token, drive_id, form_id, heavy, work_dir) {
  if (!heavy) {
    remote <- paste0(RAW_STATE_FOLDER, "/", form_id, ".csv")
    local  <- file.path(work_dir, paste0(form_id, ".csv"))
    if (!sp_download_file(token, drive_id, remote, local))
      return(list(ok = FALSE, path = NULL,
                  message = paste0("Could not download ", form_id, ".csv from SharePoint.")))
    return(list(ok = TRUE, path = local, message = NULL))
  }
  # Heavy form: per-year CSVs already sit in raw_state's own root (not the
  # partitions/ subfolder, which holds Parquet only) -- see
  # scripts/Fetch_im_data.py's _upload_csv_partitions_to_sharepoint().
  items      <- sp_list_folder(token, drive_id, RAW_STATE_FOLDER)
  names      <- vapply(items, .sp_item_name, character(1))
  year_files <- sort(names[grepl(paste0("^", form_id, "_[0-9]{4}\\.csv$"), names)])
  if (!length(year_files))
    return(list(ok = FALSE, path = NULL,
                message = paste0("No year-partitioned CSVs found for form ", form_id, ".")))
  paths <- character(0)
  for (nm in year_files) {
    local <- file.path(work_dir, nm)
    if (sp_download_file(token, drive_id, paste0(RAW_STATE_FOLDER, "/", nm), local))
      paths <- c(paths, local)
  }
  if (!length(paths))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Failed to download any year-partitioned CSV for form ", form_id, ".")))
  zip_path <- .zip_files(paths, file.path(work_dir, paste0(form_id, "_csv_by_year.zip")), work_dir)
  list(ok = TRUE, path = zip_path, message = NULL)
}

.write_xlsx_or_na <- function(df, path) {
  tryCatch({ openxlsx::write.xlsx(df, path, overwrite = TRUE); TRUE },
           error = function(e) {
             message("[download] xlsx write failed for ", path, ": ", conditionMessage(e))
             FALSE
           })
}

# Defensive fallback for a form the pipeline doesn't consider "heavy" that
# nonetheless comes back over Excel's row limit -- splits by the same
# _submission_time year key the pipeline itself partitions by, rather than
# failing the download outright.
build_xlsx_year_partitions_from_df <- function(df, form_id, work_dir) {
  if (!"_submission_time" %in% names(df))
    return(list(ok = FALSE, path = NULL,
                message = paste0(
                  nrow(df), " rows exceeds Excel's per-sheet row limit and there is no ",
                  "_submission_time column to split by year -- try CSV, Parquet, or RDS instead."
                )))
  years <- substr(as.character(df[["_submission_time"]]), 1, 4)
  years[is.na(years) | !grepl("^[0-9]{4}$", years)] <- "0000"
  xlsx_paths <- character(0)
  for (yr in sort(unique(years))) {
    sub_df <- df[years == yr, , drop = FALSE]
    xlsx_local <- file.path(work_dir, paste0(form_id, "_", yr, ".xlsx"))
    if (.write_xlsx_or_na(sub_df, xlsx_local)) xlsx_paths <- c(xlsx_paths, xlsx_local)
  }
  if (!length(xlsx_paths))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Could not build any yearly .xlsx for form ", form_id, ".")))
  zip_path <- .zip_files(xlsx_paths, file.path(work_dir, paste0(form_id, "_xlsx_by_year.zip")), work_dir)
  list(ok = TRUE, path = zip_path, message = NULL)
}

build_xlsx_download <- function(token, drive_id, form_id, heavy, work_dir) {
  if (!heavy) {
    df <- fetch_form_dataframe(token, drive_id, form_id, FALSE, work_dir)
    if (is.null(df))
      return(list(ok = FALSE, path = NULL, message = paste0("Could not read data for form ", form_id, ".")))
    if (nrow(df) > RAW_DL_EXCEL_ROW_LIMIT)
      return(build_xlsx_year_partitions_from_df(df, form_id, work_dir))
    local <- file.path(work_dir, paste0(form_id, ".xlsx"))
    if (!.write_xlsx_or_na(df, local))
      return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", form_id, ".xlsx.")))
    return(list(ok = TRUE, path = local, message = NULL))
  }
  # Heavy form: one .xlsx per year, straight from the same year-partition
  # Parquet files the pipeline itself already maintains -- each year's
  # slice is comfortably under Excel's row limit for the same reason
  # Fetch_im_data.py's own CSV year-partitioning relies on (new submissions
  # almost always land in the current year, so no single year has ever
  # approached the form's overall total).
  year_files <- .partition_year_files(token, drive_id, form_id)
  if (!length(year_files))
    return(list(ok = FALSE, path = NULL, message = paste0("No year partitions found for form ", form_id, ".")))
  xlsx_paths <- character(0)
  for (nm in year_files) {
    local_pq <- file.path(work_dir, nm)
    remote   <- paste0(sp_partition_folder(form_id), "/", nm)
    if (!sp_download_file(token, drive_id, remote, local_pq)) next
    df <- tryCatch(as.data.frame(arrow::read_parquet(local_pq)), error = function(e) NULL)
    if (is.null(df)) next
    year <- sub(paste0("^", form_id, "_([0-9]{4})\\.parquet$"), "\\1", nm)
    xlsx_local <- file.path(work_dir, paste0(form_id, "_", year, ".xlsx"))
    if (.write_xlsx_or_na(df, xlsx_local)) xlsx_paths <- c(xlsx_paths, xlsx_local)
  }
  if (!length(xlsx_paths))
    return(list(ok = FALSE, path = NULL, message = paste0("Could not build any yearly .xlsx for form ", form_id, ".")))
  zip_path <- .zip_files(xlsx_paths, file.path(work_dir, paste0(form_id, "_xlsx_by_year.zip")), work_dir)
  list(ok = TRUE, path = zip_path, message = NULL)
}

build_rds_download <- function(token, drive_id, form_id, heavy, work_dir) {
  df <- fetch_form_dataframe(token, drive_id, form_id, heavy, work_dir)
  if (is.null(df))
    return(list(ok = FALSE, path = NULL, message = paste0("Could not read data for form ", form_id, ".")))
  local <- file.path(work_dir, paste0(form_id, ".rds"))
  ok <- tryCatch({ saveRDS(df, local); TRUE }, error = function(e) FALSE)
  if (!ok) return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", form_id, ".rds.")))
  list(ok = TRUE, path = local, message = NULL)
}

# Main entry point used by the downloadHandler in app.R. Always returns
# list(ok, path, message) -- never raises -- so the caller can show a
# clean error instead of a raw R error when anything goes wrong (missing
# credentials, an unreachable form, ...).
build_form_download <- function(form_id, format) {
  form_id <- as.character(form_id)

  if (!sharepoint_credentials_available())
    return(list(ok = FALSE, path = NULL, message = "SharePoint credentials are not configured."))

  token <- tryCatch(sp_get_graph_token(), error = function(e) NULL)
  if (is.null(token))
    return(list(ok = FALSE, path = NULL, message = "Could not authenticate with SharePoint."))

  drive_id <- tryCatch(sp_resolve_drive_id(token), error = function(e) NULL)
  if (is.null(drive_id))
    return(list(ok = FALSE, path = NULL, message = "Could not resolve the SharePoint document library."))

  heavy <- form_is_partitioned(token, drive_id, form_id)

  work_dir <- file.path(
    tempdir(),
    paste0("im_dl_", form_id, "_", format, "_", as.integer(Sys.time()))
  )
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)

  tryCatch({
    switch(format,
      parquet = build_parquet_download(token, drive_id, form_id, heavy, work_dir),
      csv     = build_csv_download(token, drive_id, form_id, heavy, work_dir),
      xlsx    = build_xlsx_download(token, drive_id, form_id, heavy, work_dir),
      rds     = build_rds_download(token, drive_id, form_id, heavy, work_dir),
      list(ok = FALSE, path = NULL, message = paste0("Unsupported format: ", format))
    )
  }, error = function(e) list(ok = FALSE, path = NULL, message = conditionMessage(e)))
}
