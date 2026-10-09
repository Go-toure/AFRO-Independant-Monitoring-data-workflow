# ============================================================
# COUNTRY RUN  ("My data" tab: fetch -> process -> clean -> download)
# ============================================================
# Auto-sourced by Shiny (shiny_app/R/). A signed-in COUNTRY user (see
# R/access_control.R) can refresh and clean their own country's form. The work
# is done by scripts/run_country_workflow.R in a private scratch folder with
# SharePoint writes switched off; the result is only offered as a download
# (nothing is saved to the regional repository or to SharePoint).
#
# Pure helpers (slots, scratch folders, filtering, export) are separate from
# the session wiring (cr_session_init) so they can be tested without a session.
# ============================================================

if (!exists("%||%", mode = "function")) `%||%` <- function(a, b) if (is.null(a)) b else a

# ── limits & scratch location ───────────────────────────────────────────────
cr_max_runs <- function() {
  v <- suppressWarnings(as.integer(Sys.getenv("IM_COUNTRY_MAX_RUNS", "2")))
  if (is.na(v) || v < 1L) 2L else v
}

# Shared by every R process on this server (one level above each process's own tempdir()).
cr_runs_root <- function() {
  root <- Sys.getenv("IM_COUNTRY_RUNS_DIR", "")
  if (!nzchar(root)) root <- file.path(dirname(tempdir()), "im_country_runs")
  dir.create(root, showWarnings = FALSE, recursive = TRUE, mode = "0700")
  root
}

cr_pid_alive <- function(pid) {
  pid <- suppressWarnings(as.integer(pid))
  if (is.na(pid) || pid <= 0L) return(FALSE)
  if (.Platform$OS.type == "windows") return(TRUE)         # cannot probe cheaply; the age limit still applies
  isTRUE(tryCatch(tools::pskill(pid, 0L), error = function(e) FALSE))
}

cr_read_owner <- function(dir) {
  f <- file.path(dir, ".owner")
  if (!file.exists(f)) return(NA_integer_)
  suppressWarnings(as.integer(readLines(f, n = 1L, warn = FALSE)))
}

# Remove scratch folders whose owning process is gone, or that are older than max_age_h.
# A folder younger than `grace_s` is never touched: cr_try_acquire() creates the folder a
# moment before it writes `.owner`, and another session's sweep must not delete it in between.
cr_sweep <- function(root = cr_runs_root(), max_age_h = 6, now = Sys.time(), grace_s = 120) {
  # Only folders this module created (exact name pattern); a folder without an `.owner` file is
  # never treated as "dead" -- it is only removed once it is older than max_age_h.
  dirs <- list.files(root, pattern = "^run_[0-9]{8}_[0-9]{6}_[0-9a-f]{8}$", full.names = TRUE)
  dirs <- dirs[dir.exists(dirs)]
  for (d in dirs) {
    age_s <- as.numeric(difftime(now, file.mtime(d), units = "secs"))
    if (is.na(age_s) || age_s < grace_s) next
    owner <- cr_read_owner(d)
    too_old <- age_s > max_age_h * 3600
    dead <- !is.na(owner) && !cr_pid_alive(owner)
    if (too_old || dead) unlink(d, recursive = TRUE, force = TRUE)
  }
  invisible(NULL)
}

cr_active_count <- function(root = cr_runs_root()) {
  dirs <- list.files(root, pattern = "^run_", full.names = TRUE)
  sum(file.exists(file.path(dirs, ".active")))
}

# Is a run for this form already active on this server (any session)?
cr_form_busy <- function(root = cr_runs_root(), form_id) {
  dirs <- list.files(root, pattern = "^run_", full.names = TRUE)
  dirs <- dirs[file.exists(file.path(dirs, ".active"))]
  for (d in dirs) {
    f <- file.path(d, ".form")
    if (file.exists(f) && identical(trimws(readLines(f, n = 1L, warn = FALSE)), as.character(form_id))) return(TRUE)
  }
  FALSE
}

