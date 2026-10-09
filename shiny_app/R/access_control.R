# ============================================================
# ACCESS CONTROL  (in-app access codes: regional admin + one per country)
# ============================================================
# Auto-sourced by Shiny (shiny_app/R/). Pure functions only -- no reactive
# code lives here, so everything below can be unit-tested without a session
# (see tests/test_access_control.R). The session wiring is in app.R.
#
# Secrets (set in Posit Connect Cloud -> content -> Settings -> Secrets, or in
# config/secrets.env for a local run; NEVER commit them):
#
#   IM_ADMIN_CODES    one or more regional-admin codes, separated by ";"
#                       IM_ADMIN_CODES="K7M2-QX9P-4RTA;H3VN-8WDC-2ZLE"
#   IM_COUNTRY_CODES  "KEY=CODE" pairs separated by ";" -- KEY is the
#                     country_key column of config/country_forms.csv. A code
#                     may unlock several countries with "KEY1+KEY2=CODE".
#                       IM_COUNTRY_CODES="AGO=3FQD-9XKM-7TBW;NGA=Q8ZC-4HLP-6VSN"
#
# Modes (decided by ac_mode())
#   enforced      IM_ADMIN_CODES and/or IM_COUNTRY_CODES is set (even if badly
#                 formatted) -> a valid code is required. Only a code listed
#                 there is accepted; nothing else ever gets in.
#   open          nothing is set AND (the app runs on Windows -- the regional
#                 office PC -- OR IM_ACCESS_MODE=open is set explicitly) ->
#                 everybody is an admin (the legacy local behaviour). Setting
#                 any code secret always overrides IM_ACCESS_MODE=open.
#   unconfigured  nothing is set on a non-Windows server (e.g. Posit Connect
#                 Cloud) -> NOBODY can sign in. A missing/misnamed secret must
#                 never turn a public dashboard into an open one.
#   If only IM_COUNTRY_CODES is set (no admin code) nobody can sign in as
#   admin -- it fails closed rather than silently opening the dashboard.
#
# Code hygiene (ac_clean_config): codes shorter than 12 or longer than 128
# characters are ignored; a code listed for two countries is ignored for both;
# a country code equal to an admin code is ignored. Problems are written to the
# server log only (never shown to the user).
#
# Scoping is by the cleaned data's `country` column (full upper-case name,
# e.g. "DEMOCRATIC REPUBLIC OF THE CONGO"); the `source_file` column is only
# populated for some forms so it cannot be used. Raw-form access is scoped by
# form id via the same config/country_forms.csv.
# ============================================================

# ── country <-> form mapping ────────────────────────────────────────────────
ac_country_forms_path <- function() {
  cands <- c(file.path(CONFIG_DIR, "country_forms.csv"),
             file.path("..", "config", "country_forms.csv"),
             file.path("config", "country_forms.csv"))
  cands <- cands[file.exists(cands)]
  if (length(cands)) cands[1] else NA_character_
}

ac_country_forms <- function(path = ac_country_forms_path()) {
  empty <- data.frame(country_key = character(), country_name = character(),
                      form_id = character(), stringsAsFactors = FALSE)
  if (is.na(path) || !file.exists(path)) return(empty)
  df <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character"),
                 error = function(e) NULL)
  if (is.null(df) || !all(c("country_key", "country_name", "form_id") %in% names(df))) return(empty)
  df$country_key  <- toupper(trimws(df$country_key))
  df$country_name <- toupper(trimws(df$country_name))
  df$form_id      <- trimws(df$form_id)
  df[nzchar(df$country_key) & nzchar(df$country_name) & nzchar(df$form_id), , drop = FALSE]
}

# ── secrets parsing ─────────────────────────────────────────────────────────
ac_split <- function(x) {
  x <- gsub("[\r\n]+", ";", x)
  p <- trimws(strsplit(x, ";", fixed = TRUE)[[1]])
  p[nzchar(p)]
}

ac_admin_codes <- function(env = Sys.getenv("IM_ADMIN_CODES", "")) ac_split(env)

