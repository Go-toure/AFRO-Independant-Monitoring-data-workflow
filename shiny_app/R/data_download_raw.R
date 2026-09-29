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

# A *practical* ceiling on top of the row limit above, for wide forms.
# Discovered on form 4498 (629 columns): its 2023 year-partition alone is
# 252,306 rows -- comfortably under RAW_DL_EXCEL_ROW_LIMIT, so the existing
# row check never caught it -- but 252,306 x 629 = ~158.7 million cells.
# That's not just slow to write (regardless of engine -- openxlsx or
# writexl -- writing that many cells took long enough in production to
# either disconnect the Shiny session or OOM-kill the whole worker), it
# also produces a file that's painfully slow, and sometimes simply unable,
# to open in Excel afterward -- i.e. even a "successful" write here isn't
# actually a usable deliverable. 5 million cells is a conservative but
# still generous ceiling: comfortably fast to write and to open, while
# only kicking in for genuinely extreme row x column combinations like
# this one. CSV and Parquet have no such practical ceiling and remain
# available for exactly this case.
RAW_DL_EXCEL_CELL_LIMIT <- 5000000

.exceeds_excel_cell_limit <- function(df) {
  (as.numeric(nrow(df)) * as.numeric(ncol(df))) > RAW_DL_EXCEL_CELL_LIMIT
}

# Row/col counts straight off a Parquet file's own footer metadata --
# WITHOUT decoding any of its actual column data. This turned out to
# matter: arrow::read_parquet(path, as_data_frame = FALSE) still fully
# reads and decompresses every column into an Arrow Table in memory --
# as_data_frame only controls whether an ADDITIONAL R data.frame
# conversion happens afterward, not how much of the file gets read. So
# checking .exceeds_excel_cell_limit() on that Table (the earlier fix)
# avoided the data.frame conversion cost, but not the much larger
# read-and-decode cost that had already happened by the time the Table
# came back -- which is exactly why form 4498 (822 columns, some years
# 400k+ rows) kept disconnecting/OOM'ing even after that fix shipped.
# ParquetFileReader's schema + row-count metadata, by contrast, comes
# from the file's footer alone and is cheap regardless of file size.
# Defensive: falls back to NULL (never raises) if this lower-level API
# isn't available for some reason -- the caller then falls through to the
# slower-but-always-correct read_parquet()-based check as a backstop, so
# this is purely a performance optimization, never a correctness one.
.parquet_dims_cheap <- function(path) {
  tryCatch({
    pf     <- arrow::ParquetFileReader$create(path)
    ncols  <- length(pf$GetSchema())
    nrows  <- pf$metadata$num_rows
    if (is.null(nrows)) nrows <- pf$num_rows
    if (is.null(nrows) || is.null(ncols) || !is.finite(nrows) || !is.finite(ncols)) stop("metadata unavailable")
    c(rows = as.numeric(nrows), cols = as.numeric(ncols))
  }, error = function(e) NULL)
}

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
#
# `progress` is an optional callback, `function(detail)`, invoked with a
# short human-readable string at each meaningful checkpoint -- every
# builder function below takes the same parameter and threads it down to
# here and to sp_download_file()'s own call sites, so the Shiny download
# button can wire it up to a live progress bar + log console (see
# app.R's downloadHandler for "dl_raw_form") without this file knowing
# anything about Shiny. Defaults to a no-op so this stays callable exactly
# as before from a script, the R console, or a test that doesn't care
# about progress reporting.
fetch_form_dataframe <- function(token, drive_id, form_id, heavy, work_dir,
                                  progress = function(detail) invisible(NULL)) {
  if (!heavy) {
    progress(paste0("Downloading ", form_id, ".parquet..."))
    remote <- paste0(RAW_STATE_FOLDER, "/", form_id, ".parquet")
    local  <- file.path(work_dir, paste0(form_id, ".parquet"))
    if (!sp_download_file(token, drive_id, remote, local)) return(NULL)
    progress(paste0("Reading ", form_id, ".parquet..."))
    return(tryCatch(as.data.frame(arrow::read_parquet(local)), error = function(e) NULL))
  }
  year_files <- .partition_year_files(token, drive_id, form_id)
  if (!length(year_files)) return(NULL)
  frames <- list()
  for (nm in year_files) {
    progress(paste0("Downloading ", nm, "..."))
    local  <- file.path(work_dir, nm)
    remote <- paste0(sp_partition_folder(form_id), "/", nm)
    if (!sp_download_file(token, drive_id, remote, local)) next
    df <- tryCatch(as.data.frame(arrow::read_parquet(local)), error = function(e) NULL)
    if (!is.null(df)) frames[[nm]] <- df
  }
  if (!length(frames)) return(NULL)
  progress(paste0("Combining ", length(frames), " year(s) of data..."))
  dplyr::bind_rows(frames)
}

