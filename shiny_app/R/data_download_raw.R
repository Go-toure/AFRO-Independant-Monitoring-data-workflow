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

# Character vector of year strings (e.g. c("2020","2021",...)) this form is
# partitioned into, ascending -- or character(0) if the form isn't
# partitioned (not "heavy"), SharePoint credentials aren't configured, or
# anything else goes wrong. Never raises. Used to populate the "Year"
# dropdown in the Download Raw Form Data UI reactively as soon as a form is
# picked, so the selector only ever offers years that genuinely exist for
# that form -- a non-heavy form (nothing to partition) naturally gets back
# character(0), which the UI treats as "no year selector, only one file".
list_partition_years <- function(form_id) {
  if (!sharepoint_credentials_available()) return(character(0))
  tryCatch({
    token    <- sp_get_graph_token()
    drive_id <- sp_resolve_drive_id(token)
    files    <- .partition_year_files(token, drive_id, form_id)
    sub(paste0("^", form_id, "_([0-9]{4})\\.parquet$"), "\\1", files)
  }, error = function(e) character(0))
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

# A genuine last-resort backstop only -- NOT a routine limit. A form like
# 4498 legitimately has multiple-hundred-MB to low-GB CSVs per year, and
# excluding those from the zip defeats the entire point of the download
# (a user reported exactly this: a "successful" zip that silently dropped
# 4 of 7 years is worse than useless -- it looks complete but isn't). This
# only exists to stop something truly pathological (a corrupt/runaway
# file, or a future form even larger than anything seen so far) from
# taking the whole zip down; it should essentially never trigger for a
# normal, if large, export.
RAW_DL_ZIP_FILE_SIZE_LIMIT <- 3 * 1024 * 1024 * 1024  # 3 GB

.zip_files <- function(paths, zip_path, work_dir, progress = function(detail) invisible(NULL)) {
  # Found on form 4498's CSV path: its year-partitions run several hundred
  # MB to over a GB each as plain-text CSV, and zip::zip()'s default
  # compression_level (9 -- maximum DEFLATE) is CPU-heavy in a way that
  # scales badly with input size -- that single call ran long enough to
  # disconnect the Shiny session / OOM-kill the worker. The fix that
  # actually matters for data completeness is using compression_level = 0
  # (store -- no compression, just packaging) instead of any DEFLATE
  # level: it's the fastest possible option, at the cost of a larger zip,
  # which is the right trade for "give me all the data" over "make the
  # download small." An earlier version of this function also tried a
  # size-based exclusion at a much lower threshold as a second safety net
  # -- that turned out to be actively harmful here, since it silently
  # dropped the very years the download exists to deliver. It's kept now
  # only as RAW_DL_ZIP_FILE_SIZE_LIMIT, a much higher genuine backstop
  # (see its own comment) -- callers must still handle a NULL return
  # (nothing left worth zipping) for that truly-extreme case.
  sizes <- suppressWarnings(file.size(paths))
  sizes[is.na(sizes)] <- 0
  too_big <- sizes > RAW_DL_ZIP_FILE_SIZE_LIMIT
  if (any(too_big)) {
    for (i in which(too_big)) {
      progress(paste0(
        basename(paths[i]), " is ", round(sizes[i] / 1024 / 1024), " MB -- ",
        "too large to include even with store-only zipping, skipping it."
      ))
    }
    paths <- paths[!too_big]
  }
  if (!length(paths)) {
    progress("Nothing left to zip after skipping oversized file(s).")
    return(NULL)
  }
  progress(paste0("Building zip archive (", length(paths), " file(s), store-only for speed)..."))
  tryCatch(
    zip::zip(zip_path, files = basename(paths), root = work_dir, compression_level = 0),
    error = function(e) zip::zip(zip_path, files = basename(paths), root = work_dir)
  )
  zip_path
}

# Filters a combined data.frame down to just the rows whose _submission_time
# falls in the requested calendar year -- this is what lets a NON-heavy form
# (nothing pre-partitioned by year on SharePoint, unlike a "heavy" form) still
# serve a single-year download: read the one combined file it already has,
# then slice it down to just that year in memory, rather than needing a real
# per-year file to exist up front. Used by every build_*_download()'s new
# `year`-set-but-`!heavy` branch below.
#
# Returns:
#   NULL         -> this form has no _submission_time column at all, so there
#                    is nothing to filter by year (distinguished from the next
#                    case so callers can give a clear, different message for
#                    each -- "can't filter this form" vs. "filtered correctly,
#                    but nothing matched").
#   a data.frame -> possibly zero-row, when _submission_time exists but no row
#                    actually falls in the requested year.
.filter_df_by_year <- function(df, year) {
  if (!"_submission_time" %in% names(df)) return(NULL)
  years <- substr(as.character(df[["_submission_time"]]), 1, 4)
  df[!is.na(years) & years == as.character(year), , drop = FALSE]
}

# Case-insensitive column lookup: returns the actual column name in df that
# matches any of `candidates` (tried in order), or NULL if none do. Needed
# because raw ONA/Kobo exports aren't guaranteed to use one exact casing for
# a given field across every form -- the cleaned/processed dataset elsewhere
# in this app uses lowercase "response"/"roundnumber" (see app.R's Overview
# and Explorer tabs), while a raw export's own question names more often
# follow the form's XLSForm casing (e.g. "Response", "roundNumber") -- so
# every candidate spelling actually seen in this codebase is tried.
.find_column_ci <- function(df, candidates) {
  nm <- names(df)
  for (cand in candidates) {
    hit <- nm[tolower(nm) == tolower(cand)]
    if (length(hit)) return(hit[1])
  }
  NULL
}

# Filters df down to rows whose value in whichever column matches
# `candidates` (case-insensitively) equals `value` (also compared
# case-insensitively, after trimming whitespace on both sides) -- the Response
# and roundNumber filters both go through this one generic implementation.
# NULL means "this form has no such column at all" (vs. a zero-row
# data.frame, which means the column exists but nothing matched `value`).
.filter_df_by_field <- function(df, candidates, value) {
  col <- .find_column_ci(df, candidates)
  if (is.null(col)) return(NULL)
  vals   <- trimws(as.character(df[[col]]))
  target <- tolower(trimws(as.character(value)))
  df[!is.na(vals) & tolower(vals) == target, , drop = FALSE]
}

# Applies whichever of (year, response, round_number) are non-NULL to df, in
# sequence, each with its own clear failure message when the column it needs
# doesn't exist on this form, or when it exists but nothing matches. Used by
# every build_*_download()'s "something needs to be read and filtered"
# branch -- i.e. whenever a non-heavy form has ANY filter set, or ANY form
# has Response/roundNumber set (year alone on a heavy form instead uses a
# cheaper direct per-year-file fast path that never needs this, since the
# pipeline already keeps that exact slice as its own file -- see
# .load_base_df_for_filtering()).
#
# Returns list(df = <filtered data.frame>, error = NULL) on success, or
# list(df = NULL, error = <message>) on failure -- callers only need to check
# `error`.
.apply_raw_filters <- function(df, form_id, year = NULL, response = NULL, round_number = NULL) {
  if (!is.null(year)) {
    sub <- .filter_df_by_year(df, year)
    if (is.null(sub))
      return(list(df = NULL, error = paste0(
        "Form ", form_id, " has no _submission_time column to filter by year.")))
    df <- sub
    if (!nrow(df))
      return(list(df = NULL, error = paste0("No data found for form ", form_id, ", year ", year, ".")))
  }
  if (!is.null(response)) {
    sub <- .filter_df_by_field(df, c("Response", "response"), response)
    if (is.null(sub))
      return(list(df = NULL, error = paste0("Form ", form_id, " has no Response column to filter by.")))
    df <- sub
    if (!nrow(df))
      return(list(df = NULL, error = paste0(
        "No data found for form ", form_id, " with Response = \"", response, "\"",
        if (!is.null(year)) paste0(" (year ", year, ")") else "", ".")))
  }
  if (!is.null(round_number)) {
    sub <- .filter_df_by_field(df, c("roundNumber", "roundnumber", "round_number", "Round Number", "RoundNumber"), round_number)
    if (is.null(sub))
      return(list(df = NULL, error = paste0("Form ", form_id, " has no roundNumber column to filter by.")))
    df <- sub
    if (!nrow(df))
      return(list(df = NULL, error = paste0(
        "No data found for form ", form_id, " with roundNumber = \"", round_number, "\".")))
  }
  list(df = df, error = NULL)
}

# Loads whatever base data a filtered download should start from: a heavy
# form's own single year-partition file when a year was given (so later
# filters only ever look at that one year's data -- cheaper, and avoids
# downloading/combining every other year for nothing), or the full dataset
# otherwise (every year combined for a heavy form, or the one combined file
# for a non-heavy form, both via fetch_form_dataframe()).
.load_base_df_for_filtering <- function(token, drive_id, form_id, heavy, year, work_dir, progress) {
  if (!is.null(year) && heavy) {
    nm     <- paste0(form_id, "_", year, ".parquet")
    remote <- paste0(sp_partition_folder(form_id), "/", nm)
    local  <- file.path(work_dir, nm)
    progress(paste0("Downloading ", nm, "..."))
    if (!sp_download_file(token, drive_id, remote, local))
      return(list(df = NULL, message = paste0("No data found for form ", form_id, ", year ", year, ".")))
    df <- tryCatch(as.data.frame(arrow::read_parquet(local)), error = function(e) NULL)
    if (is.null(df)) return(list(df = NULL, message = paste0("Could not read ", nm, ".")))
    return(list(df = df, message = NULL))
  }
  df <- fetch_form_dataframe(token, drive_id, form_id, heavy, work_dir, progress)
  if (is.null(df))
    return(list(df = NULL, message = paste0("Could not read data for form ", form_id, ".")))
  list(df = df, message = NULL)
}

# A safe filename stem reflecting whichever of (year, response, round_number)
# were actually requested, e.g. "4498_2024_Yes_r3" -- used for the single
# filtered output file whenever any filter needed the data read/sliced
# in-memory rather than handed back as one of the pipeline's own
# already-partitioned files verbatim.
.filtered_file_stem <- function(form_id, year = NULL, response = NULL, round_number = NULL) {
  clean <- function(x) gsub("[^A-Za-z0-9]+", "", as.character(x))
  parts <- c(as.character(form_id))
  if (!is.null(year))         parts <- c(parts, clean(year))
  if (!is.null(response))     parts <- c(parts, clean(response))
  if (!is.null(round_number)) parts <- c(parts, paste0("r", clean(round_number)))
  paste(parts, collapse = "_")
}

build_parquet_download <- function(token, drive_id, form_id, heavy, work_dir,
                                    progress = function(detail) invisible(NULL),
                                    year = NULL, response = NULL, round_number = NULL) {
  any_extra <- !is.null(response) || !is.null(round_number)

  # Fast path: a specific year on a heavy (year-partitioned) form, with no
  # other filter set -- the pipeline already keeps that year's own Parquet
  # partition file, so this just fetches it directly with no read/rewrite at
  # all. Falls through for a non-heavy form even if a year was passed
  # (nothing to partition there -- see list_partition_years()'s own comment),
  # and falls through whenever Response/roundNumber are also requested, since
  # those need the data actually read in before they can be checked.
  if (!is.null(year) && heavy && !any_extra) {
    nm     <- paste0(form_id, "_", year, ".parquet")
    remote <- paste0(sp_partition_folder(form_id), "/", nm)
    local  <- file.path(work_dir, nm)
    progress(paste0("Downloading ", nm, "..."))
    if (!sp_download_file(token, drive_id, remote, local))
      return(list(ok = FALSE, path = NULL,
                  message = paste0("No data found for form ", form_id, ", year ", year, ".")))
    return(list(ok = TRUE, path = local, message = NULL))
  }

  # Any filter at all that the fast path above couldn't handle: load the
  # narrowest base data available (just this year's partition when heavy,
  # otherwise everything), apply whichever of year/response/round_number
  # were asked for, and write out a single filtered Parquet.
  if (!is.null(year) || any_extra) {
    base <- .load_base_df_for_filtering(token, drive_id, form_id, heavy, year, work_dir, progress)
    if (is.null(base$df)) return(list(ok = FALSE, path = NULL, message = base$message))
    # year is already baked into base$df when heavy (see
    # .load_base_df_for_filtering) -- re-applying it there is harmless
    # (every row already matches) but unnecessary, so skip it in that case.
    year_to_apply <- if (!is.null(year) && heavy) NULL else year
    filt <- .apply_raw_filters(base$df, form_id, year = year_to_apply, response = response, round_number = round_number)
    if (is.null(filt$df)) return(list(ok = FALSE, path = NULL, message = filt$error))
    stem <- .filtered_file_stem(form_id, year, response, round_number)
    progress(paste0("Writing ", stem, ".parquet (", nrow(filt$df), " rows)..."))
    out <- file.path(work_dir, paste0(stem, ".parquet"))
    ok <- tryCatch({ arrow::write_parquet(filt$df, out); TRUE }, error = function(e) FALSE)
    if (!ok)
      return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", stem, ".parquet.")))
    return(list(ok = TRUE, path = out, message = NULL))
  }

  # No filters at all -- the original combined-file path, unchanged.
  progress(paste0("Downloading ", form_id, ".parquet..."))
  remote <- paste0(RAW_STATE_FOLDER, "/", form_id, ".parquet")
  local  <- file.path(work_dir, paste0(form_id, ".parquet"))
  if (!sp_download_file(token, drive_id, remote, local))
    return(list(ok = FALSE, path = NULL,
                message = paste0("Could not download ", form_id, ".parquet from SharePoint.")))
  list(ok = TRUE, path = local, message = NULL)
}

build_csv_download <- function(token, drive_id, form_id, heavy, work_dir,
                                progress = function(detail) invisible(NULL),
                                year = NULL, response = NULL, round_number = NULL) {
  any_extra <- !is.null(response) || !is.null(round_number)

  # Fast path: a specific year on a heavy form, no other filter -- fetch just
  # that year's own CSV directly, returned as a plain .csv (not a zip), since
  # there's only ever one file involved. No need to list/download every other
  # year. Falls through whenever Response/roundNumber are also requested.
  if (!is.null(year) && heavy && !any_extra) {
    nm     <- paste0(form_id, "_", year, ".csv")
    remote <- paste0(RAW_STATE_FOLDER, "/", nm)
    local  <- file.path(work_dir, nm)
    progress(paste0("Downloading ", nm, "..."))
    if (!sp_download_file(token, drive_id, remote, local))
      return(list(ok = FALSE, path = NULL,
                  message = paste0("No CSV found for form ", form_id, ", year ", year, ".")))
    return(list(ok = TRUE, path = local, message = NULL))
  }

  # Any filter the fast path above couldn't handle: load the narrowest base
  # data available via the same Parquet-backed helper the other formats use
  # (reading from Parquet rather than CSV here avoids any risk of column-name
  # mangling on fields like "_submission_time"), filter, write a single CSV.
  if (!is.null(year) || any_extra) {
    base <- .load_base_df_for_filtering(token, drive_id, form_id, heavy, year, work_dir, progress)
    if (is.null(base$df)) return(list(ok = FALSE, path = NULL, message = base$message))
    year_to_apply <- if (!is.null(year) && heavy) NULL else year
    filt <- .apply_raw_filters(base$df, form_id, year = year_to_apply, response = response, round_number = round_number)
    if (is.null(filt$df)) return(list(ok = FALSE, path = NULL, message = filt$error))
    stem <- .filtered_file_stem(form_id, year, response, round_number)
    progress(paste0("Writing ", stem, ".csv (", nrow(filt$df), " rows)..."))
    out <- file.path(work_dir, paste0(stem, ".csv"))
    ok <- tryCatch({ readr::write_csv(filt$df, out); TRUE }, error = function(e) FALSE)
    if (!ok)
      return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", stem, ".csv.")))
    return(list(ok = TRUE, path = out, message = NULL))
  }

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

# Builds one year-partition's .xlsx straight from its own Parquet file,
# using the same cheap-metadata-first cell-limit check as the all-years
# loop below -- pulled out into its own function so the single-year
# fast path (a user picking one specific, possibly heavy, year) and the
# all-years loop share exactly one implementation instead of two copies
# that could quietly drift apart.
#
# Returns list(ok, path, skipped, message):
#   ok=TRUE                -> path is the written .xlsx, message is NULL.
#   ok=FALSE, skipped=TRUE -> this year genuinely doesn't fit in one Excel
#                             sheet; message explains why (not a hard error).
#   ok=FALSE, skipped=FALSE -> an actual download/read/write failure.
.build_one_year_xlsx <- function(token, drive_id, form_id, year, work_dir,
                                  progress = function(detail) invisible(NULL)) {
  nm       <- paste0(form_id, "_", year, ".parquet")
  local_pq <- file.path(work_dir, nm)
  remote   <- paste0(sp_partition_folder(form_id), "/", nm)
  progress(paste0("Downloading ", nm, "..."))
  if (!sp_download_file(token, drive_id, remote, local_pq))
    return(list(ok = FALSE, path = NULL, skipped = FALSE,
                message = paste0("Could not download ", nm, " from SharePoint.")))

  # Cheapest possible check first: read row/col counts off the Parquet
  # file's own footer metadata, never decoding any actual column data (see
  # .parquet_dims_cheap()'s own comment for why this matters --
  # read_parquet(as_data_frame = FALSE) alone is NOT cheap). Skips an
  # oversized year before the network/CPU cost of a full read at all.
  cheap_dims <- .parquet_dims_cheap(local_pq)
  if (!is.null(cheap_dims) && (cheap_dims["rows"] * cheap_dims["cols"]) > RAW_DL_EXCEL_CELL_LIMIT) {
    msg <- paste0(
      form_id, "_", year, ": ", cheap_dims["rows"], " rows x ", cheap_dims["cols"], " cols (",
      format(cheap_dims["rows"] * cheap_dims["cols"], big.mark = ","),
      " cells) is too large for one Excel sheet")
    progress(paste0(msg, " -- skipping this year for .xlsx."))
    return(list(ok = FALSE, path = NULL, skipped = TRUE, message = paste0(msg, ".")))
  }

  # Backstop for when the cheap metadata-only check above wasn't available
  # (older/different arrow build, or any error) -- still correct, just pays
  # the full read cost this one time instead of skipping it outright.
  tbl <- tryCatch(arrow::read_parquet(local_pq, as_data_frame = FALSE), error = function(e) NULL)
  if (is.null(tbl))
    return(list(ok = FALSE, path = NULL, skipped = FALSE, message = paste0("Could not read ", nm, ".")))
  if (.exceeds_excel_cell_limit(tbl)) {
    msg <- paste0(
      form_id, "_", year, ": ", nrow(tbl), " rows x ", ncol(tbl), " cols (",
      format(as.numeric(nrow(tbl)) * ncol(tbl), big.mark = ","),
      " cells) is too large for one Excel sheet")
    progress(paste0(msg, " -- skipping this year for .xlsx."))
    return(list(ok = FALSE, path = NULL, skipped = TRUE, message = paste0(msg, ".")))
  }

  df <- tryCatch(as.data.frame(tbl), error = function(e) NULL)
  if (is.null(df))
    return(list(ok = FALSE, path = NULL, skipped = FALSE, message = paste0("Could not read ", nm, ".")))
  progress(paste0("Writing ", form_id, "_", year, ".xlsx (", nrow(df), " rows)..."))
  xlsx_local <- file.path(work_dir, paste0(form_id, "_", year, ".xlsx"))
  if (!.write_xlsx_or_na(df, xlsx_local, progress))
    return(list(ok = FALSE, path = NULL, skipped = FALSE,
                message = paste0("Could not write ", form_id, "_", year, ".xlsx.")))
  list(ok = TRUE, path = xlsx_local, skipped = FALSE, message = NULL)
}

build_xlsx_download <- function(token, drive_id, form_id, heavy, work_dir,
                                 progress = function(detail) invisible(NULL),
                                 year = NULL, response = NULL, round_number = NULL) {
  any_extra <- !is.null(response) || !is.null(round_number)

  # Fast path: a specific year requested on a heavy form, no other filter --
  # build just that one year's .xlsx and return it directly (no zip -- only
  # ever one file). If that particular year is itself too large for Excel,
  # this fails with a clear message naming CSV/Parquet as the alternative for
  # THIS year, rather than the all-years "note" below (there's nothing else
  # in this download to fall back on, unlike the all-years case). Falls
  # through whenever Response/roundNumber are also requested, since those
  # need the data actually read in before they can be checked.
  if (!is.null(year) && heavy && !any_extra) {
    r <- .build_one_year_xlsx(token, drive_id, form_id, year, work_dir, progress)
    if (isTRUE(r$ok)) return(list(ok = TRUE, path = r$path, message = NULL))
    if (isTRUE(r$skipped))
      return(list(ok = FALSE, path = NULL,
                  message = paste0(r$message, " Try CSV or Parquet for this year instead.")))
    return(list(ok = FALSE, path = NULL, message = r$message))
  }

  # Any filter the fast path above couldn't handle (a year on a non-heavy
  # form, or Response/roundNumber on any form): load the narrowest base data
  # available, filter, and THEN check Excel's row/cell limits -- a single
  # year or Response/round slice could still in principle be too large for
  # one sheet on a wide form, so this still needs the same check the
  # all-years loop below uses, just against the already-filtered data.
  if (!is.null(year) || any_extra) {
    base <- .load_base_df_for_filtering(token, drive_id, form_id, heavy, year, work_dir, progress)
    if (is.null(base$df)) return(list(ok = FALSE, path = NULL, message = base$message))
    year_to_apply <- if (!is.null(year) && heavy) NULL else year
    filt <- .apply_raw_filters(base$df, form_id, year = year_to_apply, response = response, round_number = round_number)
    if (is.null(filt$df)) return(list(ok = FALSE, path = NULL, message = filt$error))
    df   <- filt$df
    stem <- .filtered_file_stem(form_id, year, response, round_number)
    if (nrow(df) > RAW_DL_EXCEL_ROW_LIMIT || .exceeds_excel_cell_limit(df))
      return(list(ok = FALSE, path = NULL,
                  message = paste0(
                    stem, ": ", nrow(df), " rows x ", ncol(df), " cols (",
                    format(as.numeric(nrow(df)) * ncol(df), big.mark = ","),
                    " cells) is too large for one Excel sheet. Try CSV or Parquet for this selection instead.")))
    progress(paste0("Writing ", stem, ".xlsx (", nrow(df), " rows)..."))
    out <- file.path(work_dir, paste0(stem, ".xlsx"))
    if (!.write_xlsx_or_na(df, out, progress))
      return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", stem, ".xlsx.")))
    return(list(ok = TRUE, path = out, message = NULL))
  }

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
  # Heavy form, no specific year: one .xlsx per year, straight from the
  # same year-partition Parquet files the pipeline itself already
  # maintains -- each year's slice is comfortably under Excel's row limit
  # for the same reason Fetch_im_data.py's own CSV year-partitioning
  # relies on (new submissions almost always land in the current year, so
  # no single year has ever approached the form's overall total).
  progress("Listing year partitions...")
  year_files <- .partition_year_files(token, drive_id, form_id)
  if (!length(year_files))
    return(list(ok = FALSE, path = NULL, message = paste0("No year partitions found for form ", form_id, ".")))
  xlsx_paths <- character(0)
  skipped_years <- character(0)
  for (nm in year_files) {
    yr <- sub(paste0("^", form_id, "_([0-9]{4})\\.parquet$"), "\\1", nm)
    r  <- .build_one_year_xlsx(token, drive_id, form_id, yr, work_dir, progress)
    if (isTRUE(r$ok)) {
      xlsx_paths <- c(xlsx_paths, r$path)
    } else if (isTRUE(r$skipped)) {
      skipped_years <- c(skipped_years, yr)
    }
    # else: a real download/read/write failure for this year -- move on to
    # the next one, same as the original loop's plain `next` on failure.
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
                                progress = function(detail) invisible(NULL),
                                year = NULL, response = NULL, round_number = NULL) {
  any_extra <- !is.null(response) || !is.null(round_number)

  # Fast path: a specific year on a heavy form, no other filter -- read just
  # that one year's own partition and save it directly, skipping
  # fetch_form_dataframe()'s download-every-year-then-bind_rows() path
  # entirely. Falls through whenever Response/roundNumber are also requested.
  if (!is.null(year) && heavy && !any_extra) {
    nm     <- paste0(form_id, "_", year, ".parquet")
    remote <- paste0(sp_partition_folder(form_id), "/", nm)
    local_pq <- file.path(work_dir, nm)
    progress(paste0("Downloading ", nm, "..."))
    if (!sp_download_file(token, drive_id, remote, local_pq))
      return(list(ok = FALSE, path = NULL,
                  message = paste0("No data found for form ", form_id, ", year ", year, ".")))
    df <- tryCatch(as.data.frame(arrow::read_parquet(local_pq)), error = function(e) NULL)
    if (is.null(df))
      return(list(ok = FALSE, path = NULL, message = paste0("Could not read ", nm, ".")))
    progress(paste0("Writing ", form_id, "_", year, ".rds (", nrow(df), " rows)..."))
    out <- file.path(work_dir, paste0(form_id, "_", year, ".rds"))
    ok <- tryCatch({ saveRDS(df, out); TRUE }, error = function(e) FALSE)
    if (!ok)
      return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", form_id, "_", year, ".rds.")))
    return(list(ok = TRUE, path = out, message = NULL))
  }

  # Any filter the fast path above couldn't handle.
  if (!is.null(year) || any_extra) {
    base <- .load_base_df_for_filtering(token, drive_id, form_id, heavy, year, work_dir, progress)
    if (is.null(base$df)) return(list(ok = FALSE, path = NULL, message = base$message))
    year_to_apply <- if (!is.null(year) && heavy) NULL else year
    filt <- .apply_raw_filters(base$df, form_id, year = year_to_apply, response = response, round_number = round_number)
    if (is.null(filt$df)) return(list(ok = FALSE, path = NULL, message = filt$error))
    stem <- .filtered_file_stem(form_id, year, response, round_number)
    progress(paste0("Writing ", stem, ".rds (", nrow(filt$df), " rows)..."))
    out <- file.path(work_dir, paste0(stem, ".rds"))
    ok <- tryCatch({ saveRDS(filt$df, out); TRUE }, error = function(e) FALSE)
    if (!ok)
      return(list(ok = FALSE, path = NULL, message = paste0("Could not write ", stem, ".rds.")))
    return(list(ok = TRUE, path = out, message = NULL))
  }

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
#
# `year`: optional, e.g. "2024" -- when set on a heavy (year-partitioned)
# form with no other filter, fetches/builds only that one year's data via the
# cheapest direct-file-copy path instead of every year. When set on a
# non-heavy form, or combined with `response`/`round_number` on any form, the
# data is read in and sliced down to match instead (see
# .load_base_df_for_filtering()/.apply_raw_filters()) -- there's no real
# per-year, per-Response, or per-round file sitting on SharePoint to fetch
# directly in those cases. Any of the three always returns a single plain
# file (never a zip, since there's only ever one result once filtered).
#
# `response`: optional, e.g. "Yes" -- filters to rows whose Response column
# (matched case-insensitively) equals this value (also compared
# case-insensitively). Gives a clear failure if the form has no such column.
#
# `round_number`: optional, e.g. "3" -- same idea, for the roundNumber
# column.
build_form_download <- function(form_id, format, progress = function(detail) invisible(NULL),
                                 year = NULL, response = NULL, round_number = NULL) {
  form_id <- as.character(form_id)
  # An empty string (a blank/untouched text input from the UI) means "no
  # filter", same as NULL -- normalize both to NULL once, here, so none of
  # the build_*_download() functions or helpers above need to re-check this.
  .nz <- function(x) if (is.null(x) || !nzchar(trimws(as.character(x)))) NULL else as.character(x)
  year         <- .nz(year)
  response     <- .nz(response)
  round_number <- .nz(round_number)

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
      parquet = build_parquet_download(token, drive_id, form_id, heavy, work_dir, progress, year, response, round_number),
      csv     = build_csv_download(token, drive_id, form_id, heavy, work_dir, progress, year, response, round_number),
      xlsx    = build_xlsx_download(token, drive_id, form_id, heavy, work_dir, progress, year, response, round_number),
      rds     = build_rds_download(token, drive_id, form_id, heavy, work_dir, progress, year, response, round_number),
      list(ok = FALSE, path = NULL, message = paste0("Unsupported format: ", format))
    )
  }, error = function(e) list(ok = FALSE, path = NULL, message = conditionMessage(e)))

  progress(if (isTRUE(result$ok)) "Done." else paste0("Failed: ", result$message))
  result
}
