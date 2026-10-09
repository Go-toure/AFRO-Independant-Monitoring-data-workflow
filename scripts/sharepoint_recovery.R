# ============================================================
# SHAREPOINT RECOVERY/BACKUP HELPERS (shared)
# ============================================================
# Generic small-file backup/recovery over Microsoft Graph, for pipeline
# scripts the Shiny dashboard launches directly as their own standalone
# Rscript process (afro_im_intilligence_analysis_engine.R,
# AFRO_Advocacy_Intelligence_Report.R via generate_reports_and_deck.R) --
# these never go through run_workflow.R, so they can't rely on its own
# sp_get_graph_token()/sp_recover_raw_forms()-style helpers or its
# load_secrets_env() call ever having run in this process. Kept in
# exactly one file (same philosophy as find_workflow_home.R) so this
# auth/folder/GET/PUT logic is never duplicated or drifted across the
# scripts that source it.
#
# Call sp_load_secrets_env(BASE_DIR) once near the top of a standalone
# script before using sp_recover_file()/sp_backup_file() -- a script
# sourced from inside run_workflow.R already has these credentials
# (run_workflow.R loads them itself before spawning/sourcing anything),
# but a script launched directly by the Shiny app does not.
#
# Every function here soft-fails: a missing credential, an unreachable
# SharePoint, or any HTTP error just means recovery/backup silently does
# nothing, and the calling script proceeds to fail with its own normal,
# clear error (e.g. "file not found") exactly as it would without this
# file existing at all.

sp_load_secrets_env <- function(base_dir) {
  secrets_file <- file.path(base_dir, "config", "secrets.env")
  if (!file.exists(secrets_file)) return(invisible(NULL))

  lines <- readLines(secrets_file, warn = FALSE)
  for (line in lines) {
    line <- trimws(line)
    if (nchar(line) == 0 || startsWith(line, "#") || !grepl("=", line, fixed = TRUE)) next
    parts <- strsplit(line, "=", fixed = TRUE)[[1]]
    key <- trimws(parts[1])
    value <- trimws(paste(parts[-1], collapse = "="))
    if (nzchar(key) && !nzchar(Sys.getenv(key))) {
      do.call(Sys.setenv, setNames(list(value), key))
    }
  }
  invisible(NULL)
}

sp_get_graph_token <- function() {
  tryCatch({
    tenant_id <- Sys.getenv("SHAREPOINT_TENANT_ID")
    client_id <- Sys.getenv("SHAREPOINT_CLIENT_ID")
    client_secret <- Sys.getenv("SHAREPOINT_CLIENT_SECRET")
    if (!nzchar(tenant_id) || !nzchar(client_id) || !nzchar(client_secret)) return(NULL)
    if (!requireNamespace("httr2", quietly = TRUE)) return(NULL)

    resp <- httr2::request(sprintf(
        "https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenant_id
      )) |>
      httr2::req_body_form(
        client_id = client_id, client_secret = client_secret,
        scope = "https://graph.microsoft.com/.default",
        grant_type = "client_credentials"
      ) |>
      httr2::req_perform()
    httr2::resp_body_json(resp)$access_token
  }, error = function(e) NULL)
}

sp_get_drive_id <- function(token) {
  tryCatch({
    site <- httr2::request(
        "https://graph.microsoft.com/v1.0/sites/worldhealthorg.sharepoint.com:/sites/AF-pep/GISWORKSPACE"
      ) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    drives <- httr2::request(sprintf("https://graph.microsoft.com/v1.0/sites/%s/drives", site$id)) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    match <- Filter(function(d) tolower(d$name) == "documents", drives$value)
    if (!length(match)) return(NULL)
    match[[1]]$id
  }, error = function(e) NULL)
}