# A single file above this is skipped from the zip entirely rather than
# attempted -- see the compression_level comment below for why bundling it
# is the actual risk, not just writing it.
RAW_DL_ZIP_FILE_SIZE_LIMIT <- 150 * 1024 * 1024  # 150 MB

.zip_files <- function(paths, zip_path, work_dir, progress = function(detail) invisible(NULL)) {
  # Found on form 4498's CSV path: its 2023 year-partition (629 cols x
  # 252,306 rows) is well over a GB as plain-text CSV, and zip::zip()'s
  # default compression_level (9 -- maximum DEFLATE) is CPU-heavy in a way
  # that scales badly with input size. That single call ran long enough to
  # disconnect the Shiny session / OOM-kill the worker -- the exact same
  # failure mode already fixed on the xlsx-writing side, just one step
  # later in the pipeline (zip-building instead of xlsx-writing). Two
  # mitigations, same spirit as the xlsx cell-count fix: (1) use a fast
  # compression level always, since level 9's CPU cost is what actually
  # hurts for large inputs, not compression itself; (2) as a hard backstop,
  # skip any single file over RAW_DL_ZIP_FILE_SIZE_LIMIT from the archive
  # rather than let a version of this problem happen again for an even
  # larger form/year in the future -- callers must handle a NULL return
  # (nothing left worth zipping) instead of assuming a path always comes
  # back.
  sizes <- suppressWarnings(file.size(paths))
  sizes[is.na(sizes)] <- 0
  too_big <- sizes > RAW_DL_ZIP_FILE_SIZE_LIMIT
  if (any(too_big)) {
    for (i in which(too_big)) {
      progress(paste0(
        basename(paths[i]), " is ", round(sizes[i] / 1024 / 1024), " MB -- ",
        "too large to bundle into this zip, skipping it."
      ))
    }
    paths <- paths[!too_big]
  }
  if (!length(paths)) {
    progress("Nothing left to zip after skipping oversized file(s).")
    return(NULL)
  }
  progress(paste0("Building zip archive (", length(paths), " file(s))..."))
  tryCatch(
    zip::zip(zip_path, files = basename(paths), root = work_dir, compression_level = 1),
    error = function(e) zip::zip(zip_path, files = basename(paths), root = work_dir)
  )
  zip_path
}

build_parquet_download <- function(token, drive_id, form_id, heavy, work_dir,
                                    progress = function(detail) invisible(NULL)) {
  progress(paste0("Downloading ", form_id, ".parquet..."))
  remote <- paste0(RAW_STATE_FOLDER, "/", form_id, ".parquet")
  local  <- file.path(work_dir, paste0(form_id, ".parquet"))
  if (!sp_download_file(token, drive_id, remote, local))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Could not download ", form_id, ".parquet from SharePoint.")))
  list(ok = TRUE, path = local, message = NULL)
}

build_csv_download <- function(token, drive_id, form_id, heavy, work_dir,
                                progress = function(detail) invisible(NULL)) {
  if (!heavy) {
    progress(paste0("Downloading ", form_id, ".csv..."))
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
  progress("Listing year-partitioned CSV files...")
  items      <- sp_list_folder(token, drive_id, RAW_STATE_FOLDER)
  names      <- vapply(items, .sp_item_name, character(1))
  year_files <- sort(names[grepl(paste0("^", form_id, "_[0-9]{4}\\.csv$"), names)])
  if (!length(year_files))
    return(list(ok = FALSE, path = NULL,
                message = paste0("No year-partitioned CSVs found for form ", form_id, ".")))
  paths <- character(0)
  for (nm in year_files) {
    progress(paste0("Downloading ", nm, "..."))
    local <- file.path(work_dir, nm)
    if (sp_download_file(token, drive_id, paste0(RAW_STATE_FOLDER, "/", nm), local))
      paths <- c(paths, local)
  }
  if (!length(paths))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Failed to download any year-partitioned CSV for form ", form_id, ".")))
  zip_path <- .zip_files(paths, file.path(work_dir, paste0(form_id, "_csv_by_year.zip")), work_dir, progress)
  if (is.null(zip_path))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Every year-partitioned CSV for form ", form_id,
                                  " was too large to bundle into a zip.")))
  list(ok = TRUE, path = zip_path, message = NULL)
}

