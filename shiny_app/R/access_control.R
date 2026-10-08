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
# Modes
#   open      neither secret is set  -> everybody is an admin (the legacy
#             behaviour; what a local run on the regional office PC gets).
#   enforced  at least one secret is set -> a code is required. Only a code
#             listed above is accepted; an unknown code never gets in.
#   If only IM_COUNTRY_CODES is set (no admin code) nobody can sign in as
#   admin -- it fails closed rather than silently opening the dashboard.
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

ac_mode <- function(admin_codes = ac_admin_codes(), country_codes = ac_country_codes()) {
  if (length(admin_codes) == 0L && length(country_codes) == 0L) "open" else "enforced"
}

# ── constant-time string comparison (no early exit on the first difference) ─
ac_ct_equal <- function(a, b) {
  ra <- as.integer(charToRaw(enc2utf8(a)))
  rb <- as.integer(charToRaw(enc2utf8(b)))
  n  <- max(length(ra), length(rb))
  diff <- as.integer(length(ra) != length(rb))
  if (n > 0L) {
    ra <- c(ra, rep(0L, n - length(ra)))
    rb <- c(rb, rep(0L, n - length(rb)))
    for (i in seq_len(n)) diff <- bitwOr(diff, bitwXor(ra[i], rb[i]))
  }
  diff == 0L
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
                            map           = ac_country_forms()) {
  code <- trimws(if (is.null(code)) "" else as.character(code)[1])
  if (is.na(code) || !nzchar(code)) return(NULL)

  if (ac_mode(admin_codes, country_codes) == "open")
    return(list(role = "admin", label = "Regional office (open access)",
                keys = NULL, countries = NULL, forms = NULL))

  is_admin <- FALSE
  for (ac in admin_codes) if (ac_ct_equal(code, ac)) is_admin <- TRUE
  hit <- NULL
  for (cc in country_codes) if (ac_ct_equal(code, cc$code) && is.null(hit)) hit <- cc

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
# Codes are long and random, so guessing is hopeless anyway; this just makes
# every failed attempt (across ALL sessions of this server process) a little
# slower the more failures there have been in the last 10 minutes (max 3 s),
# without ever locking a legitimate user out.
.ac_state <- new.env(parent = emptyenv())
.ac_state$fails <- numeric()
ac_throttle_failure <- function(now = Sys.time(), sleep = TRUE) {
  t <- as.numeric(now)
  recent <- c(.ac_state$fails[.ac_state$fails > t - 600], t)
  .ac_state$fails <- recent
  d <- min(3, 0.25 * length(recent))
  if (sleep && d > 0) Sys.sleep(d)
  d
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
# Creates the sign-in modal, the role-dependent UI (country users lose the
# Pipeline tab and the AI assistant) and output$auth_badge. Returns the
# reactive `user` plus the is_admin()/form_ok() checks the rest of the server
# uses to guard its handlers. `mode` is a parameter so tests can force it.
ac_session_init <- function(input, output, session, mode = ac_mode()) {
  user       <- shiny::reactiveVal(NULL)
  auth_fails <- shiny::reactiveVal(0L)

  show_login <- function(msg = NULL) {
    shiny::showModal(shiny::modalDialog(
      title = shiny::div(style = "font-weight:800;", "AFRO IM Dashboard"),
      shiny::p(style = "font-size:.85rem;color:#6C7A8D;",
               "Enter your access code to continue. Country users see their own country's data only."),
      shiny::passwordInput("auth_code", "Access code", width = "100%"),
      if (!is.null(msg)) shiny::div(class = "text-danger small mb-2", msg),
      shiny::tags$script(shiny::HTML(
        "$(document).off('keyup.acauth').on('keyup.acauth','#auth_code',function(e){if(e.which===13){$('#auth_submit').click();}});")),
      footer = shiny::actionButton("auth_submit", "Sign in", class = "btn-primary"),
      easyClose = FALSE, size = "s"
    ))
  }

  apply_role_ui <- function(u) {
    if (!ac_is_admin(u)) {
      # Country users: no Pipeline tab and no AI assistant (its tools read
      # pipeline files and run report scripts). Cosmetic only -- the server
      # handlers check the role as well.
      tryCatch(bslib::nav_remove("nav", "pipeline"), error = function(e) NULL)
      tryCatch({ shinyjs::hide("ai_fab"); shinyjs::hide("ai_panel") }, error = function(e) NULL)
    }
  }

  shiny::observeEvent(TRUE, {
    if (mode == "open") {
      u <- ac_authenticate("open", admin_codes = character(), country_codes = list())
      user(u); apply_role_ui(u)
    } else {
      show_login()
    }
  }, once = TRUE)

  shiny::observeEvent(input$auth_submit, {
    if (!is.null(user())) return()
    u <- ac_authenticate(input$auth_code)
    if (is.null(u)) {
      auth_fails(auth_fails() + 1L)
      ac_throttle_failure()
      if (auth_fails() >= 5L) {
        shiny::showModal(shiny::modalDialog(title = "Too many attempts",
          "Please reload the page and try again.", footer = NULL, easyClose = FALSE, size = "s"))
        session$close()
        return()
      }
      show_login("That access code is not recognised.")
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
        if (mode == "enforced")
          shiny::actionLink("auth_signout", "Sign out", style = "color:#fff;text-decoration:underline;"))
  })
  shiny::observeEvent(input$auth_signout, session$reload())

  list(user     = user,
       is_admin = function() ac_is_admin(user()),
       form_ok  = function(fid) ac_form_ok(user(), fid))
}
