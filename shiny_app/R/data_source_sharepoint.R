# ============================================================
# SHAREPOINT DATA SOURCE (fallback for Posit Connect Cloud)
# ============================================================
# On the user's own machine, the nightly pipeline (scripts/run_workflow.R)
# writes CLEANED_CSV etc. straight into FINAL_DIR, so none of this ever
# runs there -- load_im_data() just finds the local file. On Posit Connect
# Cloud, this app has no access to that machine's disk and never runs the
# pipeline itself, so on first load those files won't exist yet. In that
# case, load_im_data() calls download_cleaned_data_from_sharepoint() below
# to pull the pipeline's last output straight from SharePoint -- the same
# file scripts/upload_to_sharepoint.py already pushes there after every
# local pipeline run -- using the same Microsoft Graph app-only credentials
# (SHAREPOINT_TENANT_ID / SHAREPOINT_CLIENT_ID / SHAREPOINT_CLIENT_SECRET)
# already set as environment variables for this deployment. Once that
# download succeeds, the file sits in FINAL_DIR like any local run, and
# later calls in the same running instance just find it there.

SP_HOSTNAME      <- "worldhealthorg.sharepoint.com"
SP_SITE_PATH     <- "/sites/AF-pep/GISWORKSPACE"
SP_LIBRARY_NAME  <- "Documents"
SP_TARGET_FOLDER <- "7. SIA_Data/Data Repository"
SP_REMOTE_CSV    <- "AFRO_Inside_HH_M.csv"

sharepoint_credentials_available <- function() {
  nzchar(Sys.getenv("SHAREPOINT_TENANT_ID")) &&
    nzchar(Sys.getenv("SHAREPOINT_CLIENT_ID")) &&
    nzchar(Sys.getenv("SHAREPOINT_CLIENT_SECRET"))
}

sp_get_graph_token <- function() {
  resp <- httr2::request(sprintf(
      "https://login.microsoftonline.com/%s/oauth2/v2.0/token",
      Sys.getenv("SHAREPOINT_TENANT_ID")
    )) |>
    httr2::req_body_form(
      client_id     = Sys.getenv("SHAREPOINT_CLIENT_ID"),
      client_secret = Sys.getenv("SHAREPOINT_CLIENT_SECRET"),
      scope         = "https://graph.microsoft.com/.default",
      grant_type    = "client_credentials"
    ) |>
    httr2::req_perform()
  httr2::resp_body_json(resp)$access_token
}

sp_resolve_drive_id <- function(token) {
  site_url <- sprintf("https://graph.microsoft.com/v1.0/sites/%s:%s", SP_HOSTNAME, SP_SITE_PATH)
  site <- httr2::request(site_url) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_perform() |>
    httr2::resp_body_json()

  drives <- httr2::request(sprintf("https://graph.microsoft.com/v1.0/sites/%s/drives", site$id)) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_perform() |>
    httr2::resp_body_json()

  match <- Filter(function(d) tolower(d$name) == tolower(SP_LIBRARY_NAME), drives$value)
  if (!length(match)) stop("SharePoint library '", SP_LIBRARY_NAME, "' not found")
  match[[1]]$id
}

# ============================================================
# GENERIC GRAPH LIST/DOWNLOAD (raw_state form-data downloads)
# ============================================================
# The two functions above (sp_get_graph_token / sp_resolve_drive_id) plus
# these two give this app the same generic list/download building blocks
# scripts/_sharepoint_client.py already provides on the Python side --
# used by R/data_download_raw.R's "Download Raw Form Data" feature so it
# never needs to shell out to Python just to read a folder or pull a file.
# Same never-raise-to-the-caller contract as their Python counterparts:
# list returns an empty list and download returns FALSE on any failure
# (missing item, bad credentials, network error, ...), never an R error.

# Every item (files + subfolders) directly inside folder_path. Empty list
# if the folder doesn't exist, is empty, or on any error.
sp_list_folder <- function(token, drive_id, folder_path) {
  tryCatch({
    url <- sprintf(
      "https://graph.microsoft.com/v1.0/drives/%s/root:/%s:/children",
      drive_id, utils::URLencode(folder_path)
    )
    items <- list()
    repeat {
      resp <- httr2::request(url) |>
        httr2::req_auth_bearer_token(token) |>
        httr2::req_perform()
      body  <- httr2::resp_body_json(resp)
      items <- c(items, body$value)
      next_link <- body[["@odata.nextLink"]]
      if (is.null(next_link)) break
      url <- next_link
    }
    items
  }, error = function(e) list())
}