# openxlsx builds the whole worksheet as an in-memory R structure before
# writing it out, which is both slow and memory-heavy for a wide,
# many-row sheet -- form 4498 in particular (629 columns) is exactly the
# form that needed this same kind of engine swap on the Python side of
# this project (scripts/fetch_sharepoint_csvs.py's _write_xlsx_year_partitions(),
# benchmarked there at openpyxl's ~212 rows/sec vs. xlsxwriter's ~344
# rows/sec). A single write.xlsx() call blocking for minutes on one of
# form 4498's larger year partitions (a quarter-million rows is well
# under Excel's row limit, but still slow to WRITE at that width) doesn't
# just look slow here -- since it's happening inside a downloadHandler's
# content(), which runs as one long synchronous call, R can't process
# anything else meanwhile either, including the websocket heartbeat that
# keeps the browser convinced the Shiny session is still alive. Long
# enough, and the browser disconnects mid-download with no real error at
# all, exactly the "eternity" symptom that write got fixed for already.
# `writexl` wraps the same fast C library (libxlsxwriter) the Python side
# now uses, so it gets the same speed-up here -- falling back to openxlsx
# only if writexl isn't installed or itself fails for some reason.
.write_xlsx_or_na <- function(df, path, progress = function(detail) invisible(NULL)) {
  if (requireNamespace("writexl", quietly = TRUE)) {
    ok <- tryCatch({ writexl::write_xlsx(df, path); TRUE },
                   error = function(e) {
                     message("[download] writexl xlsx write failed for ", path, ": ", conditionMessage(e))
                     FALSE
                   })
    if (ok) return(TRUE)
    progress("writexl failed -- falling back to the slower openxlsx engine...")
  }
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
build_xlsx_year_partitions_from_df <- function(df, form_id, work_dir,
                                                progress = function(detail) invisible(NULL)) {
  if (!"_submission_time" %in% names(df))
    return(list(ok = FALSE, path = NULL,
                message = paste0(
                  nrow(df), " rows exceeds Excel's per-sheet row limit and there is no ",
                  "_submission_time column to split by year -- try CSV, Parquet, or RDS instead."
                )))
  years <- substr(as.character(df[["_submission_time"]]), 1, 4)
  years[is.na(years) | !grepl("^[0-9]{4}$", years)] <- "0000"
  xlsx_paths <- character(0)
  skipped_years <- character(0)
  for (yr in sort(unique(years))) {
    sub_df <- df[years == yr, , drop = FALSE]
    if (.exceeds_excel_cell_limit(sub_df)) {
      progress(paste0(
        form_id, "_", yr, ": ", nrow(sub_df), " rows x ", ncol(sub_df), " cols (",
        format(nrow(sub_df) * ncol(sub_df), big.mark = ","),
        " cells) is too large for one Excel sheet -- skipping this year for .xlsx."
      ))
      skipped_years <- c(skipped_years, yr)
      next
    }
    progress(paste0("Writing ", form_id, "_", yr, ".xlsx (", nrow(sub_df), " rows)..."))
    xlsx_local <- file.path(work_dir, paste0(form_id, "_", yr, ".xlsx"))
    if (.write_xlsx_or_na(sub_df, xlsx_local, progress)) xlsx_paths <- c(xlsx_paths, xlsx_local)
  }
  if (!length(xlsx_paths))
    return(list(ok = FALSE, path = NULL,
                message = paste0(
                  "Could not build any yearly .xlsx for form ", form_id, ".",
                  if (length(skipped_years))
                    paste0(" Year(s) ", paste(skipped_years, collapse = ", "),
                           " were too large for Excel -- try CSV or Parquet instead.")
                  else ""
                )))
  zip_path <- .zip_files(xlsx_paths, file.path(work_dir, paste0(form_id, "_xlsx_by_year.zip")), work_dir, progress)
  if (is.null(zip_path))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Every yearly .xlsx for form ", form_id,
                                  " was too large to bundle into a zip.")))
  list(ok = TRUE, path = zip_path, message = NULL)
}

