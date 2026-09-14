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