# Downloads one file by its path (relative to the library root) to
# local_path. Returns FALSE on any failure, including the file not
# existing remotely.
sp_download_file <- function(token, drive_id, remote_path, local_path) {
  tryCatch({
    url <- sprintf(
      "https://graph.microsoft.com/v1.0/drives/%s/root:/%s:/content",
      drive_id, utils::URLencode(remote_path)
    )
    resp <- httr2::request(url) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_perform()
    dir.create(dirname(local_path), recursive = TRUE, showWarnings = FALSE)
    writeBin(httr2::resp_body_raw(resp), local_path)
    TRUE
  }, error = function(e) {
    message("[sharepoint] download failed for ", remote_path, ": ", conditionMessage(e))
    FALSE
  })
}

# Metadata only (no file content) for one item -- used to read its
# lastModifiedDateTime without downloading the file itself. Returns NULL on
# any failure (missing item, bad credentials, network error, ...).
sp_get_item_metadata <- function(token, drive_id, remote_path) {
  tryCatch({
    url <- sprintf(
      "https://graph.microsoft.com/v1.0/drives/%s/root:/%s",
      drive_id, utils::URLencode(remote_path)
    )
    httr2::request(url) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
  }, error = function(e) NULL)
}

# "Last Pipeline Run" as seen from Posit Connect Cloud. Connect Cloud never
# runs scripts/run_workflow.R itself, so there is no local workflow_*.log for
# last_run_info() (R/data_helpers.R) to read there -- it's always empty.
# The best available signal in that environment is when AFRO_Inside_HH_M.csv
# on SharePoint was itself last modified: scripts/upload_to_sharepoint.py
# overwrites that file at the end of every successful nightly run, so its
# lastModifiedDateTime effectively IS the last pipeline run time. Returns
# NULL (never a partial/garbage result) if credentials are missing, any
# Graph call fails, or the timestamp can't be parsed -- callers should treat
# NULL the same as "unknown" and fall back accordingly.
sharepoint_last_pipeline_run <- function() {
  if (!sharepoint_credentials_available()) return(NULL)
  tryCatch({
    token     <- sp_get_graph_token()
    drive_id  <- sp_resolve_drive_id(token)
    item_path <- paste(SP_TARGET_FOLDER, SP_REMOTE_CSV, sep = "/")
    meta <- sp_get_item_metadata(token, drive_id, item_path)
    ts <- meta$lastModifiedDateTime
    if (is.null(ts) || !nzchar(ts)) return(NULL)
    ts   <- sub("\\.\\d+Z$", "Z", ts)  # drop fractional seconds, if any
    when <- as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    if (is.na(when)) return(NULL)
    list(
      time   = paste0(format(when, "%Y-%m-%d  %H:%M", tz = "UTC"), " UTC"),
      status = "ok",
      log    = ""
    )
  }, error = function(e) NULL)
}

# Downloads AFRO_Inside_HH_M.csv from SharePoint into `dest_path` (CLEANED_CSV
# by default). Never throws -- returns TRUE/FALSE so load_im_data() can just
# fall through to "no data" if this fails, same as a missing local file today.
download_cleaned_data_from_sharepoint <- function(dest_path = CLEANED_CSV) {
  if (!sharepoint_credentials_available()) {
    message("[sharepoint] Credentials not set -- skipping SharePoint fallback.")
    return(FALSE)
  }
  tryCatch({
    token     <- sp_get_graph_token()
    drive_id  <- sp_resolve_drive_id(token)
    item_path <- paste(SP_TARGET_FOLDER, SP_REMOTE_CSV, sep = "/")
    content_url <- sprintf(
      "https://graph.microsoft.com/v1.0/drives/%s/root:/%s:/content",
      drive_id, utils::URLencode(item_path)
    )
    resp <- httr2::request(content_url) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_perform()
    dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)
    writeBin(httr2::resp_body_raw(resp), dest_path)
    message("[sharepoint] Downloaded ", SP_REMOTE_CSV, " -> ", dest_path)
    TRUE
  }, error = function(e) {
    message("[sharepoint] FAILED to download from SharePoint: ", conditionMessage(e))
    FALSE
  })
}