sp_ensure_folder <- function(token, drive_id, folder_path) {
  # Read-only mode (country runs, see scripts/run_country_workflow.R): never write to SharePoint.
  if (identical(Sys.getenv("IM_READ_ONLY_SHAREPOINT"), "1")) return(list(ok = TRUE, error = NULL, folder = folder_path))
  # Returns list(ok = TRUE/FALSE, error = <message or NULL>, folder = <segment
  # that failed, or the full path on success>) -- kept in sync with
  # run_workflow.R's own copy of this function (both had to exist
  # separately since this file is sourced by scripts that never go through
  # run_workflow.R -- see this file's header comment).
  segments <- Filter(nzchar, strsplit(folder_path, "/")[[1]])
  current <- ""

  for (seg in segments) {
    parent <- current
    current <- if (nzchar(current)) paste0(current, "/", seg) else seg

    exists <- tryCatch({
      check_url <- sprintf(
        "https://graph.microsoft.com/v1.0/drives/%s/root:/%s",
        drive_id, utils::URLencode(current)
      )
      httr2::request(check_url) |>
        httr2::req_auth_bearer_token(token) |>
        httr2::req_perform()
      TRUE
    }, error = function(e) FALSE)

    if (exists) next

    create_error <- NULL
    created <- tryCatch({
      if (nzchar(parent)) {
        parent_url <- sprintf(
          "https://graph.microsoft.com/v1.0/drives/%s/root:/%s",
          drive_id, utils::URLencode(parent)
        )
        parent_id <- (httr2::request(parent_url) |>
          httr2::req_auth_bearer_token(token) |>
          httr2::req_perform() |>
          httr2::resp_body_json())$id
        create_url <- sprintf(
          "https://graph.microsoft.com/v1.0/drives/%s/items/%s/children",
          drive_id, parent_id
        )
      } else {
        create_url <- sprintf("https://graph.microsoft.com/v1.0/drives/%s/root/children", drive_id)
      }
      httr2::request(create_url) |>
        httr2::req_auth_bearer_token(token) |>
        httr2::req_body_json(list(
          name = seg,
          # An empty R list() has NULL names, so jsonlite serializes it as
          # JSON [] (array) by default -- Graph's schema requires "folder"
          # to be an OBJECT ({}), and rejects [] with a 400 "Property
          # folder in payload has a value that does not match schema".
          # Giving it an explicit (empty) names attribute makes jsonlite
          # treat it as an object instead.
          folder = structure(list(), names = character(0)),
          "@microsoft.graph.conflictBehavior" = "rename"
        )) |>
        httr2::req_perform()
      TRUE
    }, error = function(e) {
      # conditionMessage(e) alone is just the HTTP status line (e.g. "HTTP
      # 400 Bad Request"), which isn't enough to act on -- Microsoft Graph
      # normally returns a JSON body with the real error.code/error.message
      # explaining what was actually wrong with the request. httr2 attaches
      # the raw response to the condition as e$resp for exactly this case
      # (see httr2's own error-handling docs); pull the body out when it's
      # there, and fall back to the plain status line if it isn't (e.g. a
      # connection-level error with no response at all).
      detail <- conditionMessage(e)
      if (!is.null(e$resp)) {
        body_detail <- tryCatch({
          body <- httr2::resp_body_json(e$resp)
          if (!is.null(body$error$message)) {
            paste0(body$error$code, ": ", body$error$message)
          } else {
            NULL
          }
        }, error = function(e2) NULL)
        if (!is.null(body_detail)) {
          detail <- paste0(detail, " -- ", body_detail)
        }
      }
      create_error <<- detail
      FALSE
    })

    if (!created) {
      return(list(ok = FALSE, error = create_error, folder = current))
    }
  }

  list(ok = TRUE, error = NULL, folder = folder_path)
}

sp_recover_file <- function(local_path, remote_path) {
  # Soft-fail, and never overwrite a file that's already there -- this
  # can never clobber a fresher local copy from a run earlier in this
  # same session.
  if (file.exists(local_path)) return(invisible(NULL))
  if (!requireNamespace("httr2", quietly = TRUE)) return(invisible(NULL))

  token <- sp_get_graph_token()
  if (is.null(token)) return(invisible(NULL))
  drive_id <- sp_get_drive_id(token)
  if (is.null(drive_id)) return(invisible(NULL))

  content_url <- sprintf(
    "https://graph.microsoft.com/v1.0/drives/%s/root:/%s:/content",
    drive_id, utils::URLencode(remote_path)
  )

  tryCatch({
    resp <- httr2::request(content_url) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_perform()
    dir.create(dirname(local_path), recursive = TRUE, showWarnings = FALSE)
    writeBin(httr2::resp_body_raw(resp), local_path)
    message("Recovered ", basename(local_path), " from SharePoint (no local copy existed yet).")
  }, error = function(e) {
    message("Could not recover ", basename(local_path), " from SharePoint: ", conditionMessage(e))
  })

  invisible(NULL)
}

# ------------------------------------------------------------
# Version-history pruning for files this pipeline overwrites
# ------------------------------------------------------------
# SharePoint keeps the PREVIOUS content of every overwritten file as a full
# extra version in the library's Document Version History. Every backup
# below overwrites the same file on each run, so without trimming, that
# history grows by one full copy per run -- the same mechanism behind the
# ~180 GB growth Fetch_im_data.py now prevents for raw_state (see
# SP_RAW_VERSIONS_TO_KEEP there) and upload_to_sharepoint.py prevents for
# its own uploads (SP_UPLOAD_VERSIONS_TO_KEEP, same name and same env var).
# After each successful backup, only the newest N HISTORICAL versions are
# kept; the live file is never touched. Override with the
# SP_UPLOAD_VERSIONS_TO_KEEP env var; a negative value turns pruning off.
# Best-effort like everything else here: any failure is reported with
# message() and swallowed, so a prune problem can never fail a backup.
# Kept in sync with the copy in run_workflow.R (this file is sourced by scripts
# that never go through run_workflow.R -- see this file's header comment).
SP_UPLOAD_VERSIONS_TO_KEEP <- local({
  v <- suppressWarnings(as.integer(trimws(Sys.getenv("SP_UPLOAD_VERSIONS_TO_KEEP", "1"))))
  if (is.na(v)) 1L else v
})