# Returns a list of list(keys = c("AGO", ...), code = "...").
ac_country_codes <- function(env = Sys.getenv("IM_COUNTRY_CODES", "")) {
  out <- list()
  for (p in ac_split(env)) {
    if (!grepl("=", p, fixed = TRUE)) next
    k    <- trimws(sub("=.*$", "", p))
    code <- trimws(sub("^[^=]*=", "", p))
    keys <- toupper(trimws(strsplit(k, "+", fixed = TRUE)[[1]]))
    keys <- keys[nzchar(keys)]
    if (length(keys) && nzchar(code)) out[[length(out) + 1L]] <- list(keys = keys, code = code)
  }
  out
}

AC_MIN_CODE_LEN <- 12L
AC_MAX_CODE_LEN <- 128L

ac_mode <- function(explicit    = Sys.getenv("IM_ACCESS_MODE", ""),
                    admin_raw   = Sys.getenv("IM_ADMIN_CODES", ""),
                    country_raw = Sys.getenv("IM_COUNTRY_CODES", ""),
                    os          = .Platform$OS.type) {
  if (nzchar(trimws(admin_raw)) || nzchar(trimws(country_raw))) return("enforced")
  if (identical(tolower(trimws(explicit)), "open")) return("open")
  if (identical(os, "windows")) return("open")
  "unconfigured"
}

# Drop unusable / ambiguous codes. Returns list(admin, country, problems).
ac_clean_config <- function(admin_codes = ac_admin_codes(), country_codes = ac_country_codes()) {
  problems <- character()
  len_ok <- function(x) nchar(x, type = "bytes") >= AC_MIN_CODE_LEN & nchar(x, type = "bytes") <= AC_MAX_CODE_LEN
  bad <- !len_ok(admin_codes)
  if (any(bad)) problems <- c(problems, sprintf("%d admin code(s) ignored (must be %d-%d characters)", sum(bad), AC_MIN_CODE_LEN, AC_MAX_CODE_LEN))
  admin <- unique(admin_codes[!bad])

  keep <- vapply(country_codes, function(cc) len_ok(cc$code), logical(1))
  if (length(keep) && any(!keep))
    problems <- c(problems, sprintf("%d country code(s) ignored (must be %d-%d characters)", sum(!keep), AC_MIN_CODE_LEN, AC_MAX_CODE_LEN))
  country <- country_codes[keep]

  if (length(country)) {
    codes <- vapply(country, function(cc) cc$code, character(1))
    dup <- codes %in% codes[duplicated(codes)]
    if (any(dup)) problems <- c(problems, sprintf("%d country code(s) ignored (same code used more than once)", sum(dup)))
    clash <- codes %in% admin
    if (any(clash)) problems <- c(problems, sprintf("%d country code(s) ignored (equal to an admin code)", sum(clash)))
    country <- country[!dup & !clash]
  }
  list(admin = admin, country = country, problems = problems)
}

# ── constant-time string comparison (no early exit on the first difference) ─
ac_ct_equal <- function(a, b) {
  ra <- as.integer(charToRaw(enc2utf8(a)))
  rb <- as.integer(charToRaw(enc2utf8(b)))
  n  <- max(length(ra), length(rb))
  if (n == 0L) return(TRUE)
  length(ra) <- n; length(rb) <- n
  ra[is.na(ra)] <- 0L; rb[is.na(rb)] <- 0L
  sum(bitwXor(ra, rb)) == 0L && length(charToRaw(enc2utf8(a))) == length(charToRaw(enc2utf8(b)))
}