# Claim a run slot and create a fresh private scratch folder; NULL when the server is full.
cr_try_acquire <- function(root = cr_runs_root(), max_runs = cr_max_runs(), form_id = NULL) {
  cr_sweep(root)
  if (cr_active_count(root) >= max_runs) return(NULL)
  home <- file.path(root, sprintf("run_%s_%s", format(Sys.time(), "%Y%m%d_%H%M%S"),
                                  paste(sample(c(0:9, letters[1:6]), 8, TRUE), collapse = "")))
  if (!dir.create(home, showWarnings = FALSE, mode = "0700")) return(NULL)
  writeLines(as.character(Sys.getpid()), file.path(home, ".owner"))
  if (!is.null(form_id)) writeLines(as.character(form_id), file.path(home, ".form"))
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), file.path(home, ".active"))
  home
}

cr_release_slot <- function(home) {
  if (!is.null(home) && nzchar(home)) unlink(file.path(home, ".active"), force = TRUE)
  invisible(NULL)
}

cr_discard <- function(home) {
  if (!is.null(home) && nzchar(home) && basename(home) != "" && grepl("^run_", basename(home)))
    unlink(home, recursive = TRUE, force = TRUE)
  invisible(NULL)
}

# ── what a country user is allowed to read in the progress log ──────────────
CR_BLOCKED <- paste0("(?i)sharepoint|graph\\.microsoft|https?://|file:|token|secret|passw|tenant|client[_ -]?(id|secret)|",
                     "api[_ -]?key|authorization|bearer|\\.env|traceback|site[_ -]?id|drive[_ -]?id|raw_state|lookup_state|",
                     "site-packages|^File \"|\\.py\\b|host=|\\.(org|com|net|int|io|gov|edu)\\b")

# Anything that looks like a file-system path (has a slash/backslash run containing a letter) is masked.
CR_PATHLIKE <- "(?:[A-Za-z]:)?[\\\\/](?=[^\\s'\"()<>]*[A-Za-z_])[^\\s'\"()<>]+[\\\\/]\\S*"

cr_clean_lines <- function(lines) {
  lines <- as.character(lines)
  # Force plain printable ASCII first: invalid bytes would otherwise make the regex calls fail.
  lines <- iconv(lines, from = "", to = "ASCII", sub = "")
  lines[is.na(lines)] <- ""
  lines <- gsub("\033\\[[0-9;]*[A-Za-z]", "", lines)
  lines <- trimws(gsub("[^\\x20-\\x7E]", "", lines, perl = TRUE))
  lines <- lines[nzchar(lines) & !grepl(CR_BLOCKED, lines, perl = TRUE)]
  lines <- gsub(CR_PATHLIKE, "<path>", lines, perl = TRUE)
  lines <- sub("^\\[country-run\\] ?", "", lines)
  ifelse(nchar(lines) > 160L, paste0(substr(lines, 1L, 157L), "..."), lines)
}

# ── export: cleaned / raw data in the chosen format ─────────────────────────
CR_EXCEL_MAX_ROWS <- 1048575L

cr_write_df <- function(df, fmt, out) {
  switch(fmt,
    csv     = readr::write_csv(df, out, na = ""),
    parquet = arrow::write_parquet(df, out),
    rds     = saveRDS(df, out),
    xlsx    = {
      if (nrow(df) > CR_EXCEL_MAX_ROWS)
        stop(sprintf("This table has %s rows, more than Excel can hold (1,048,575). Please choose CSV or Parquet.",
                     format(nrow(df), big.mark = ",")))
      writexl::write_xlsx(df, out)
    },
    stop("Unknown format: ", fmt))
  invisible(TRUE)
}

cr_read_any <- function(path) {
  switch(tolower(tools::file_ext(path)),
         parquet = as.data.frame(arrow::read_parquet(path)),
         rds     = readRDS(path),
         csv     = as.data.frame(readr::read_csv(path, show_col_types = FALSE, guess_max = 10000)),
         stop("Unsupported file: ", basename(path)))
}

