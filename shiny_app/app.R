# ── PACKAGES, PATHS, CREDENTIALS & PALETTE ── moved to R/00_globals.R (auto-sourced by Shiny; defines BASE_DIR, WORKFLOW_DIR, SCRIPTS_DIR, FINAL_DIR, LOGS_DIR, REPORTS_DIR, CONFIG_DIR, AI_ASSISTANT_ENABLED, CLEANED_RDS, CLEANED_PARQUET, CLEANED_CSV, RAW_RDS, C_) ──

# ── CUSTOM CSS & JS ── moved to R/constants_css_js.R (auto-sourced by Shiny; defines CSS, JS) ──

# ── DATA LOADING & HELPERS ── moved to R/data_helpers.R (auto-sourced by Shiny; defines load_im_data, fmt_pct, fmt_num, date_col_of, get_log_lines, last_run_info, %+%) ──


# ── UI COMPONENT HELPERS ── moved to R/ui_helpers.R (auto-sourced by Shiny; defines kpi, plotly_base, im_layout, dl_btn, hdr_icon) ──

# ── RISK SCORING ── moved to R/risk_scoring.R (auto-sourced by Shiny; defines with_risk) ──

# ── AI ASSISTANT SYSTEM PROMPT ── moved to R/ai_system_prompt.R (auto-sourced by Shiny; defines IM_SYSTEM_PROMPT) ──

# ── AI ASSISTANT DATA HELPERS & TOOLS ── moved to R/ai_assistant_tools.R (auto-sourced by Shiny; defines im_filter_scope, im_kpi_summary_text, im_top_risk_text, im_trend_text, build_im_ai_tools) ──

who_theme <- bs_theme(
  version=5, bg="#F0F4F8", fg="#1A2637",
  primary="#005C97", secondary="#6C7A8D",
  success="#27AE60", warning="#E8730A", danger="#C0392B",
  base_font    = font_google("Inter"),
  heading_font = font_google("Inter", wght="700"),
  "navbar-bg"="#003F6B"
)