# ── sign-in ─────────────────────────────────────────────────────────────────
# Returns NULL for a wrong code, otherwise
#   list(role = "admin"|"country", label, keys, countries, forms)
# `countries` = upper-case country names (match the `country` column),
# `forms` = form ids as character. Every candidate is compared (no early
# return) so response time does not reveal which entry matched.
ac_authenticate <- function(code,
                            admin_codes   = ac_admin_codes(),
                            country_codes = ac_country_codes(),
                            map           = ac_country_forms(),
                            mode          = ac_mode()) {
  code <- if (is.null(code)) "" else as.character(code)[1]
  if (is.na(code)) return(NULL)
  code <- trimws(code)
  if (!nzchar(code) || nchar(code, type = "bytes") > AC_MAX_CODE_LEN) return(NULL)

  if (identical(mode, "open"))
    return(list(role = "admin", label = "Regional office (open access)",
                keys = NULL, countries = NULL, forms = NULL))
  if (!identical(mode, "enforced")) return(NULL)             # unconfigured: nobody

  cfg <- ac_clean_config(admin_codes, country_codes)
  is_admin <- FALSE
  for (ac in cfg$admin) if (ac_ct_equal(code, ac)) is_admin <- TRUE
  hit <- NULL
  for (cc in cfg$country) if (ac_ct_equal(code, cc$code) && is.null(hit)) hit <- cc

  if (is_admin)
    return(list(role = "admin", label = "Regional office (admin)",
                keys = NULL, countries = NULL, forms = NULL))
  if (is.null(hit)) return(NULL)

  rows <- map[map$country_key %in% hit$keys, , drop = FALSE]
  if (!nrow(rows)) return(NULL)        # code configured for an unknown country key: refuse
  list(role      = "country",
       label     = paste(sort(unique(rows$country_name)), collapse = ", "),
       keys      = sort(unique(rows$country_key)),
       countries = sort(unique(rows$country_name)),
       forms     = sort(unique(rows$form_id)))
}

# ── brute-force slow-down ───────────────────────────────────────────────────
# Seconds a session must wait after its n-th wrong code (1, 2, 4, 8, 16, ...
# capped at 30). The wait is enforced by ignoring submissions (and disabling
# the button in the browser) -- the R process never sleeps, so a flood of bad
# codes cannot stall other users.
ac_lock_seconds <- function(n_fails) {
  if (is.na(n_fails) || n_fails < 1L) return(0)
  min(30, 2^(n_fails - 1L)) * getOption("ac.lock_scale", 1)     # the option exists only so tests need not wait
}

# ── data scoping ────────────────────────────────────────────────────────────
# Admin: untouched. Country: only rows of that country. Fails closed (NULL when
# nobody is signed in, zero rows when there is no usable `country` column).
ac_scope_data <- function(df, user) {
  if (is.null(df)) return(NULL)
  if (is.null(user)) return(NULL)
  if (identical(user$role, "admin")) return(df)
  if (!"country" %in% names(df) || !length(user$countries)) return(df[0, , drop = FALSE])
  keep <- !is.na(df$country) & toupper(trimws(df$country)) %in% toupper(user$countries)
  df[keep, , drop = FALSE]
}

ac_is_admin <- function(user) !is.null(user) && identical(user$role, "admin")

# May this user touch this raw form id? (admin: any; country: only own forms)
ac_form_ok <- function(user, form_id) {
  if (is.null(user) || is.null(form_id) || length(form_id) != 1L || is.na(form_id)) return(FALSE)
  if (identical(user$role, "admin")) return(TRUE)
  as.character(form_id) %in% as.character(user$forms)
}