# kind: "clean" (the cleaned repository for this form) or "raw" (the freshly fetched raw form).
# Returns list(ok, message). Never throws.
cr_export <- function(home, kind = c("clean", "raw"), fmt, out_file, form_id = NULL) {
  kind <- match.arg(kind)
  tryCatch({
    if (!fmt %in% c("csv", "xlsx", "parquet", "rds")) stop("Unknown format.")
    if (kind == "clean") {
      stem <- file.path(home, "data", "final", "Regional_IM_repository_cleaned")
      native <- paste0(stem, ".", fmt)
      if (fmt %in% c("csv", "parquet", "rds") && file.exists(native)) {
        file.copy(native, out_file, overwrite = TRUE)
        return(list(ok = TRUE, message = ""))
      }
      src <- Filter(file.exists, paste0(stem, c(".parquet", ".rds", ".csv")))[1]
      if (is.na(src)) stop("The cleaned data is not available yet - run \"Fetch & clean my data\" first.")
    } else {
      if (is.null(form_id) || !grepl("^[0-9]{1,8}$", form_id)) stop("Unknown form.")
      src <- file.path(home, "data", "raw", paste0(form_id, ".parquet"))
      if (!file.exists(src)) stop("The raw data is not available yet - run \"Fetch & clean my data\" first.")
      if (fmt == "parquet") {
        file.copy(src, out_file, overwrite = TRUE)
        return(list(ok = TRUE, message = ""))
      }
    }
    cr_write_df(cr_read_any(src), fmt, out_file)
    list(ok = TRUE, message = "")
  }, error = function(e) {
    msg <- conditionMessage(e)
    message("[country-run] export failed: ", msg)                      # full text stays in the server log
    safe <- grepl("more than Excel|not available yet|^Unknown (format|form)", msg)
    list(ok = FALSE, message = if (safe) msg else
      "The file could not be prepared. Please try another format, or contact the regional office.")
  })
}

cr_download_name <- function(kind, fmt, country_label, today = Sys.Date()) {
  stem <- gsub("[^A-Za-z0-9]+", "_", country_label)
  stem <- gsub("^_+|_+$", "", stem)
  if (!nzchar(stem)) stem <- "country"
  paste0("IM_", stem, "_", if (kind == "clean") "cleaned" else "raw", "_", format(today), ".", fmt)
}

# ── UI ──────────────────────────────────────────────────────────────────────
cr_ui <- function() {
  layout_columns(
    col_widths = c(4, 8), gap = "14px",
    card(
      card_header(hdr_icon("person-circle", "My data")),
      card_body(
        div(class = "info-banner mb-3",
          "Fetch the latest submissions for your country's form, then process and clean them. ",
          "The result is yours to download - nothing is saved to the regional repository. ",
          "A run can take several minutes; keep this page open until it finishes."),
        selectInput("cr_form", "Form", choices = NULL, width = "100%"),
        div(class = "d-grid gap-2",
          actionButton("cr_run", hdr_icon("play-fill", "Fetch & clean my data"), class = "btn-success btn-lg"),
          shinyjs::disabled(
            actionButton("cr_stop", hdr_icon("stop-fill", "Stop"), class = "btn-outline-danger"))),
        tags$hr(style = "border-color:rgba(0,0,0,.08);margin:12px 0;"),
        selectInput("cr_fmt", "Download format",
                    c("CSV" = "csv", "Excel (.xlsx)" = "xlsx", "Parquet" = "parquet", "R data (.rds)" = "rds"),
                    width = "100%"),
        div(class = "d-grid gap-2",
          shinyjs::disabled(downloadButton("cr_dl_clean", hdr_icon("download", "Cleaned data"), class = "btn-outline-primary")),
          shinyjs::disabled(downloadButton("cr_dl_raw",   hdr_icon("download", "Raw data (fresh)"), class = "btn-outline-secondary"))),
        uiOutput("cr_dl_msg")
      )
    ),
    card(
      card_header(div(class = "d-flex align-items-center gap-3",
        hdr_icon("broadcast", "Progress"), uiOutput("cr_status_badge"))),
      tags$pre(id = "cr_log_pre",
               style = "height:420px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;",
               textOutput("cr_log_txt", inline = TRUE))
    )
  )
}