# ── AI ASSISTANT WIDGET UI ── moved to R/ai_assistant_tools.R (auto-sourced by Shiny; defines ai_assistant_widget_ui) ──

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- page_navbar(
  title = div(
    style="display:flex;align-items:center;gap:12px;",
    bs_icon("globe-europe-africa", size="1.5rem", style="color:#fff;"),
    div(
      div(style="color:#fff;font-weight:800;font-size:1.05rem;letter-spacing:-.01em;",
          "AFRO IM Dashboard"),
      div(style="color:rgba(255,255,255,.55);font-size:.68rem;font-weight:500;letter-spacing:.05em;margin-top:-2px;",
          "WHO AFRO INDEPENDENT MONITORING")
    )
  ),
  theme  = who_theme, id = "nav",
  header = tagList(
    useShinyjs(),
    tags$head(
      tags$style(HTML(CSS)),
      tags$script(HTML(JS)),
      tags$link(
        rel="stylesheet",
        href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&display=swap"
      ),
      # html2canvas: powers the "📷 PNG" export of the Executive KPI Snapshot
      # (client-side DOM screenshot — needs the browser to reach this CDN)
      tags$script(src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js")
    )
  ),
  footer = ai_assistant_widget_ui(),

  # ── TAB 1 : EXPLORER ────────────────────────────────────────────────────────
  nav_panel(hdr_icon("search", "Explorer"),

    layout_sidebar(
      sidebar = sidebar(
        width=275, open=TRUE,
        div(class="sec-title", style="color:#fff;font-size:.95rem;margin-bottom:14px;",
            hdr_icon("funnel-fill", "Filters")),

        selectInput("f_block",   "AFRO Block",   c("All","LCB","WA","DRC","CEA","ESA")),
        selectInput("f_country", "Country",       "All"),
        selectInput("f_vaccine", "Vaccine Type",  "All"),
        selectInput("f_resp",    "Response",      "All"),
        dateRangeInput("f_dates","Date Range",
                       start=Sys.Date()-365, end=Sys.Date()),
        selectInput("f_qc","QC Status", c("All","Clean only","Flagged only")),

        hr(),
        div(class="d-grid gap-2",
          actionButton("btn_apply", hdr_icon("search", "Apply Filters"), class="btn-primary"),
          actionButton("btn_reset", hdr_icon("arrow-counterclockwise", "Reset"), class="btn-outline-secondary btn-sm")
        ),
        hr(),
        div(class="d-grid",
          downloadButton("dl_csv", tagList(bs_icon("download", class="me-1"), "Download CSV"), class="btn-outline-success btn-sm"))
      ),

      layout_columns(
        col_widths=c(6,6), gap="14px",
        card(full_screen=TRUE,
             card_header(hdr_icon("bullseye", "CV vs Missed Children")),
             plotlyOutput("chart_scatter", height="320px")),
        card(full_screen=TRUE,
             card_header(hdr_icon("bar-chart-steps", "Top Missed-Child Reasons")),
             plotlyOutput("chart_reasons", height="320px"))
      ),

      card(
        full_screen=TRUE,
        card_header(
          div(class="d-flex align-items-center gap-3",
            hdr_icon("clipboard-data-fill", "Records"),
            tags$span(class="badge",
                      style="background:rgba(0,92,151,.1);color:#005C97;font-weight:700;",
                      textOutput("rec_count", inline=TRUE))
          )
        ),
        DTOutput("data_tbl")
      )
    )
  ),

  # ── TAB 2 : QC MONITOR ──────────────────────────────────────────────────────
  nav_panel(hdr_icon("shield-check", "QC"),

    div(class="sec-title mb-1","Quality Control Monitor"),
    div(class="sec-sub mb-4","Flags from denominator checks, reconciliation, and social mobilization analytics"),

    div(class="row row-cols-2 row-cols-md-4 g-3 mb-2",
      div(class="col", div(class="fade-up d1", kpi("qv_denom",  "Denominator Issues",bs_icon("exclamation-circle-fill"),"kpi-red",   "", trend="flags"))),
      div(class="col", div(class="fade-up d2", kpi("qv_review", "Needs Review",      bs_icon("eye-fill"),"kpi-orange","", trend="review"))),
      div(class="col", div(class="fade-up d3", kpi("qv_sm_pri", "SM Priority Flags", bs_icon("megaphone-fill"),"kpi-purple","", trend="SM"))),
      div(class="col", div(class="fade-up d4", kpi("qv_sm_gap", "SM Gap Flags",      bs_icon("bar-chart-fill"),"kpi-teal",  "", trend="gaps")))
    ),

    br(),

    layout_columns(
      col_widths=c(6,6), gap="14px",
      card(full_screen=TRUE,
           card_header(hdr_icon("bar-chart-fill", "QC Flags by Type")),
           plotlyOutput("chart_qc_bar", height="300px")),
      card(full_screen=TRUE,
           card_header(hdr_icon("globe-europe-africa", "SM Gap Flags by Country")),
           plotlyOutput("chart_sm_gap_bar", height="300px"))
    ),

    card(
      full_screen=TRUE,
      card_header(hdr_icon("exclamation-triangle-fill", "Flagged Records")),
      layout_columns(
        col_widths=c(4,4,4),
        selectInput("qc_type","Flag Type",
                    c("All flags","Denominator issues","Needs review","SM gaps")),
        selectInput("qc_cntry","Country","All"),
        div()
      ),
      DTOutput("qc_tbl")
    )
  ),

  # ── TAB 3 : PIPELINE ────────────────────────────────────────────────────────
  nav_panel(hdr_icon("gear-fill", "Pipeline"), value = "pipeline",

    # Country users see this block (R/country_run.R) instead of the admin controls
    # below; shown/hidden per role by ac_session_init() (R/access_control.R).
    div(id = "pl_country_block", style = "display:none;", cr_ui()),

    div(id = "pl_admin_block",
    layout_columns(
      col_widths=c(3,9), gap="14px",

      card(
        card_header(hdr_icon("sliders", "Controls")),
        card_body(
          div(class="d-grid gap-2",
            actionButton("run_all",    hdr_icon("play-fill", "Run Full Pipeline"), class="btn-success btn-lg"),
            shinyjs::disabled(
              actionButton("btn_stop", hdr_icon("stop-fill", "Stop"), class="btn-outline-danger btn-lg")
            ),
            tags$hr(style="border-color:rgba(0,0,0,.08);margin:4px 0;"),
            actionButton("run_fetch",  hdr_icon("cloud-download-fill",       "1. Fetch Data"),        class="btn-outline-primary"),
            actionButton("run_build",  hdr_icon("database-fill-gear",        "2. Build Repository"),  class="btn-outline-primary"),
            actionButton("run_clean",  hdr_icon("eraser-fill",               "3. Clean Geonames"),    class="btn-outline-primary"),
            actionButton("run_rpts",   hdr_icon("file-earmark-bar-graph-fill","4. Generate Reports & Deck"), class="btn-outline-primary"),
            actionButton("run_upload", hdr_icon("cloud-arrow-up-fill",       "5. Upload SharePoint"), class="btn-outline-primary"),
            tags$hr(style="border-color:rgba(0,0,0,.08);margin:4px 0;"),
            actionButton("btn_rl_data", hdr_icon("arrow-repeat", "Reload Data"),  class="btn-outline-success btn-sm"),
            actionButton("btn_rl_log",  hdr_icon("arrow-repeat", "Refresh Log"),  class="btn-outline-secondary btn-sm")
          )
        )
      ),

      card(
        card_header(
          div(class="d-flex align-items-center gap-3",
            hdr_icon("broadcast", "Pipeline Status"),
            uiOutput("status_badge")
          )
        ),
        div(class="p-3", uiOutput("step_pills")),
        tags$pre(
          id="log_pre",
          style="height:430px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;",
          textOutput("log_txt", inline=TRUE)
        )
      )
    )
    ),

    card(
      card_header(hdr_icon("cloud-download-fill", "Download Raw Form Data")),
      card_body(
        div(class="info-banner mb-3",
          tags$b("Source:"), tags$code("raw_state"),
          " — pulls a form's raw data directly from SharePoint. Forms too large for one Excel sheet are automatically split into one file per year (zipped). Pick a specific Year, Response, and/or Round Number to narrow the download down to just that slice instead of every record for the form — any of the three can be combined, and setting any of them always returns a single file (never a zip)."),
        # Plain Bootstrap row/col (flexbox), not bslib's layout_columns()
        # (CSS Grid) -- two selectize widgets side by side inside a
        # layout_columns() grid cell were overlapping/overflowing their
        # column (a known bslib-grid + selectize interaction issue,
        # especially on a tab that isn't the one active at page load).
        # A plain .row/.col-* pair is the same layout every other
        # side-by-side filter row in this app already uses successfully.
        # All five filters share one row -- `col-md` with no number gives
        # Bootstrap's equal-width flex columns, so they split the row evenly
        # regardless of count, rather than needing fractions that divide the
        # 12-column grid cleanly. Still stacks to one-per-line below `md`.
        div(class="row gx-3 gy-2 mb-3",
          div(class="col-12 col-md",
            selectInput("dl_raw_form_id", "Form ID", choices = NULL, width = "100%")),
          div(class="col-12 col-md dl-raw-cascade-field",
            # Repopulated reactively (server-side) with that form's actual
            # years the moment a Form ID is picked -- see the
            # output$dl_raw_year_ui <- renderUI({...}) block below, which
            # calls R/data_download_raw.R's list_available_years(). That
            # function deliberately works the same way for every form,
            # heavy (year-partitioned) or not -- unlike the now-removed
            # list_partition_years()-only version of this dropdown, it
            # doesn't leave a non-heavy form stuck offering nothing but
            # "All years" to pick from; it reads the real years out of that
            # form's own combined file instead (cheaply -- see that
            # function's own comment on why that's an acceptable cost only
            # for a non-heavy form). create = TRUE still lets someone type a
            # year outside the pre-populated list (e.g. one so new the
            # lookup hasn't caught up with it yet).
            #
            # "All years" uses the sentinel value "__ALL__", never "" -- an
            # empty string doubles as jQuery/selectize's own "nothing is
            # selected" value, which caused the box to render completely
            # blank (no text, no placeholder) once a value changed. A real,
            # non-empty sentinel avoids that ambiguous state entirely.
            #
            # Rendered via uiOutput()/renderUI(), same as Response/Round
            # Number below, rather than a single long-lived selectizeInput()
            # kept in sync with updateSelectizeInput() -- see those widgets'
            # own comment for why (avoids any possibility of a previous
            # form's leftover options surviving a switch), and it's what
            # makes the "Refreshing…" cue (CSS, R/constants_css_js.R) show
            # up here too: Shiny only adds its automatic 'recalculating'
            # class to a renderUI()-backed output, not to a plain
            # updateSelectizeInput()-driven one.
            uiOutput("dl_raw_year_ui")),
          div(class="col-12 col-md",
            selectInput("dl_raw_format", "Format",
                        c("CSV" = "csv", "Excel (.xlsx)" = "xlsx",
                          "R data (.rds)" = "rds", "Parquet" = "parquet"),
                        width = "100%")),
          # Response / Round Number: cascading selectizeInputs, same
          # "__ALL__" sentinel pattern as Year above (never "" -- see that
          # widget's own comment on why an empty string is the wrong choice
          # here). Response's choices are the real, distinct Response values
          # for the selected Form ID + Year (R/data_download_raw.R's
          # list_available_responses()); Round Number's choices are the
          # real, distinct roundNumber values for the selected Form ID +
          # Year + Response (list_available_rounds()) -- each level reads
          # only the narrow set of columns it needs
          # (.load_narrow_columns()/.read_parquet_cols()), matched
          # case-insensitively (.find_column_ci()/.filter_df_by_field()),
          # rather than eagerly loading every column of a form just to
          # populate a dropdown.
          #
          # Rendered via uiOutput()/renderUI() (server block below) rather
          # than a single long-lived selectizeInput() updated in place with
          # updateSelectizeInput() -- a real cross-form mix-up was observed
          # in production with the update-in-place approach (switching Form
          # ID after browsing a different form could leave a previous
          # form's Response options still showing in the dropdown alongside
          # the new form's, a known category of staleness with
          # updateSelectizeInput()+create=TRUE not fully clearing a
          # selectize widget's rendered option list). Rebuilding the whole
          # widget from scratch -- a brand new <select> element and a brand
          # new selectize.js instance -- every time Form ID, Year, or
          # Response changes leaves no old DOM/JS state behind to leak into
          # the next form, at the cost of a very small amount of extra
          # render work each time (the same SharePoint lookup either way).
          div(class="col-12 col-md dl-raw-cascade-field", uiOutput("dl_raw_response_ui")),
          div(class="col-12 col-md dl-raw-cascade-field", uiOutput("dl_raw_round_ui"))
        ),
        div(class="d-grid",
          downloadButton("dl_raw_form", hdr_icon("download", "Download"), class="btn-outline-primary")),
        uiOutput("dl_raw_status"),
        # Live step-by-step log for the download build (auth, resolve
        # library, per-file download/zip, ...) -- filled via the
        # dlRawLogLine/dlRawLogClear custom messages (R/constants_css_js.R)
        # from inside the downloadHandler below, the same "push straight to
        # the browser, don't wait for a reactive flush" trick countUp()
        # already relies on, since content() runs as one long synchronous
        # call. Styled like the Pipeline tab's own #log_pre, just shorter.
        tags$pre(
          id = "dl_raw_log_pre",
          style = "height:110px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;margin-top:10px;"
        )
      )
    )
  ),

  # Who is signed in (+ Sign out) -- filled by output$auth_badge in the server.
  nav_spacer(),
  nav_item(uiOutput("auth_badge"))
)

# ── SERVER ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  rv <- reactiveValues(
    data           = NULL,
    report_builder = NULL   # in-progress AI-generated report/deck, if any (see R/ai_report_builder.R)
  )

  # ── Access control (R/access_control.R) ─────────────────────────────────────
  # Nothing is loaded and no admin action is accepted until `user()` is set by
  # a valid access code. Hiding UI is only a convenience for country users:
  # every admin handler and every raw-form handler below ALSO checks the role
  # on the server, so a hand-crafted request cannot get around the UI.
  auth        <- ac_session_init(input, output, session)   # sign-in modal, role UI, auth_badge
  user        <- auth$user
  is_admin    <- auth$is_admin
  form_ok     <- auth$form_ok
  # Every load of the cleaned repository goes through here, so a country user
  # only ever holds their own country's rows in memory.
  load_scoped <- function() { if (is.null(user())) return(NULL); ac_scope_data(load_im_data(), user()) }
  # "My data" tab for country users: fetch -> process -> clean in a private scratch
  # folder with SharePoint writes disabled, download only (R/country_run.R).
  cr_session_init(input, output, session, auth, source_home = BASE_DIR)

  # ── Fix: plotly charts render squished on tabs that weren't visible yet ─────
  # A plotlyOutput inside a nav_panel that isn't the active tab starts life at
  # display:none, so Plotly measures a 0-width container the first time it
  # draws and never recovers on its own. Firing a window resize event right
  # after a tab becomes visible (Bootstrap's `input$nav` changes) makes every
  # plotly chart already on that tab recompute its real size. This is what
  # made Explorer/QC look "squished" while the first tab (the initially active
  # tab) rendered fine.
  observeEvent(input$nav, {
    shinyjs::delay(50, shinyjs::runjs("window.dispatchEvent(new Event('resize'));"))
  }, ignoreInit = TRUE)

  # ── AI Assistant chat client ────────────────────────────────────────────────
  # One ellmer Chat object per session (conversation state lives here), with
  # its tools closing over this session's `rv` so answers reflect whatever
  # this user currently has loaded. Wrapped in tryCatch so a bad/missing key
  # or an API-side error surfaces as a chat message instead of crashing the app.
  if (AI_ASSISTANT_ENABLED) {
    ai_chat_client <- tryCatch({
      # Pinning the model explicitly (same one ellmer was defaulting to)
      # stops it from printing "Using model = ..." to the console every time
      # the dashboard starts.
      client <- ellmer::chat_anthropic(system_prompt = IM_SYSTEM_PROMPT,
                                        model = "claude-sonnet-4-5-20250929")
      for (tl in build_im_ai_tools(rv)) client$register_tool(tl)
      client
    }, error = function(e) {
      warning("AI Assistant: failed to initialize Anthropic client — ", conditionMessage(e))
      NULL
    })

    observeEvent(input$ai_chat_user_input, {
      if (!is_admin()) {
        shinychat::chat_append("ai_chat", "The assistant is available to the regional office only.")
        return()
      }
      if (is.null(ai_chat_client)) {
        shinychat::chat_append("ai_chat",
          "The AI Assistant couldn't start — check that ANTHROPIC_API_KEY in config/secrets.env is a valid key, then restart the app.")
        return()
      }
      tryCatch({
        stream <- ai_chat_client$stream_async(input$ai_chat_user_input)
        shinychat::chat_append("ai_chat", stream)
      }, error = function(e) {
        shinychat::chat_append("ai_chat",
          paste0("Sorry, I couldn't reach the AI service just now (",
                 conditionMessage(e), "). Please try again in a moment."))
      })
    })
  }

  # ── Load on startup ──────────────────────────────────────────────────────────
  observe({
    req(user())
    rv$data <- load_scoped()
    req(rv$data)
    df <- rv$data

    ctrs <- sort(unique(df$country[!is.na(df$country)]))
    vacs <- sort(unique(df$vaccine_type[!is.na(df$vaccine_type)]))
    resp <- sort(unique(df$response[!is.na(df$response)]))

    updateSelectInput(session, "f_country",  choices=c("All", ctrs))
    updateSelectInput(session, "f_vaccine",  choices=c("All", vacs))
    updateSelectInput(session, "f_resp",     choices=c("All", resp))
    updateSelectInput(session, "qc_cntry",   choices=c("All", ctrs))

    # Country users: the AFRO Block filters list only the block(s) their own country belongs to.
    if (!is_admin() && "afro_block" %in% names(df)) {
      blks <- sort(unique(as.character(df$afro_block[!is.na(df$afro_block) & nzchar(as.character(df$afro_block))])))
      updateSelectInput(session, "f_block",  choices = c("All", blks), selected = "All")
    }

    dc <- date_col_of(df)
    if (!is.na(dc)) {
      v <- as.Date(df[[dc]]); v <- v[!is.na(v)]
      if (length(v)) updateDateRangeInput(session,"f_dates", start=min(v), end=max(v))
    }
  })

  # %||% helper
  `%||%` <- function(a,b) if (!is.null(a)) a else b

  observeEvent(input$btn_rl_data, {
    rv$data <- load_scoped(); showNotification("Data reloaded.", type="message")
  })

  # ── Filtering ────────────────────────────────────────────────────────────────
  filtered <- eventReactive(list(input$btn_apply, rv$data), {
    df <- rv$data; if (is.null(df)) return(NULL)

    block_val <- input$f_block
    if (!is.null(block_val) && block_val!="All" && "afro_block" %in% names(df))
      df <- df[!is.na(df$afro_block) & df$afro_block==block_val, ]

    cntry_val <- input$f_country
    if (!is.null(cntry_val) && cntry_val!="All" && "country" %in% names(df))
      df <- df[!is.na(df$country) & df$country==cntry_val, ]

    vac_val <- input$f_vaccine
    if (!is.null(vac_val) && vac_val!="All" && "vaccine_type" %in% names(df))
      df <- df[!is.na(df$vaccine_type) & df$vaccine_type==vac_val, ]

    resp_val <- input$f_resp
    if (!is.null(resp_val) && resp_val!="All" && "response" %in% names(df))
      df <- df[!is.na(df$response) & df$response==resp_val, ]

    dc <- date_col_of(df)
    if (!is.na(dc)) {
      d <- as.Date(df[[dc]])
      df <- df[!is.na(d) & d>=input$f_dates[1] & d<=input$f_dates[2], ]
    }

    qc_val <- input$f_qc
    if (!is.null(qc_val) && qc_val!="All" && "qc_flag" %in% names(df)) {
      if (qc_val=="Clean only")   df <- df[!is.na(df$qc_flag) & df$qc_flag=="OK", ]
      if (qc_val=="Flagged only") df <- df[!is.na(df$qc_flag) & df$qc_flag!="OK", ]
    }
    df
  }, ignoreNULL=FALSE)

  active <- reactive({ fd <- filtered(); if (!is.null(fd)) fd else rv$data })

  # ── Dynamic country list based on selected AFRO Block ───────────────────────
  observeEvent(input$f_block, {
    req(rv$data)
    df <- rv$data
    if (!"country" %in% names(df)) return()

    if (input$f_block == "All" || !"afro_block" %in% names(df)) {
      ctrs <- sort(unique(df$country[!is.na(df$country)]))
    } else {
      ctrs <- df %>%
        filter(afro_block == input$f_block, !is.na(country)) %>%
        pull(country) %>% unique() %>% sort()
    }

    updateSelectInput(session, "f_country",
                      choices  = c("All", ctrs),
                      selected = "All")
  }, ignoreInit = TRUE)

  observeEvent(input$btn_reset, {
    updateSelectInput(session, "f_block",   selected="All")
    updateSelectInput(session, "f_vaccine", selected="All")
    updateSelectInput(session, "f_resp",    selected="All")
    updateSelectInput(session, "f_qc",      selected="All")
    # Restore full country list
    req(rv$data)
    ctrs <- sort(unique(rv$data$country[!is.na(rv$data$country)]))
    updateSelectInput(session, "f_country", choices=c("All", ctrs), selected="All")
  })

  # ── Pipeline step pills ──────────────────────────────────────────────────────
  output$pipeline_steps <- renderUI({
    steps <- list(
      list(label="1. Clean Data",             script="run_workflow.R"),
      list(label="2. Intelligence Engine",     script="afro_im_intilligence_analysis_engine.R"),
      list(label="3. Generate Report",         script="AFRO_Advocacy_Intelligence_Report.R"),
      list(label="4. Build Deck",              script="afro_region_im_deck_generation.R"),
      list(label="5. Upload SharePoint",       script="upload_to_sharepoint.py")
    )
    pills <- lapply(steps, function(s)
      tags$span(class="step-pill step-pending", s$label))
    do.call(div, c(list(class="step-pills-row"), pills))
  })

  # ═══════════════════════════════════════════════════════════════════════════
  # EXPLORER TAB
  # ═══════════════════════════════════════════════════════════════════════════

  output$rec_count <- renderText({
    df <- active(); if (is.null(df)) return("0")
    fmt_num(nrow(df))
  })

  output$chart_scatter <- renderPlotly({
    df <- active(); req(df)
    if (!all(c("u5_fm","u5_present") %in% names(df))) return(NULL)
    df2 <- df %>%
      mutate(cv = as.numeric(u5_fm) / pmax(as.numeric(u5_present), 1),
             missed = pmax(as.numeric(u5_present) - as.numeric(u5_fm), 0)) %>%
      filter(!is.na(cv))
    grp <- intersect(c("country","afro_block"), names(df2))[1]
    col_var <- if (!is.na(grp)) df2[[grp]] else rep("All", nrow(df2))
    plot_ly(df2, x=~cv, y=~missed, type="scatter", mode="markers",
            color=col_var,
            marker=list(size=7, opacity=0.7, line=list(width=0)),
            text=if (!is.na(grp)) ~.data[[grp]] else NULL,
            hovertemplate="CV: %{x:.1%}<br>Missed: %{y:,}<extra></extra>") %>%
      im_layout(.title="CV vs Missed Children", .filename="IM_scatter",
                xaxis=list(title="Coverage Rate", tickformat=".0%"),
                yaxis=list(title="Missed Children"))
  })

  output$chart_reasons <- renderPlotly({
    df <- active(); req(df)
    rcols <- grep("^r_non_fm_|^r_non_", names(df), value=TRUE)
    rcols <- rcols[sapply(df[,rcols,drop=FALSE], is.numeric)]
    if (!length(rcols)) return(
      plotly_empty() %>% im_layout() %>%
        add_annotations(text="No reason columns found", showarrow=FALSE,
                        font=list(size=13, color=C_$muted))
    )
    tots <- sort(colSums(df[,rcols,drop=FALSE], na.rm=TRUE), decreasing=TRUE)
    tots <- tots[tots > 0][seq_len(min(10, length(tots)))]
    lbl  <- sub("^r_non_fm_|^r_non_","", names(tots))
    tbl  <- data.frame(reason=lbl, n=as.numeric(tots))
    plot_ly(tbl, x=~n, y=~reorder(reason,n), type="bar", orientation="h",
            marker=list(color=C_$blue, line=list(width=0)),
            hovertemplate="%{y}: %{x:,}<extra></extra>") %>%
      im_layout(.title="Top Missed-Child Reasons", .filename="IM_reasons",
                xaxis=list(title="Missed Children"),
                yaxis=list(title=""), margin=list(l=140,r=60,t=46,b=30))
  })

  output$data_tbl <- DT::renderDT({
    df <- active(); req(df)
    show_cols <- intersect(c("country","province","district","roundnumber",
                             "vaccine_type","response","u5_present","u5_fm",
                             "qc_flag","reconciliation_flag"),
                           names(df))
    DT::datatable(df[, show_cols, drop=FALSE],
      options=list(pageLength=15, scrollX=TRUE,
                   dom="Bfrtip", buttons=c("csv","excel")),
      rownames=FALSE, filter="top",
      class="table table-sm table-striped")
  })

  output$dl_csv <- downloadHandler(
    filename=function() paste0("IM_explorer_",Sys.Date(),".csv"),
    content =function(f) write.csv(active() %||% data.frame(), f, row.names=FALSE))

  # ═══════════════════════════════════════════════════════════════════════════
  # QC TAB
  # ═══════════════════════════════════════════════════════════════════════════

  qc_data <- reactive({
    df <- rv$data; if (is.null(df)) return(NULL)
    df
  })

  observe({
    df <- qc_data(); if (is.null(df)) return()

    denom_flag <- if ("qc_flag" %in% names(df))
      sum(grepl("denom|denominator", df$qc_flag, ignore.case=TRUE), na.rm=TRUE) else 0
    review_flag <- if ("qc_flag" %in% names(df))
      sum(grepl("review", df$qc_flag, ignore.case=TRUE), na.rm=TRUE) else 0
    sm_pri <- if ("sm_priority_flag" %in% names(df))
      sum(df$sm_priority_flag == 1, na.rm=TRUE) else 0
    sm_gap <- if ("sm_gap_flag" %in% names(df))
      sum(df$sm_gap_flag == 1, na.rm=TRUE) else 0

    session$sendCustomMessage("countUp", list(id="qv_denom",  v=denom_flag,  ms=700))
    session$sendCustomMessage("countUp", list(id="qv_review", v=review_flag, ms=700))
    session$sendCustomMessage("countUp", list(id="qv_sm_pri", v=sm_pri,      ms=700))
    session$sendCustomMessage("countUp", list(id="qv_sm_gap", v=sm_gap,      ms=700))
  })

  output$chart_qc_bar <- renderPlotly({
    df <- qc_data(); req(df)
    qc_col <- intersect(c("qc_flag","reconciliation_flag"), names(df))[1]
    if (is.na(qc_col)) return(NULL)
    tbl <- df %>% count(flag=.data[[qc_col]]) %>% filter(!is.na(flag)) %>% arrange(desc(n))
    pal <- case_when(tbl$flag=="OK"~C_$green,
                     grepl("review",tbl$flag,ignore.case=TRUE)~C_$orange, TRUE~C_$red)
    plot_ly(tbl, x=~flag, y=~n, type="bar",
            marker=list(color=pal, line=list(width=0)),
            hovertemplate="%{x}: %{y:,}<extra></extra>") %>%
      im_layout(.title="QC Flags by Type", .filename="IM_qc_bar",
                xaxis=list(title=""), yaxis=list(title="Records"))
  })

  output$chart_sm_gap_bar <- renderPlotly({
    df <- qc_data(); req(df)
    if (!all(c("country","sm_gap_flag") %in% names(df))) return(
      plotly_empty() %>% im_layout() %>%
        add_annotations(text="No SM gap data found", showarrow=FALSE,
                        font=list(size=13, color=C_$muted))
    )
    tbl <- df %>% filter(sm_gap_flag==1, !is.na(country)) %>%
           count(country) %>% arrange(desc(n)) %>% slice_head(n=15)
    if (!nrow(tbl)) return(NULL)
    plot_ly(tbl, x=~n, y=~reorder(country,n), type="bar", orientation="h",
            marker=list(color=C_$orange, line=list(width=0)),
            hovertemplate="%{y}: %{x:,}<extra></extra>") %>%
      im_layout(.title="SM Gap Flags by Country", .filename="IM_sm_gap",
                xaxis=list(title="Flagged Records"), yaxis=list(title=""),
                margin=list(l=120,r=60,t=46,b=30))
  })

  output$qc_tbl <- DT::renderDT({
    df <- qc_data(); req(df)
    qc_col <- intersect(c("qc_flag","reconciliation_flag"), names(df))[1]
    ft <- input$qc_type
    if (!is.null(ft) && !is.na(qc_col)) {
      if (ft == "Denominator issues")
        df <- df[grepl("denom", df[[qc_col]], ignore.case=TRUE) & !is.na(df[[qc_col]]),]
      else if (ft == "Needs review")
        df <- df[grepl("review", df[[qc_col]], ignore.case=TRUE) & !is.na(df[[qc_col]]),]
      else if (ft == "SM gaps" && "sm_gap_flag" %in% names(df))
        df <- df[!is.na(df$sm_gap_flag) & df$sm_gap_flag==1,]
      else if (ft == "All flags" && !is.na(qc_col))
        df <- df[!is.na(df[[qc_col]]) & df[[qc_col]] != "OK",]
    }
    ct <- input$qc_cntry
    if (!is.null(ct) && ct != "All" && "country" %in% names(df))
      df <- df[!is.na(df$country) & df$country==ct,]
    show_cols <- intersect(c("country","province","district","roundnumber",
                             "vaccine_type","qc_flag","reconciliation_flag",
                             "sm_gap_flag","sm_priority_flag","u5_present","u5_fm"),
                           names(df))
    DT::datatable(df[, show_cols, drop=FALSE],
      options=list(pageLength=15, scrollX=TRUE, dom="Bfrtip"),
      rownames=FALSE, class="table table-sm")
  })

  observeEvent(rv$data, {
    df <- rv$data; if (is.null(df) || !"country" %in% names(df)) return()
    ctrs <- sort(unique(df$country[!is.na(df$country)]))
    updateSelectInput(session, "qc_cntry", choices=c("All", ctrs))
  })

  # ═══════════════════════════════════════════════════════════════════════════
  # PIPELINE TAB
  # ═══════════════════════════════════════════════════════════════════════════

  rv_log   <- reactiveVal(character(0))
  observeEvent(user(), { if (is_admin()) rv_log(get_log_lines()) })   # nothing is read for signed-out / country sessions
  rv_stat  <- reactiveVal("idle")
  rv_steps <- reactiveVal(rep("pending", 6L))
  rv_proc  <- reactiveVal(NULL)   # list(proc, step_idx, lf, pos)
  rv_queue <- reactiveVal(integer(0))
  # TRUE when a report step (4 = Intelligence Engine, 5 = Report + Deck) failed
  # but Upload SharePoint (6) was still run afterwards -- see the failure branch
  # below. Keeps the final status "error" even though the last step succeeded.
  rv_soft_error <- reactiveVal(FALSE)

  # Stop button only makes sense while something is actually running.
  observe({
    if (rv_stat() == "running") shinyjs::enable("btn_stop")
    else                        shinyjs::disable("btn_stop")
  })

  observeEvent(input$btn_stop, {
    if (!is_admin()) return()
    pinfo <- isolate(rv_proc())
    if (is.null(pinfo) || !pinfo$proc$is_alive()) {
      showNotification("Nothing is currently running.", type="message")
      return()
    }
    step_idx <- pinfo$step_idx
    # cleanup_tree=TRUE (set when the process was launched) means kill()
    # also takes down whatever Rscript/python child processes this step
    # spawned, not just the top-level Rscript run_workflow.R process.
    tryCatch(pinfo$proc$kill(), error=function(e) NULL)

    states <- isolate(rv_steps())
    states[step_idx] <- "pending"   # back to normal, ready to re-run
    rv_steps(states)
    rv_stat("idle")
    rv_proc(NULL)
    rv_queue(integer(0))            # drop any steps still queued behind it

    rv_log(paste0(isolate(rv_log()),
                  "\n[STOPPED] Step ", step_idx, " cancelled by user.\n"))
    showNotification("Pipeline stopped.", type="warning")
  })

  # Step definitions -------------------------------------------------------
  # NOTE: these Rscript calls intentionally do NOT pass "--vanilla". That flag
  # also skips .Rprofile/.Renviron, which is where this machine's R library
  # path (R_LIBS_USER) is configured -- with --vanilla, a freshly spawned
  # Rscript subprocess can fail to find already-installed packages
  # (tidyverse, openxlsx, flextable, ...) even though the exact same script
  # runs fine when launched normally (as it always is from the command line,
  # and as run_workflow.R's own source()-based steps already do). Every
  # subprocess call below matches that same plain "Rscript scriptname.R"
  # invocation on purpose.
  # Order matters: Upload SharePoint runs LAST so the Intelligence Report, Word
  # brief, Deck and Phase 1 workbook (all written by steps 4-5) exist by the time
  # upload_to_sharepoint.py looks for them -- when it ran as step 4 it always
  # reported them missing and skipped them.
  STEPS <- list(
    list(n=1L, label="Fetch Data",        icon="cloud-download-fill",
         cmd="Rscript",
         args=c(file.path(WORKFLOW_DIR,"scripts","run_workflow.R"),
                "--skip-build","--skip-clean","--skip-upload","--skip-reports")),
    list(n=2L, label="Build Repository",  icon="database-fill-gear",
         cmd="Rscript",
         args=c(file.path(WORKFLOW_DIR,"scripts","run_workflow.R"),
                "--skip-fetch","--skip-clean","--skip-upload","--skip-reports")),
    list(n=3L, label="Clean Geonames",    icon="eraser-fill",
         cmd="Rscript",
         args=c(file.path(WORKFLOW_DIR,"scripts","run_workflow.R"),
                "--skip-fetch","--skip-build","--skip-upload","--skip-reports")),
    list(n=4L, label="Intelligence Engine", icon="cpu-fill",
         cmd="Rscript",
         args=c(file.path(WORKFLOW_DIR,"scripts","afro_im_intilligence_analysis_engine.R"))),
    list(n=5L, label="Generate Report + Deck",  icon="file-earmark-bar-graph-fill",
         cmd="Rscript",
         # Runs the Advocacy Report and the PowerPoint deck as ONE step
         # (scripts/generate_reports_and_deck.R sources both in
         # sequence) instead of two separate pills/subprocesses -- see
         # that wrapper's own header comment for why.
         args=c(file.path(WORKFLOW_DIR,"scripts","generate_reports_and_deck.R"))),
    list(n=6L, label="Upload SharePoint", icon="cloud-arrow-up-fill",
         cmd=PYTHON_CMD,
         args=c(file.path(WORKFLOW_DIR,"scripts","upload_to_sharepoint.py"),
                "--base-dir", WORKFLOW_DIR, "--all"))
  )

  # Launch one step as a background process --------------------------------
  launch_step <- function(step_idx) {
    s      <- STEPS[[step_idx]]
    states <- rv_steps()
    states[step_idx] <- "running"
    rv_steps(states)
    rv_stat("running")

    hdr <- paste0("\n▶ [Step ", s$n, "] ", s$label,
                  "\n── Started: ", Sys.time(), " ──\n")
    rv_log(paste0(rv_log(), hdr))

    # Verify script exists (all args that aren't flags are paths)
    non_flag <- s$args[!startsWith(s$args, "--")]
    script   <- non_flag[length(non_flag)]
    if (!file.exists(script)) {
      rv_log(paste0(rv_log(), "[ERROR] Not found: ", script))
      states[step_idx] <- "error"; rv_steps(states); rv_stat("error")
      rv_proc(NULL); rv_queue(integer(0)); return()
    }

    lf <- tempfile(fileext=".log")
    proc <- tryCatch(
      processx::process$new(s$cmd, s$args, stdout=lf, stderr=lf,
                            cleanup_tree=TRUE),
      error=function(e) {
        rv_log(paste0(rv_log(), "[ERROR] Could not start process: ", e$message))
        NULL
      }
    )
    if (is.null(proc)) {
      states[step_idx] <- "error"; rv_steps(states); rv_stat("error")
      rv_proc(NULL); rv_queue(integer(0)); return()
    }
    rv_proc(list(proc=proc, step_idx=step_idx, lf=lf, pos=0L))
  }

  # Workflow log file tracker (shared across polling calls) ----------------
  rv_logfile_pos <- reactiveVal(0L)   # bytes already shown from workflow log

  # Reset log file position when a new run starts
  reset_log_pos <- function() {
    fls <- sort(list.files(LOGS_DIR, pattern="^workflow_.*\\.log$",
                           full.names=TRUE))
    if (length(fls)) rv_logfile_pos(as.integer(file.info(tail(fls,1))$size))
    else             rv_logfile_pos(0L)
  }

  # Poll every 800ms — stream log file + detect process completion ---------
  observe({
    invalidateLater(800)
    pinfo <- isolate(rv_proc())
    if (is.null(pinfo)) return()

    proc     <- pinfo$proc
    step_idx <- pinfo$step_idx

    # ── 1. Read new bytes from the WORKFLOW log file (where logger writes) ──
    fls <- sort(list.files(LOGS_DIR, pattern="^workflow_.*\\.log$",
                           full.names=TRUE))
    if (length(fls)) {
      wf  <- tail(fls, 1)
      pos <- isolate(rv_logfile_pos())
      sz  <- tryCatch(file.info(wf)$size, error=function(e) NA_real_)
      if (!is.na(sz) && sz > pos) {
        con       <- file(wf, "rb")
        if (pos > 0L) seek(con, pos)
        raw_bytes <- readBin(con, "raw", n=as.integer(sz - pos))
        close(con)
        if (length(raw_bytes) > 0L) {
          rv_logfile_pos(pos + length(raw_bytes))
          new_text <- tryCatch(rawToChar(raw_bytes), error=function(e) "")
          # strip the "INFO [timestamp]" prefix for cleaner display
          new_text <- gsub("INFO \\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\] {1,3}",
                           "", new_text)
          rv_log(paste0(isolate(rv_log()), new_text))
        }
      }
    }

    # ── 2. Also capture any direct stdout from the process (e.g. errors) ──
    lf  <- pinfo$lf
    pos2 <- pinfo$pos
    if (file.exists(lf)) {
      sz2 <- tryCatch(file.info(lf)$size, error=function(e) NA_real_)
      if (!is.na(sz2) && sz2 > pos2) {
        con2      <- file(lf, "rb")
        if (pos2 > 0L) seek(con2, pos2)
        rb2       <- readBin(con2, "raw", n=as.integer(sz2 - pos2))
        close(con2)
        if (length(rb2) > 0L) {
          rv_proc(modifyList(pinfo, list(pos=pos2 + length(rb2))))
          txt2 <- tryCatch(rawToChar(rb2), error=function(e) "")
          if (nchar(trimws(txt2)) > 0)
            rv_log(paste0(isolate(rv_log()), txt2))
        }
      }
    }

    # ── 3. Detect process completion ──────────────────────────────────────
    if (!proc$is_alive()) {
      exit_code <- proc$get_exit_status()
      ok        <- isTRUE(exit_code == 0L)
      states    <- isolate(rv_steps())
      states[step_idx] <- if (ok) "done" else "error"
      rv_steps(states)

      if (!ok) {
        rv_log(paste0(isolate(rv_log()),
                      "\n[ERROR] Step ", step_idx,
                      " failed (exit code: ", exit_code, ")"))
        q_left <- isolate(rv_queue())
        if (step_idx %in% c(4L, 5L) && 6L %in% q_left) {
          # Upload SharePoint now runs AFTER the report steps. A failed report
          # must not stop the freshly built repository files from being
          # published, so skip the remaining report step(s) and still upload.
          rv_soft_error(TRUE)
          rv_log(paste0(isolate(rv_log()),
                        "\n[WARN] Report step failed -- still running Upload SharePoint ",
                        "so the repository files are published.\n"))
          rv_proc(NULL); rv_queue(integer(0))
          launch_step(6L)
        } else {
          rv_stat("error"); rv_proc(NULL); rv_queue(integer(0))
        }
      } else {
        rv_log(paste0(isolate(rv_log()),
                      "\n[OK] Step ", step_idx, " complete\n"))
        rv_proc(NULL)
        q <- isolate(rv_queue())
        if (length(q) == 0L) {
          rv$data <- load_scoped()
          if (isolate(rv_soft_error())) {
            rv_stat("error")
            showNotification("Pipeline finished, but a report step failed. The repository was uploaded and the data refreshed - see the log.",
                             type="warning", duration=10)
          } else {
            rv_stat("ok")
            showNotification("Pipeline complete — data refreshed.",
                             type="message", duration=6)
          }
        } else {
          rv_queue(q[-1L]); launch_step(q[1L])
        }
      }
    }
  })

  # Button handlers --------------------------------------------------------
  step_start <- function(clear_log = TRUE, header = NULL) {
    rv_steps(rep("pending", 6L))
    rv_queue(integer(0L))
    rv_soft_error(FALSE)
    reset_log_pos()   # start reading workflow log from current EOF
    if (clear_log) {
      msg <- if (!is.null(header)) paste0(header, "\n") else
             paste0("── ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ──\n")
      rv_log(msg)
    }
  }

  observeEvent(input$run_fetch, {
    if (!is_admin()) return()
    step_start(header = "[1] FETCH DATA\n")
    launch_step(1L)
  })
  observeEvent(input$run_build, {
    if (!is_admin()) return()
    step_start(header = "[2] BUILD REPOSITORY\n")
    launch_step(2L)
  })
  observeEvent(input$run_clean, {
    if (!is_admin()) return()
    step_start(header = "[3] CLEAN GEONAMES\n")
    launch_step(3L)
  })
  observeEvent(input$run_upload, {
    if (!is_admin()) return()
    step_start(header = "[5] UPLOAD SHAREPOINT\n")
    launch_step(6L)
  })
  observeEvent(input$run_rpts, {
    if (!is_admin()) return()
    step_start(header = "[4] GENERATE REPORTS (Intelligence Engine + Advocacy Report + Deck)\n")
    rv_queue(5L)
    launch_step(4L)
  })
  observeEvent(input$run_all, {
    if (!is_admin()) return()
    step_start(header = paste0("▶  FULL PIPELINE STARTED\n── ",
                               format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                               " ──\n"))
    rv_queue(2:6)
    launch_step(1L)
  })

  # Refresh log from file on button click ----------------------------------
  observeEvent(input$btn_rl_log, {
    if (!is_admin()) return()
    rv_log(get_log_lines())
    rv_stat(last_run_info()$status)
  })

  # Reload data manually ---------------------------------------------------
  observeEvent(input$btn_rl_data, {
    rv$data <- load_scoped()
    showNotification("Data reloaded.", type="message")
  })

  # Outputs ----------------------------------------------------------------
  output$log_txt <- renderText({ req(is_admin()); rv_log() })

  output$status_badge <- renderUI({
    st  <- rv_stat()
    cls <- switch(st,
      ok      = "bg-success",
      error   = "bg-danger",
      running = "bg-warning text-dark",
      "bg-secondary")
    # Just a status "light" (dot) + plain text -- no icon glyph.
    dot_cls <- switch(st,
      ok="dot-ok", error="dot-err", running="dot-running", "dot-idle")
    lbl <- switch(st,
      ok="Pipeline OK", error="Error",
      running="Running…", "Idle")
    tags$span(class=paste("badge rounded-pill", cls),
              style="font-size:.75rem;padding:5px 12px;",
              tags$span(class=paste("dot", dot_cls)),
              lbl)
  })

  output$step_pills <- renderUI({
    states <- rv_steps()
    pills  <- lapply(seq_along(STEPS), function(i) {
      s    <- STEPS[[i]]
      st   <- states[i]
      cls  <- switch(st,
        done    = "step-pill step-done",
        running = "step-pill step-running",
        error   = "step-pill step-error",
        "step-pill step-pending")
      dot_cls <- switch(st, done="dot-ok", running="dot-running",
                        error="dot-err", "dot-idle")
      tags$span(class=cls,
        tags$span(class=paste("dot", dot_cls)),
        s$label)
    })
    div(class="d-flex flex-wrap gap-2 p-1", pills)
  })

  # ═══════════════════════════════════════════════════════════════════════════
  # DOWNLOAD RAW FORM DATA (Pipeline tab)
  # ── R/data_download_raw.R holds all the actual SharePoint list/download/
  # partition/zip logic (build_form_download()); this block only wires the
  # "Form ID" dropdown and the downloadHandler to it. Populated independently
  # of the "Load on startup" observe() above (which req()s the main cleaned
  # dataset) so the dropdown still fills in even before/without that dataset,
  # since raw_state forms are a separate SharePoint listing entirely.
  # ═══════════════════════════════════════════════════════════════════════════

  rv_dl_raw_msg <- reactiveVal(NULL)

  observe({
    req(user())
    ids <- tryCatch(list_available_form_ids(), error = function(e) character(0))
    if (length(ids)) ids <- ids[vapply(ids, form_ok, logical(1))]
    if (length(ids)) updateSelectInput(session, "dl_raw_form_id", choices = ids)
  })

  # "Effective" Year/Response for the Response/Round Number cascade below --
  # NOT the same thing as input$dl_raw_year/input$dl_raw_response directly.
  # A real bug was found in production: Response and Round Number are each
  # rebuilt from scratch via renderUI() (see their own comment for why), but
  # reading input$dl_raw_year/input$dl_raw_response straight from those
  # renderUI() bodies raced against Year's OWN renderUI() resetting itself
  # on a Form ID switch -- Year's brand-new widget only reports its reset
  # "__ALL__" value back to the server after a round trip to the browser,
  # so for one reactive flush right after switching forms, Response's/Round
  # Number's renderUI() could still read the PREVIOUS form's leftover Year/
  # Response value (confirmed via the #dl_raw_log_pre log: switching from
  # form 4445 to form 3550 briefly ran form 3550's Round Number lookup with
  # Response = "CHD-2023-10-1_nOPV", a value that only ever existed on
  # 4445). It self-corrected a few reactive ticks later, but along the way
  # re-downloaded the same file several times and briefly showed a
  # confusing "0 results" state.
  #
  # The fix: reset these two reactiveValues to "__ALL__" synchronously, in
  # the very same reactive flush that Form ID changes in (via the
  # priority = 1000 observer below, which always runs before any
  # priority-0 renderUI() in that same flush) -- no round trip needed.
  # Response's/Round Number's renderUI() blocks read FROM these
  # reactiveValues instead of the raw inputs, so they can never see a value
  # that belongs to a form other than the one currently selected. A second
  # pair of observers keeps them in sync with whatever the user actually
  # picks in the Year/Response widgets once those have settled.
  rv_dl_filters <- reactiveValues(year = "__ALL__", response = "__ALL__")

  observeEvent(input$dl_raw_form_id, {
    rv_dl_filters$year     <- "__ALL__"
    rv_dl_filters$response <- "__ALL__"
  }, priority = 1000, ignoreInit = FALSE)

  observeEvent(input$dl_raw_year, {
    if (.rd_year_arg_ok(input$dl_raw_year)) rv_dl_filters$year <- input$dl_raw_year
  }, ignoreNULL = TRUE)

  observeEvent(input$dl_raw_response, {
    if (.rd_text_ok(input$dl_raw_response)) rv_dl_filters$response <- input$dl_raw_response
  }, ignoreNULL = TRUE)

  # Shared log line pusher for the #dl_raw_log_pre console -- the actual
  # download build (downloadHandler's content(), below) already narrates
  # every step through this exact message shape; this is the same thing
  # reused for the Year/Response/Round Number lookups themselves (via
  # R/data_download_raw.R's own `progress` parameter on
  # list_available_years()/list_available_responses()/list_available_rounds()),
  # so picking a filter shows what that lookup is actually doing (which
  # file(s) it reads, how many rows survive each narrowing step, how many
  # distinct values it found) instead of happening silently behind the
  # "Refreshing…" indicator alone. Deliberately never clears the log itself
  # -- only an actual download start does that (dlRawLogClear below) -- so
  # switching Year then Response then Round Number leaves a readable trace
  # of the whole cascade rather than wiping it at every step.
  .dl_raw_log_progress <- function(detail) {
    session$sendCustomMessage("dlRawLogLine", list(
      text = paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", detail)
    ))
  }

  # Year dropdown: a brand new selectizeInput() is built from scratch every
  # time Form ID changes, via renderUI() -- same rebuild-the-whole-widget
  # approach as Response/Round Number below (see their own comment for why:
  # it keeps a previous form's leftover options from ever surviving a
  # switch), and it's what makes Shiny's automatic 'recalculating' class
  # -- and so the "Refreshing…" cue in R/constants_css_js.R's CSS -- show up
  # for Year too, which a plain updateSelectizeInput()-driven widget never
  # gets. Calls list_available_years() (R/data_download_raw.R), not the
  # cheaper but heavy-only list_partition_years() -- that distinction is
  # deliberately invisible here: every form, heavy or not, gets real years
  # to pick from when they're known, and "All years" (value "__ALL__",
  # never "" -- see the UI definition's own comment on why) is always
  # offered too.
  output$dl_raw_year_ui <- renderUI({
    form_id <- input$dl_raw_form_id
    req(form_id, form_ok(form_id))
    years <- tryCatch(list_available_years(form_id, progress = .dl_raw_log_progress),
                       error = function(e) character(0))
    choices <- c("All years" = "__ALL__")
    if (length(years)) choices <- c(choices, setNames(years, years))
    selectizeInput("dl_raw_year", "Year", choices = choices, selected = "__ALL__",
                   width = "100%", options = list(create = TRUE, createOnBlur = TRUE))
  })

  # Response / Round Number dropdowns: a brand new selectizeInput() is
  # built from scratch on every relevant change, via renderUI(), rather
  # than one long-lived widget kept in sync with updateSelectizeInput() --
  # see the UI definition's own comment for why (a real cross-form mix-up
  # was observed in production with the update-in-place approach). Each
  # render tears down the previous <select> + selectize.js instance
  # entirely and replaces it with a fresh one carrying only the choices
  # this exact lookup just returned, so there is no previous form's (or
  # previous year's) leftover option sitting in the DOM to ever show up
  # again.

  # Response's choices are the real, distinct Response values for the
  # selected Form ID + Year (list_available_responses(),
  # R/data_download_raw.R). renderUI() automatically re-runs whenever any
  # input/reactiveValue it reads changes, so simply reading both
  # input$dl_raw_form_id and rv_dl_filters$year here is enough to make this
  # cascade off either one -- no separate observeEvent()/multi-dependency
  # idiom needed. Reads rv_dl_filters$year, NOT input$dl_raw_year directly
  # -- see that reactiveValues' own comment for why (avoids a real race
  # where this could briefly read a previous form's leftover Year value
  # right after a Form ID switch).
  output$dl_raw_response_ui <- renderUI({
    form_id <- input$dl_raw_form_id
    req(form_id, form_ok(form_id))
    year      <- rv_dl_filters$year
    responses <- tryCatch(list_available_responses(form_id, year, progress = .dl_raw_log_progress),
                           error = function(e) character(0))
    choices <- c("All" = "__ALL__")
    if (length(responses)) choices <- c(choices, setNames(responses, responses))
    selectizeInput("dl_raw_response", "Response", choices = choices, selected = "__ALL__",
                   width = "100%", options = list(create = TRUE, createOnBlur = TRUE))
  })

  # Round Number's choices are the real, distinct roundNumber values for
  # the selected Form ID + Year + Response (list_available_rounds()),
  # cascading one level further than Response -- reading rv_dl_filters$response
  # here means this also rebuilds (resetting to "All") whenever Response
  # changes, since a round number that existed under the previous Response
  # value may not even exist under the new one. Reads rv_dl_filters$year/
  # $response, NOT the raw inputs directly -- same race-avoidance reason as
  # Response's own renderUI() above.
  output$dl_raw_round_ui <- renderUI({
    form_id <- input$dl_raw_form_id
    req(form_id, form_ok(form_id))
    year     <- rv_dl_filters$year
    response <- rv_dl_filters$response
    rounds   <- tryCatch(list_available_rounds(form_id, year, response, progress = .dl_raw_log_progress),
                          error = function(e) character(0))
    choices <- c("All" = "__ALL__")
    if (length(rounds)) choices <- c(choices, setNames(rounds, rounds))
    selectizeInput("dl_raw_round", "Round Number", choices = choices, selected = "__ALL__",
                   width = "100%", options = list(create = TRUE, createOnBlur = TRUE))
  })

  output$dl_raw_form <- downloadHandler(
    filename = function() {
      form_id  <- input$dl_raw_form_id
      fmt      <- input$dl_raw_format
      year     <- input$dl_raw_year
      response <- input$dl_raw_response
      round_nb <- input$dl_raw_round
      ext      <- switch(fmt, parquet = "parquet", xlsx = "xlsx", rds = "rds", "csv")
      req(form_id, fmt, form_ok(form_id))
      year_arg     <- if (!is.null(year) && nzchar(year) && year != "__ALL__") year else NULL
      response_arg <- if (!is.null(response) && nzchar(trimws(response)) && trimws(response) != "__ALL__") trimws(response) else NULL
      round_arg    <- if (!is.null(round_nb) && nzchar(trimws(round_nb)) && trimws(round_nb) != "__ALL__") trimws(round_nb) else NULL
      req(.rd_form_ok(form_id), fmt %in% .rd_formats, .rd_year_ok(year_arg),
          .rd_text_ok(response_arg), .rd_text_ok(round_arg))
      # Any of year/Response/roundNumber being set always means exactly one
      # resulting file -- never a zip, no need to check whether the form is
      # "heavy" at all -- since each of those filters narrows down to at
      # most one matching slice, not "one file per year".
      if (!is.null(year_arg) || !is.null(response_arg) || !is.null(round_arg))
        return(paste0(.filtered_file_stem(form_id, year_arg, response_arg, round_arg), ".", ext))
      multi <- tryCatch({
        if (!sharepoint_credentials_available()) {
          FALSE
        } else {
          token    <- sp_get_graph_token()
          drive_id <- sp_resolve_drive_id(token)
          heavy    <- form_is_partitioned(token, drive_id, form_id)
          heavy && fmt %in% c("csv", "xlsx")
        }
      }, error = function(e) FALSE)
      if (isTRUE(multi)) paste0(form_id, "_", fmt, "_by_year.zip") else paste0(form_id, ".", ext)
    },
    content = function(file) {
      form_id  <- input$dl_raw_form_id
      fmt      <- input$dl_raw_format
      year     <- input$dl_raw_year
      response <- input$dl_raw_response
      round_nb <- input$dl_raw_round
      req(form_id, fmt, form_ok(form_id))
      rv_dl_raw_msg(NULL)
      year_arg     <- if (!is.null(year) && nzchar(year) && year != "__ALL__") year else NULL
      response_arg <- if (!is.null(response) && nzchar(trimws(response)) && trimws(response) != "__ALL__") trimws(response) else NULL
      round_arg    <- if (!is.null(round_nb) && nzchar(trimws(round_nb)) && trimws(round_nb) != "__ALL__") trimws(round_nb) else NULL
      if (!.rd_form_ok(form_id) || !(fmt %in% .rd_formats) || !.rd_year_ok(year_arg) ||
          !.rd_text_ok(response_arg) || !.rd_text_ok(round_arg)) {
        rv_dl_raw_msg("Invalid download request.")
        writeLines(character(0), file)
        return(invisible())
      }

      # A heavy-form download can mean several sequential SharePoint
      # round-trips (one per year partition) plus a zip step -- with
      # nothing shown while that runs, it looks exactly like the
      # year-partitioned xlsx export "taking eternity" with zero progress
      # output earlier in this project (see scripts/fetch_sharepoint_csvs.py's
      # own history). withProgress()/incProgress() drive Shiny's built-in
      # progress bar, and every incProgress() call also pushes a line to
      # the #dl_raw_log_pre console below the button via the dlRawLogLine
      # custom message (R/constants_css_js.R) -- sendCustomMessage reaches
      # the browser immediately, unlike a plain reactive output, which
      # would only flush once this whole content() call returns.
      session$sendCustomMessage("dlRawLogClear", list())
      dl_label <- if (!is.null(year_arg) || !is.null(response_arg) || !is.null(round_arg))
        paste0(.filtered_file_stem(form_id, year_arg, response_arg, round_arg), ".", fmt)
      else paste0(form_id, ".", fmt)
      withProgress(message = paste0("Building ", dl_label, " download..."), value = 0, {
        progress_cb <- function(detail) {
          incProgress(amount = 1 / 12, detail = detail)
          .dl_raw_log_progress(detail)
        }
        res <- build_form_download(form_id, fmt, progress = progress_cb,
                                    year = year_arg, response = response_arg, round_number = round_arg)
      })

      if (!isTRUE(res$ok)) {
        rv_dl_raw_msg(res$message)
        showNotification(paste("Download failed:", res$message), type = "error", duration = 10)
        # downloadHandler must still produce a file even on failure -- an
        # empty one signals "nothing here" rather than silently truncating
        # whatever previous content the browser had, or crashing the handler.
        writeLines(character(0), file)
        return(invisible())
      }
      rv_dl_raw_msg(NULL)
      file.copy(res$path, file, overwrite = TRUE)
      # The build folder (can be GBs for big forms) is no longer needed once copied out.
      wd <- dirname(res$path)
      if (startsWith(basename(wd), "im_dl_") && identical(normalizePath(dirname(wd), mustWork = FALSE), normalizePath(tempdir(), mustWork = FALSE)))
        unlink(wd, recursive = TRUE, force = TRUE)
    }
  )

  output$dl_raw_status <- renderUI({
    msg <- rv_dl_raw_msg(); if (is.null(msg)) return(NULL)
    div(class="alert alert-danger p-2 mt-2 small",
        tags$span(class="dot dot-err"), msg)
  })
} # end server
shinyApp(ui, server)