# ── per-session wiring (called once from the Shiny server function) ──────────
# Creates the sign-in modal, the role-dependent UI (country users get the "My data"
# version of the Pipeline tab and no AI assistant) and output$auth_badge. Returns the
# reactive `user` plus the is_admin()/form_ok() checks the rest of the server
# uses to guard its handlers. `mode` is a parameter so tests can force it.
ac_session_init <- function(input, output, session, mode = ac_mode()) {
  user       <- shiny::reactiveVal(NULL)
  auth_fails <- shiny::reactiveVal(0L)
  lock_until <- 0                      # per-session; plain variable (not reactive) on purpose

  # Errors must never leak file paths / internals to a visitor of a shared dashboard.
  if (!identical(mode, "open")) options(shiny.sanitize.errors = TRUE)
  if (!identical(mode, "open")) {
    probs <- tryCatch(ac_clean_config()$problems, error = function(e) "access configuration could not be read")
    if (identical(mode, "unconfigured"))
      probs <- c(probs, "no IM_ADMIN_CODES / IM_COUNTRY_CODES set: sign-in is disabled (set the secrets, or IM_ACCESS_MODE=open)")
    for (p in probs) message("[access] ", p)
  }

  show_login <- function(msg = NULL, locked_secs = 0) {
    if (identical(mode, "unconfigured")) {
      shiny::showModal(shiny::modalDialog(
        title = shiny::div(style = "font-weight:800;", "AFRO IM Dashboard"),
        shiny::p("Access has not been configured on this server yet. Please contact the regional office."),
        footer = NULL, easyClose = FALSE, size = "s"))
      return(invisible())
    }
    shiny::showModal(shiny::modalDialog(
      title = shiny::div(style = "font-weight:800;", "AFRO IM Dashboard"),
      shiny::p(style = "font-size:.85rem;color:#6C7A8D;",
               "Enter your access code to continue. Country users see their own country's data only."),
      shiny::passwordInput("auth_code", "Access code", width = "100%"),
      if (!is.null(msg)) shiny::div(class = "text-danger small mb-2", msg),
      shiny::tags$script(shiny::HTML(
        "$(document).off('keyup.acauth').on('keyup.acauth','#auth_code',function(e){if(e.which===13){$('#auth_submit').click();}});")),
      if (locked_secs > 0) shiny::tags$script(shiny::HTML(sprintf(
        "$('#auth_submit').prop('disabled',true);setTimeout(function(){$('#auth_submit').prop('disabled',false);},%d);",
        as.integer(ceiling(locked_secs) * 1000)))),
      footer = shiny::actionButton("auth_submit", "Sign in", class = "btn-primary"),
      easyClose = FALSE, size = "s"
    ))
  }

  apply_role_ui <- function(u) {
    if (!ac_is_admin(u)) {
      # Country users: the Pipeline tab turns into "My data" -- the admin controls
      # are hidden, their own fetch/clean/download panel is shown -- and the AI
      # assistant is hidden (its tools read pipeline files and run report scripts).
      # Cosmetic only: the server handlers check the role as well.
      tryCatch({
        shinyjs::hide("pl_admin_block")
        shinyjs::show("pl_country_block")
        shinyjs::runjs(paste0(
          "var a=document.querySelector('a.nav-link[data-value=\"pipeline\"]');",
          "if(a){a.textContent='My data';}"))
      }, error = function(e) NULL)
      tryCatch({ shinyjs::hide("ai_fab"); shinyjs::hide("ai_panel") }, error = function(e) NULL)
      # Land on the country's own page ("My data"), not on the Overview tab.
      tryCatch(bslib::nav_select("nav", "pipeline", session = session), error = function(e) NULL)
    }
  }

  shiny::observeEvent(TRUE, {
    if (identical(mode, "open")) {
      u <- ac_authenticate("open", admin_codes = character(), country_codes = list(), mode = "open")
      user(u); apply_role_ui(u)
    } else {
      show_login()
    }
  }, once = TRUE)

  shiny::observeEvent(input$auth_submit, {
    if (!is.null(user())) return()
    if (!identical(mode, "enforced")) return()           # open: no sign-in; unconfigured: nobody
    now <- as.numeric(Sys.time())
    if (now < lock_until) return()                       # still locked: ignore, do no work
    u <- ac_authenticate(input$auth_code, mode = mode)
    if (is.null(u)) {
      auth_fails(auth_fails() + 1L)
      if (auth_fails() >= 5L) {
        shiny::showModal(shiny::modalDialog(title = "Too many attempts",
          "Please reload the page and try again.", footer = NULL, easyClose = FALSE, size = "s"))
        session$close()
        return()
      }
      secs <- ac_lock_seconds(auth_fails())
      lock_until <<- now + secs
      show_login("That access code is not recognised.", locked_secs = secs)
      return()
    }
    user(u)
    shiny::removeModal()
    apply_role_ui(u)
  })

  output$auth_badge <- shiny::renderUI({
    u <- user(); if (is.null(u)) return(NULL)
    shiny::div(class = "d-flex align-items-center gap-2",
        style = "color:#fff;font-size:.78rem;",
        shiny::tags$span(style = "opacity:.9;max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;",
                  title = u$label,
                  if (ac_is_admin(u)) "Regional office" else u$label),
        if (identical(mode, "enforced"))
          shiny::actionLink("auth_signout", "Sign out", style = "color:#fff;text-decoration:underline;"))
  })
  shiny::observeEvent(input$auth_signout, session$reload())

  list(user     = user,
       is_admin = function() ac_is_admin(user()),
       form_ok  = function(fid) ac_form_ok(user(), fid))
}