build_xlsx_download <- function(token, drive_id, form_id, heavy, work_dir,
                                 progress = function(detail) invisible(NULL)) {
  if (!heavy) {
    df <- fetch_form_dataframe(token, drive_id, form_id, FALSE, work_dir, progress)
    if (is.null(df))
      return(list(ok = FALSE, path = NULL, message = paste0("Could not read data for form ", form_id, ".")))
    if (nrow(df) > RAW_DL_EXCEL_ROW_LIMIT || .exceeds_excel_cell_limit(df)) {
      progress(paste0(
        nrow(df), " rows x ", ncol(df), " cols exceeds Excel's practical limit -- ",
        "splitting by year instead..."
      ))
      return(build_xlsx_year_partitions_from_df(df, form_id, work_dir, progress))
    }
    progress(paste0("Writing ", form_id, ".xlsx (", nrow(df), " rows)..."))
    local <- file.path(work_dir, paste0(form_id, ".xlsx"))
    if (!.write_xlsx_or_na(df, local, progress))
      return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", form_id, ".xlsx.")))
    return(list(ok = TRUE, path = local, message = NULL))
  }
  # Heavy form: one .xlsx per year, straight from the same year-partition
  # Parquet files the pipeline itself already maintains -- each year's
  # slice is comfortably under Excel's row limit for the same reason
  # Fetch_im_data.py's own CSV year-partitioning relies on (new submissions
  # almost always land in the current year, so no single year has ever
  # approached the form's overall total).
  progress("Listing year partitions...")
  year_files <- .partition_year_files(token, drive_id, form_id)
  if (!length(year_files))
    return(list(ok = FALSE, path = NULL, message = paste0("No year partitions found for form ", form_id, ".")))
  xlsx_paths <- character(0)
  skipped_years <- character(0)
  for (nm in year_files) {
    progress(paste0("Downloading ", nm, "..."))
    local_pq <- file.path(work_dir, nm)
    remote   <- paste0(sp_partition_folder(form_id), "/", nm)
    if (!sp_download_file(token, drive_id, remote, local_pq)) next
    year <- sub(paste0("^", form_id, "_([0-9]{4})\\.parquet$"), "\\1", nm)
    # Cheapest possible check first: read row/col counts off the Parquet
    # file's own footer metadata, never decoding any actual column data
    # (see .parquet_dims_cheap()'s own comment for why this matters --
    # read_parquet(as_data_frame = FALSE) alone is NOT cheap). Skips an
    # oversized year before the network/CPU cost of a full read at all.
    cheap_dims <- .parquet_dims_cheap(local_pq)
    if (!is.null(cheap_dims) && (cheap_dims["rows"] * cheap_dims["cols"]) > RAW_DL_EXCEL_CELL_LIMIT) {
      progress(paste0(
        form_id, "_", year, ": ", cheap_dims["rows"], " rows x ", cheap_dims["cols"], " cols (",
        format(cheap_dims["rows"] * cheap_dims["cols"], big.mark = ","),
        " cells) is too large for one Excel sheet -- skipping this year for .xlsx."
      ))
      skipped_years <- c(skipped_years, year)
      next
    }
    # Backstop for when the cheap metadata-only check above wasn't
    # available (older/different arrow build, or any error) -- still
    # correct, just pays the full read cost this one time instead of
    # skipping it outright.
    tbl <- tryCatch(arrow::read_parquet(local_pq, as_data_frame = FALSE), error = function(e) NULL)
    if (is.null(tbl)) next
    if (.exceeds_excel_cell_limit(tbl)) {
      progress(paste0(
        form_id, "_", year, ": ", nrow(tbl), " rows x ", ncol(tbl), " cols (",
        format(as.numeric(nrow(tbl)) * ncol(tbl), big.mark = ","),
        " cells) is too large for one Excel sheet -- skipping this year for .xlsx."
      ))
      skipped_years <- c(skipped_years, year)
      next
    }
    df <- tryCatch(as.data.frame(tbl), error = function(e) NULL)
    if (is.null(df)) next
    progress(paste0("Writing ", form_id, "_", year, ".xlsx (", nrow(df), " rows)..."))
    xlsx_local <- file.path(work_dir, paste0(form_id, "_", year, ".xlsx"))
    if (.write_xlsx_or_na(df, xlsx_local, progress)) xlsx_paths <- c(xlsx_paths, xlsx_local)
  }
  if (!length(xlsx_paths))
    return(list(ok = FALSE, path = NULL,
                message = paste0(
                  "Could not build any yearly .xlsx for form ", form_id, ".",
                  if (length(skipped_years))
                    paste0(" Year(s) ", paste(skipped_years, collapse = ", "),
                           " were too large for Excel -- try CSV or Parquet instead.")
                  else ""
                )))
  if (length(skipped_years))
    progress(paste0(
      "Note: year(s) ", paste(skipped_years, collapse = ", "),
      " were too large for Excel and are not included in this zip -- ",
      "use CSV or Parquet to get the full data for those years."
    ))
  zip_path <- .zip_files(xlsx_paths, file.path(work_dir, paste0(form_id, "_xlsx_by_year.zip")), work_dir, progress)
  if (is.null(zip_path))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Every yearly .xlsx for form ", form_id,
                                  " was too large to bundle into a zip.")))
  list(ok = TRUE, path = zip_path, message = NULL)
}