# ── session wiring ──────────────────────────────────────────────────────────
# `auth` is the list returned by ac_session_init(). `source_home` is the regional
# BASE_DIR (its data/lookup/lookup.xlsx seeds the run). `script` is overridable for tests.
cr_session_init <- function(input, output, session, auth, source_home = NULL,
                            script = NULL, root = cr_runs_root()) {
  if (is.null(script)) {
    cand <- c(file.path(source_home, "scripts", "run_country_workflow.R"),
              file.path("..", "scripts", "run_country_workflow.R"))
    script <- Filter(file.exists, cand)[1]
  }

  cr <- shiny::reactiveValues(status = "idle", log = character(), home = NULL, proc = NULL,
                              pos = 0L, form = NULL, label = "", ok = FALSE)

  is_country <- function() identical(auth$user()$role, "country")
  add_log <- function(lines, runner = FALSE) {
    # Output of the runner process: only its own "[country-run] ..." progress lines are shown;
    # anything a child script printed that is not one of those is dropped.
    if (runner) lines <- lines[grepl("^\\[country-run\\]", trimws(lines))]
    lines <- cr_clean_lines(lines)
    if (length(lines)) cr$log <- utils::tail(c(cr$log, lines), 400L)
  }

  # Form choices for this user.
  shiny::observe({
    u <- auth$user()
    shiny::req(u, identical(u$role, "country"))
    map  <- ac_country_forms()
    rows <- map[map$form_id %in% u$forms, , drop = FALSE]
    shiny::updateSelectInput(session, "cr_form",
      choices = stats::setNames(rows$form_id, sprintf("%s (form %s)", rows$country_name, rows$form_id)))
  })

  finish <- function(exit_status) {
    home <- shiny::isolate(cr$home)
    cr_release_slot(home)
    res <- tryCatch(jsonlite::fromJSON(file.path(home, "run_result.json")), error = function(e) NULL)
    ok  <- identical(as.integer(exit_status), 0L) && !is.null(res) && isTRUE(res$ok)
    cr$proc <- NULL
    cr$ok   <- ok
    cr$status <- if (ok) "ok" else "error"
    if (!ok && (is.null(res) || !nzchar(res$message %||% "")))
      add_log("The run stopped unexpectedly. Please try again; if it keeps happening, contact the regional office.")
    shiny::showNotification(
      if (ok) "Your data is ready to download." else "The run did not complete - see the progress log.",
      type = if (ok) "message" else "error", duration = 8)
  }

  shiny::observeEvent(input$cr_run, {
    if (!is_country()) return()
    fid <- input$cr_form
    if (!is.character(fid) || length(fid) != 1L || is.na(fid) || !nzchar(fid) || !auth$form_ok(fid)) return()
    if (identical(shiny::isolate(cr$status), "running")) return()
    if (is.null(script) || is.na(script)) {
      add_log("This feature is not available on this server."); return()
    }

    cr_discard(shiny::isolate(cr$home))               # drop the previous run's files
    if (cr_form_busy(root, fid)) {
      shiny::showNotification("A run for this form is already in progress (perhaps in another browser tab). Please wait for it to finish.",
                              type = "warning", duration = 10)
      return()
    }
    home <- cr_try_acquire(root, form_id = fid)
    if (is.null(home)) {
      shiny::showNotification("The server is busy with other countries' runs. Please try again in a few minutes.",
                              type = "warning", duration = 10)
      return()
    }
    out <- file.path(home, "runner_stdout.txt")
    err <- file.path(home, "runner_stderr.txt")        # never shown to the user
    proc <- tryCatch(
      processx::process$new(file.path(R.home("bin"), "Rscript"),
                            c(script, "--home", home, "--form-id", fid),
                            stdout = out, stderr = err, cleanup_tree = TRUE,
                            env = c("current",
                                    IM_SOURCE_HOME = if (is.null(source_home)) "" else source_home,
                                    IM_ADMIN_CODES = "", IM_COUNTRY_CODES = "", ANTHROPIC_API_KEY = "")),
      error = function(e) NULL)
    if (is.null(proc)) {
      cr_release_slot(home); cr_discard(home)
      shiny::showNotification("Could not start the run on this server.", type = "error")
      return()
    }
    map <- ac_country_forms()
    cr$label  <- map$country_name[match(fid, map$form_id)]
    cr$form   <- fid
    cr$home   <- home
    cr$proc   <- proc
    cr$pos    <- 0L
    cr$ok     <- FALSE
    cr$log    <- character()
    cr$status <- "running"
    add_log(sprintf("Started %s for %s ...", format(Sys.time(), "%H:%M:%S"), cr$label))
  })

  shiny::observeEvent(input$cr_stop, {
    if (!is_country()) return()
    p <- shiny::isolate(cr$proc)
    if (is.null(p) || !p$is_alive()) return()
    tryCatch(p$kill_tree(), error = function(e) NULL)
    cr_release_slot(shiny::isolate(cr$home))
    cr$proc <- NULL; cr$status <- "stopped"; cr$ok <- FALSE
    add_log("Stopped by you.")
  })

  # Poll the runner: stream its (already filtered) output, detect completion.
  shiny::observe({
    shiny::req(identical(cr$status, "running"))
    shiny::invalidateLater(1000, session)
    p <- shiny::isolate(cr$proc); home <- shiny::isolate(cr$home)
    if (is.null(p)) return()
    f <- file.path(home, "runner_stdout.txt")
    if (file.exists(f)) {
      pos <- shiny::isolate(cr$pos); sz <- file.info(f)$size
      if (!is.na(sz) && sz > pos) {
        con <- file(f, "rb")
        if (pos > 0L) seek(con, pos)
        raw <- readBin(con, "raw", n = as.integer(sz - pos))
        close(con)
        cr$pos <- pos + length(raw)
        txt <- tryCatch(rawToChar(raw), error = function(e) "")
        add_log(strsplit(txt, "\r?\n")[[1]], runner = TRUE)
      }
    }
    if (!p$is_alive()) {
      Sys.sleep(0.2)                                   # let the last bytes land
      if (file.exists(f)) {
        pos <- shiny::isolate(cr$pos); sz <- file.info(f)$size
        if (!is.na(sz) && sz > pos) {
          con2 <- file(f, "rb"); seek(con2, pos)
          raw <- readBin(con2, "raw", n = as.integer(sz - pos)); close(con2)
          add_log(strsplit(tryCatch(rawToChar(raw), error = function(e) ""), "\r?\n")[[1]], runner = TRUE)
        }
      }
      finish(p$get_exit_status())
    }
  })

  shiny::observe({
    running <- identical(cr$status, "running")
    tryCatch({
      shinyjs::toggleState("cr_run",  !running)
      shinyjs::toggleState("cr_form", !running)
      shinyjs::toggleState("cr_stop", running)
      shinyjs::toggleState("cr_dl_clean", identical(cr$status, "ok"))
      shinyjs::toggleState("cr_dl_raw",   identical(cr$status, "ok"))
    }, error = function(e) NULL)
  })

  output$cr_log_txt <- shiny::renderText({
    shiny::req(is_country())
    if (!length(cr$log)) "Press \"Fetch & clean my data\" to start." else paste(cr$log, collapse = "\n")
  })

  output$cr_status_badge <- shiny::renderUI({
    shiny::req(is_country())
    st <- cr$status
    cls <- switch(st, ok = "bg-success", error = "bg-danger", running = "bg-warning text-dark", "bg-secondary")
    dot <- switch(st, ok = "dot-ok", error = "dot-err", running = "dot-running", "dot-idle")
    lbl <- switch(st, ok = "Ready to download", error = "Error", running = "Running...", stopped = "Stopped", "Idle")
    shiny::tags$span(class = paste("badge rounded-pill", cls), style = "font-size:.75rem;padding:5px 12px;",
                     shiny::tags$span(class = paste("dot", dot)), lbl)
  })

  dl_msg <- shiny::reactiveVal(NULL)
  output$cr_dl_msg <- shiny::renderUI({
    m <- dl_msg(); if (is.null(m)) return(NULL)
    shiny::div(class = "alert alert-danger p-2 mt-2 small", m)
  })

  make_dl <- function(kind) {
    shiny::downloadHandler(
      filename = function() cr_download_name(kind, input$cr_fmt %||% "csv", cr$label),
      content = function(file) {
        dl_msg(NULL)
        ok_to_go <- is_country() && identical(cr$status, "ok") && !is.null(cr$home) &&
          !is.null(cr$form) && auth$form_ok(cr$form)
        if (!ok_to_go) { writeLines(character(0), file); return(invisible()) }
        res <- cr_export(cr$home, kind, input$cr_fmt %||% "csv", file, cr$form)
        if (!isTRUE(res$ok)) {
          dl_msg(res$message)
          shiny::showNotification(paste("Download failed:", res$message), type = "error", duration = 10)
          writeLines(character(0), file)
        }
      })
  }
  output$cr_dl_clean <- make_dl("clean")
  output$cr_dl_raw   <- make_dl("raw")

  # Tidy up when the browser closes: stop the run, free the slot, delete the scratch files.
  session$onSessionEnded(function() {
    p <- shiny::isolate(cr$proc); home <- shiny::isolate(cr$home)
    if (!is.null(p)) tryCatch(p$kill_tree(), error = function(e) NULL)
    cr_release_slot(home); cr_discard(home)
  })

  invisible(cr)
}