sp_prune_old_versions <- function(token, drive_id, remote_path, keep = SP_UPLOAD_VERSIONS_TO_KEEP) {
  # Read-only mode (country runs, see scripts/run_country_workflow.R): never write to SharePoint.
  if (identical(Sys.getenv("IM_READ_ONLY_SHAREPOINT"), "1")) return(invisible(0L))
  # Returns the number of versions deleted (0 on nothing-to-prune or any
  # failure). Mirrors _sharepoint_client.prune_old_versions() in Python.
  if (is.na(keep) || keep < 0L) return(invisible(0L))
  transient <- function(resp) httr2::resp_status(resp) %in% c(429L, 502L, 503L, 504L)
  perform <- function(url, method = "GET") {
    httr2::request(url) |>
      httr2::req_method(method) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_retry(max_tries = 4, is_transient = transient) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()
  }
  name <- basename(remote_path)

  tryCatch({
    base <- sprintf("https://graph.microsoft.com/v1.0/drives/%s", drive_id)
    item <- perform(sprintf("%s/root:/%s", base, utils::URLencode(remote_path)))
    if (httr2::resp_status(item) == 404L) return(invisible(0L))
    if (httr2::resp_status(item) >= 400L) {
      message("Could not look up ", name, " to prune its old versions (HTTP ", httr2::resp_status(item), ").")
      return(invisible(0L))
    }
    item_id <- httr2::resp_body_json(item)$id

    versions_url <- sprintf("%s/items/%s/versions", base, item_id)
    versions <- list()
    url <- versions_url
    while (!is.null(url)) {
      resp <- perform(url)
      if (httr2::resp_status(resp) >= 400L) {
        message("Could not list old versions of ", name, " (HTTP ", httr2::resp_status(resp), ").")
        return(invisible(0L))
      }
      body <- httr2::resp_body_json(resp)
      versions <- c(versions, body$value)
      url <- body[["@odata.nextLink"]]
    }
    if (length(versions) <= keep) return(invisible(0L))

    # Newest first, sorted explicitly rather than trusting response order.
    stamps <- vapply(versions, function(v) {
      s <- v$lastModifiedDateTime
      if (is.null(s)) "" else as.character(s)
    }, character(1))
    versions <- versions[order(stamps, decreasing = TRUE)]
    to_delete <- versions[seq.int(keep + 1L, length(versions))]

    deleted <- 0L
    for (v in to_delete) {
      if (is.null(v$id)) next
      dr <- perform(sprintf("%s/%s", versions_url, utils::URLencode(v$id, reserved = TRUE)), "DELETE")
      if (httr2::resp_status(dr) %in% c(204L, 404L)) {
        deleted <- deleted + 1L
      } else {
        message("Could not delete old version ", v$id, " of ", name, " (HTTP ", httr2::resp_status(dr), ").")
      }
    }
    invisible(deleted)
  }, error = function(e) {
    message("Could not prune old versions of ", name, ": ", conditionMessage(e))
    invisible(0L)
  })
}

sp_backup_file <- function(local_path, remote_path) {
  # Read-only mode (country runs, see scripts/run_country_workflow.R): never write to SharePoint.
  if (identical(Sys.getenv("IM_READ_ONLY_SHAREPOINT"), "1")) return(invisible(NULL))
  if (!file.exists(local_path)) return(invisible(NULL))
  if (!requireNamespace("httr2", quietly = TRUE)) return(invisible(NULL))

  token <- sp_get_graph_token()
  if (is.null(token)) return(invisible(NULL))
  drive_id <- sp_get_drive_id(token)
  if (is.null(drive_id)) return(invisible(NULL))

  remote_folder <- dirname(remote_path)
  folder_result <- sp_ensure_folder(token, drive_id, remote_folder)
  if (!folder_result$ok) {
    error_detail <- if (is.null(folder_result$error)) "unknown error" else folder_result$error
    message("Could not ensure SharePoint folder ", remote_folder, " exists -- skipping backup of ", basename(local_path), ". Reason: ", error_detail)
    return(invisible(NULL))
  }

  content_url <- sprintf(
    "https://graph.microsoft.com/v1.0/drives/%s/root:/%s:/content",
    drive_id, utils::URLencode(remote_path)
  )

  tryCatch({
    httr2::request(content_url) |>
      httr2::req_auth_bearer_token(token) |>
      httr2::req_method("PUT") |>
      httr2::req_headers("Content-Type" = "application/octet-stream") |>
      httr2::req_body_file(local_path) |>
      httr2::req_perform()
    message("Backed up ", basename(local_path), " to SharePoint (", remote_folder, ").")
    pruned <- sp_prune_old_versions(token, drive_id, remote_path)
    if (pruned > 0L) {
      message("Pruned ", pruned, " old version(s) of ", basename(local_path), " (kept ", SP_UPLOAD_VERSIONS_TO_KEEP, ").")
    }
  }, error = function(e) {
    message("Could not back up ", basename(local_path), " to SharePoint: ", conditionMessage(e))
  })

  invisible(NULL)
}