build_rds_download <- function(token, drive_id, form_id, heavy, work_dir,
                                progress = function(detail) invisible(NULL)) {
  df <- fetch_form_dataframe(token, drive_id, form_id, heavy, work_dir, progress)
  if (is.null(df))
    return(list(ok = FALSE, path = NULL, message = paste0("Could not read data for form ", form_id, ".")))
  progress(paste0("Writing ", form_id, ".rds (", nrow(df), " rows)..."))
  local <- file.path(work_dir, paste0(form_id, ".rds"))
  ok <- tryCatch({ saveRDS(df, local); TRUE }, error = function(e) FALSE)
  if (!ok) return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", form_id, ".rds.")))
  list(ok = TRUE, path = local, message = NULL)
}

# Main entry point used by the downloadHandler in app.R. Always returns
# list(ok, path, message) -- never raises -- so the caller can show a
# clean error instead of a raw R error when anything goes wrong (missing
# credentials, an unreachable form, ...).
#
# `progress`: optional `function(detail)` called with a short status
# string at each checkpoint (see the header comment on fetch_form_dataframe()
# above) -- app.R's downloadHandler passes one in that drives both a
# shiny::withProgress() bar and a live log console, so a slow heavy-form
# download (several SharePoint round-trips plus zipping) doesn't just sit
# there looking hung the way the year-partitioned xlsx export in
# scripts/fetch_sharepoint_csvs.py used to before it got the same
# treatment earlier this project.
build_form_download <- function(form_id, format, progress = function(detail) invisible(NULL)) {
  form_id <- as.character(form_id)

  if (!sharepoint_credentials_available())
    return(list(ok = FALSE, path = NULL, message = "SharePoint credentials are not configured."))

  progress("Authenticating with SharePoint...")
  token <- tryCatch(sp_get_graph_token(), error = function(e) NULL)
  if (is.null(token))
    return(list(ok = FALSE, path = NULL, message = "Could not authenticate with SharePoint."))

  progress("Resolving document library...")
  drive_id <- tryCatch(sp_resolve_drive_id(token), error = function(e) NULL)
  if (is.null(drive_id))
    return(list(ok = FALSE, path = NULL, message = "Could not resolve the SharePoint document library."))

  progress(paste0("Checking whether form ", form_id, " is year-partitioned..."))
  heavy <- form_is_partitioned(token, drive_id, form_id)

  work_dir <- file.path(
    tempdir(),
    paste0("im_dl_", form_id, "_", format, "_", as.integer(Sys.time()))
  )
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)

  result <- tryCatch({
    switch(format,
      parquet = build_parquet_download(token, drive_id, form_id, heavy, work_dir, progress),
      csv     = build_csv_download(token, drive_id, form_id, heavy, work_dir, progress),
      xlsx    = build_xlsx_download(token, drive_id, form_id, heavy, work_dir, progress),
      rds     = build_rds_download(token, drive_id, form_id, heavy, work_dir, progress),
      list(ok = FALSE, path = NULL, message = paste0("Unsupported format: ", format))
    )
  }, error = function(e) list(ok = FALSE, path = NULL, message = conditionMessage(e)))

  progress(if (isTRUE(result$ok)) "Done." else paste0("Failed: ", result$message))
  result
}
