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

  # ── TAB 1 : OVERVIEW ────────────────────────────────────────────────────────
  nav_panel(hdr_icon("bar-chart-line-fill", "Overview"),

    layout_sidebar(
      sidebar = sidebar(
        width = 290, open = TRUE,

        div(class="sidebar-brand",
          div(class="sidebar-brand-icon", bs_icon("globe-europe-africa", size="1.7rem")),
          div(
            div(class="sidebar-brand-name", "AFRO IM Dashboard"),
            div(class="sidebar-brand-sub",  "Independent Monitoring")
          )
        ),

        # ── Scope ─────────────────────────────────────────────────────────────
        div(class="sidebar-sec", hdr_icon("geo-alt-fill", "Geographic Scope")),
        selectInput("ov_block",    "AFRO Block",  c("All","LCB","WA","DRC","CEA","ESA")),
        selectInput("ov_country",  "Country",      "All"),
        selectInput("ov_province", "Province",     "All"),
        selectInput("ov_district", "District",     "All"),

        hr(),

        # ── Campaign ──────────────────────────────────────────────────────────
        div(class="sidebar-sec", hdr_icon("clipboard2-pulse-fill", "Campaign")),
        selectInput("ov_vaccine",  "Vaccine Type", "All"),
        selectInput("ov_response", "Response",     "All"),
        selectizeInput("ov_round", "Round Number(s)", choices=NULL, multiple=TRUE,
                       options=list(placeholder="All rounds", plugins=list("remove_button"))),

        hr(),

        # ── Date ──────────────────────────────────────────────────────────────
        div(class="sidebar-sec", hdr_icon("calendar3", "Date / Period")),
        selectInput("ov_date_type", NULL,
                    c("All time","Last N months","Last N years",
                      "Date range","Last N consecutive rounds",
                      "Last N rounds in last 12 months")),
        conditionalPanel("input.ov_date_type == 'Last N months'",
          numericInput("ov_n_months","Months",6,min=1,max=120,step=1)),
        conditionalPanel("input.ov_date_type == 'Last N years'",
          numericInput("ov_n_years","Years",1,min=1,max=10,step=1)),
        conditionalPanel("input.ov_date_type == 'Date range'",
          dateRangeInput("ov_daterange","Range",
                         start=Sys.Date()-365, end=Sys.Date())),
        conditionalPanel("input.ov_date_type == 'Last N consecutive rounds'",
          numericInput("ov_n_rounds","N most recent rounds",3,min=1,max=50,step=1)),
        conditionalPanel("input.ov_date_type == 'Last N rounds in last 12 months'",
          numericInput("ov_n_rounds_12m","N most recent rounds",3,min=1,max=50,step=1)),

        hr(),
        uiOutput("ov_filter_badge"),
        div(class="d-grid",
          actionButton("ov_reset", hdr_icon("arrow-counterclockwise", "Reset All Filters"),
                       class="btn btn-outline-secondary btn-sm mt-1")),
        div(class="d-grid mt-2",
          downloadButton("dl_ov_all", tagList(bs_icon("cloud-download-fill", class="me-1"), "Download Filtered Data (CSV)"),
                         class="btn-dl-master")),

        hr(),
        div(class="d-flex justify-content-between align-items-center",
          div(style="color:rgba(255,255,255,.55);font-size:.68rem;","Last refresh:"),
          div(style="color:#fff;font-size:.68rem;font-weight:600;",
              uiOutput("data_freshness_mini"))
        ),
        actionButton("btn_refresh", hdr_icon("arrow-repeat", "Refresh Data"),
                     class="btn btn-outline-primary btn-sm w-100 mt-2")
      ),

      # ── Main panel ────────────────────────────────────────────────────────
      div(
        # ── KPI strip — compact, pinned to the very top of the dashboard ─────
        div(class="row row-cols-2 row-cols-md-4 row-cols-xl-8 g-2 mb-3",
          div(class="col", div(class="fade-up d1", kpi("v_records",   "Total Records",      bs_icon("clipboard-data-fill"),"kpi-blue",  "filtered",   trend="live", compact=TRUE))),
          div(class="col", div(class="fade-up d2", kpi("v_hh",        "Households Visited", bs_icon("house-fill"),"kpi-teal",  "HH reached", trend=NULL, compact=TRUE))),
          div(class="col", div(class="fade-up d3", kpi("v_cv",        "Coverage Rate",      bs_icon("check-circle-fill"),"kpi-green", "vs 90% target", trend="target 90%", bar_pct=0.0, compact=TRUE))),
          div(class="col", div(class="fade-up d4", kpi("v_missed",    "Missed Children",    bs_icon("person-fill"),"kpi-red",   "", trend=NULL, compact=TRUE))),
          div(class="col", div(class="fade-up d1", kpi("v_awareness", "Caregiver Awareness",bs_icon("megaphone-fill"),"kpi-orange","SM",       trend="target 80%", bar_pct=0.0, compact=TRUE))),
          div(class="col", div(class="fade-up d2", kpi("v_risk_crit", "Critical Districts", bs_icon("exclamation-circle-fill"),"kpi-purple","risk ≥70", trend=NULL, compact=TRUE))),
          div(class="col", div(class="fade-up d3", kpi("v_countries", "Countries",          bs_icon("globe-europe-africa"),"kpi-teal",  "in scope", trend=NULL, compact=TRUE))),
          div(class="col", div(class="fade-up d4", kpi("v_run",       "Last Pipeline Run",  bs_icon("clock-history"),"kpi-blue",  "",         trend=NULL, compact=TRUE)))
        ),

        # ── Hero context banner ──────────────────────────────────────────────
        uiOutput("hero_banner"),

        # ── Executive KPI snapshot card (ported from report Visual 0) ────────
        div(id="exec_kpi_capture",
          uiOutput("exec_kpi_card")
        ),

        # ── Row 2 : Country Risk Profile + Operational Failure Profile ──────
        # (ported from the AFRO Advocacy Intelligence Report's country-risk
        # and operational-failure visuals, computed live from filtered data)
        # Placed early — this is a "where is the problem" view, highest
        # priority for advocacy/decision-making.
        div(class="row g-3 mb-3",
          div(class="col-xl-6 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("globe-europe-africa", "Country-Level IM Risk Profile"),
                dl_btn("dl_country_risk")),
              plotlyOutput("chart_country_risk", height="360px"))
          ),
          div(class="col-xl-6 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("tools", "Operational Failure Profile"),
                dl_btn("dl_op_failure")),
              plotlyOutput("chart_op_failure", height="360px"))
          )
        ),

        # ── Row 3 : Top Priority Districts for Advocacy ──────────────────────
        # (also "where is the problem", at district granularity — kept next
        # to the Country Risk Profile above for a continuous priority read)
        div(class="row g-3 mb-3",
          div(class="col-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("bullseye", "Top Priority Districts for Advocacy"),
                dl_btn("dl_priority_districts")),
              plotlyOutput("chart_priority_districts", height="640px"))
          )
        ),

        # ── Row 4 : Block CV + Risk donut ───────────────────────────────────
        div(class="row g-3 mb-3",
          div(class="col-xl-7 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("map-fill", "CV Performance by AFRO Block"),
                dl_btn("dl_block")),
              plotlyOutput("chart_block", height="260px"))
          ),
          div(class="col-xl-5 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("speedometer2", "District Risk Classification"),
                dl_btn("dl_risk_dist")),
              plotlyOutput("chart_risk_dist", height="260px"))
          )
        ),

        # ── Row 5 : SM Quadrant + Alert ─────────────────────────────────────
        div(class="row g-3 mb-3",
          div(class="col-xl-7 col-lg-12",
            card(full_screen=TRUE,
              card_header(div(class="d-flex align-items-center justify-content-between",
                div(class="d-flex align-items-center gap-3",
                  hdr_icon("diagram-3-fill", "Social Mobilisation vs Coverage"),
                  div(style="font-size:.68rem;font-weight:500;display:flex;gap:8px;",
                    tags$span(style=paste0("color:",C_$red,";"),    "● Low SM+CV"),
                    tags$span(style=paste0("color:",C_$orange,";"), "● Low SM"),
                    tags$span(style=paste0("color:",C_$purple,";"), "● Low CV"),
                    tags$span(style=paste0("color:",C_$blue,";"),   "● High SM+CV")
                  )
                ),
                dl_btn("dl_sm_quad")
              )),
              plotlyOutput("chart_sm_quadrant", height="450px"))
          ),
          div(class="col-xl-5 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("exclamation-triangle-fill", "Countries / Areas Below 80% CV"), dl_btn("dl_alert_cv")),
              div(style="padding:4px 8px;", uiOutput("alert_low_cv")))
          )
        ),

        # ── Row 6 : Root causes + CV by Country/Province/District ───────────
        div(class="row g-3 mb-3",
          div(class="col-xl-5 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("search", "Root Causes of Missed Children"),
                dl_btn("dl_root_ov")),
              plotlyOutput("chart_root_ov", height="360px"))
          ),
          div(class="col-xl-7 col-lg-12",
            card(full_screen=TRUE,
              card_header(div(class="d-flex align-items-center justify-content-between",
                div(class="d-flex align-items-center gap-3",
                  uiOutput("chart_cv_title", inline=TRUE),
                  div(style="font-size:.72rem;font-weight:500;",
                    tags$span(style=paste0("color:",C_$green,";"),  "■ ≥90%  "),
                    tags$span(style=paste0("color:",C_$orange,";"), "■ 80–90%  "),
                    tags$span(style=paste0("color:",C_$red,";"),    "■ <80%")
                  )
                ),
                dl_btn("dl_cv")
              )),
              plotlyOutput("chart_cv", height="360px"))
          )
        ),

        # ── Row 7 : Top/Bottom + Trend ──────────────────────────────────────
        div(class="row g-3 mb-3",
          div(class="col-xl-4 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                uiOutput("chart_topbot_title", inline=TRUE),
                dl_btn("dl_top_bottom")),
              plotlyOutput("chart_top_bottom", height="280px"))
          ),
          div(class="col-xl-8 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("graph-up", "Records & Coverage Trend Over Time"),
                dl_btn("dl_trend")),
              plotlyOutput("chart_trend", height="280px"))
          )
        ),

        # ── Row 8 : Heatmap + QC ────────────────────────────────────────────
        div(class="row g-3 mb-3",
          div(class="col-xl-8 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("fire", "CV Heatmap — Area × Campaign Round"),
                dl_btn("dl_heatmap")),
              plotlyOutput("chart_heatmap", height="340px"))
          ),
          div(class="col-xl-4 col-lg-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("pie-chart-fill", "QC Flag Distribution"),
                dl_btn("dl_qc_pie")),
              plotlyOutput("chart_qc_pie", height="340px"))
          )
        ),

        # ── Row 9 : CV95 proportion table ────────────────────────────────────
        div(class="row g-3",
          div(class="col-12",
            card(full_screen=TRUE,
              card_header(class="d-flex align-items-center justify-content-between",
                hdr_icon("bar-chart-line-fill", "% Districts ≥95% CV — Country × Vaccine Type × Month"),
                dl_btn("dl_cv95")),
              plotlyOutput("chart_cv95", height="520px"))
          )
        )
      )
    )
  ),

  # ── TAB 2 : EXPLORER ────────────────────────────────────────────────────────
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

  # ── TAB 3 : QC MONITOR ──────────────────────────────────────────────────────
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

  # ── TAB 4 : PIPELINE ────────────────────────────────────────────────────────
  nav_panel(hdr_icon("gear-fill", "Pipeline"),

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
            actionButton("run_upload", hdr_icon("cloud-arrow-up-fill",       "4. Upload SharePoint"), class="btn-outline-primary"),
            actionButton("run_rpts",   hdr_icon("file-earmark-bar-graph-fill","5. Generate Reports"), class="btn-outline-primary"),
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
    ),

    card(
      card_header(hdr_icon("cloud-arrow-up-fill", "SharePoint Upload (manual/ad hoc)")),
      card_body(
        div(class="info-banner mb-3",
          tags$b("Target:"), tags$code("7. SIA_Data / Data Repository"),
          " — use this for a quick test/check, or a one-off push outside the full pipeline run above."),
        layout_columns(
          col_widths=c(6,6), gap="10px",
          selectInput("sp_scope","Scope",
                      c("Upload all files"  = "--all",
                        "Test connection"   = "--test",
                        "Check local files" = "--check")),
          div(style="padding-top:24px;",
            actionButton("btn_push_sp", hdr_icon("cloud-arrow-up-fill", "Push to SharePoint"),
                         class="btn-warning w-100"))
        ),
        uiOutput("sp_badge_ui")
      )
    )
  )
)

# ── SERVER ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  rv <- reactiveValues(
    data           = NULL,
    report_builder = NULL   # in-progress AI-generated report/deck, if any (see R/ai_report_builder.R)
  )

  # ── Fix: plotly charts render squished on tabs that weren't visible yet ─────
  # A plotlyOutput inside a nav_panel that isn't the active tab starts life at
  # display:none, so Plotly measures a 0-width container the first time it
  # draws and never recovers on its own. Firing a window resize event right
  # after a tab becomes visible (Bootstrap's `input$nav` changes) makes every
  # plotly chart already on that tab recompute its real size. This is what
  # made Explorer/QC look "squished" while Overview (the initially active
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
    rv$data <- load_im_data()
    req(rv$data)
    df <- rv$data

    ctrs <- sort(unique(df$country[!is.na(df$country)]))
    vacs <- sort(unique(df$vaccine_type[!is.na(df$vaccine_type)]))
    resp <- sort(unique(df$response[!is.na(df$response)]))

    updateSelectInput(session, "f_country",  choices=c("All", ctrs))
    updateSelectInput(session, "f_vaccine",  choices=c("All", vacs))
    updateSelectInput(session, "f_resp",     choices=c("All", resp))
    updateSelectInput(session, "qc_cntry",   choices=c("All", ctrs))

    dc <- date_col_of(df)
    if (!is.na(dc)) {
      v <- as.Date(df[[dc]]); v <- v[!is.na(v)]
      if (length(v)) updateDateRangeInput(session,"f_dates", start=min(v), end=max(v))
    }

    # ── Animate KPIs ──────────────────────────────────────────────────────────
    session$sendCustomMessage("countUp",
      list(id="v_records", v=nrow(df), ms=1200, delay=50))

    if ("country" %in% names(df))
      session$sendCustomMessage("countUp",
        list(id="v_countries", v=n_distinct(df$country, na.rm=TRUE), ms=900, delay=100))

    if (all(c("u5_fm","u5_present") %in% names(df))) {
      tp <- as.numeric(sum(df$u5_present, na.rm=TRUE))
      tf <- as.numeric(sum(df$u5_fm,      na.rm=TRUE))
      mc <- pmax(tp - tf, 0)
      if (tp > 0) {
        session$sendCustomMessage("countUp",
          list(id="v_cv", v=round(tf/tp*100,1), ms=1400, pct=TRUE, delay=150))
        session$sendCustomMessage("countUp",
          list(id="v_missed", v=round(mc), ms=1200, delay=200))
      }
    }

    # HH Visited
    if ("number_of_hh_visited" %in% names(df)) {
      hh <- sum(as.numeric(df$number_of_hh_visited), na.rm=TRUE)
      session$sendCustomMessage("countUp", list(id="v_hh", v=round(hh), ms=1100, delay=250))
    }

    # Caregiver awareness
    if (all(c("number_of_hh_visited","care_giver_informed_sia") %in% names(df))) {
      tot_hh  <- sum(as.numeric(df$number_of_hh_visited),    na.rm=TRUE)
      tot_inf <- sum(as.numeric(df$care_giver_informed_sia), na.rm=TRUE)
      if (tot_hh > 0)
        session$sendCustomMessage("countUp",
          list(id="v_awareness", v=round(tot_inf/tot_hh*100,1), ms=1300, pct=TRUE, delay=300))
    }

    # Critical districts (risk score ≥ 70)
    dfr <- tryCatch(with_risk(df), error=function(e) NULL)
    if (!is.null(dfr) && "risk_class" %in% names(dfr)) {
      # Aggregate to district level first
      crit <- dfr %>%
        group_by(country, province, district) %>%
        summarise(rc=first(risk_class), .groups="drop") %>%
        filter(rc == "Critical") %>% nrow()
      session$sendCustomMessage("countUp",
        list(id="v_risk_crit", v=crit, ms=1100, delay=350))
    }
  })

  # ── Hero context banner ──────────────────────────────────────────────────────
  output$hero_banner <- renderUI({
    df <- tryCatch(ov_data(), error = function(e) NULL)
    df <- if (!is.null(df)) df else rv$data

    n_rec      <- if (!is.null(df)) nrow(df)                                              else 0
    n_country  <- if (!is.null(df) && "country"  %in% names(df)) n_distinct(df$country,  na.rm=TRUE) else 0
    n_district <- if (!is.null(df) && "district" %in% names(df)) n_distinct(df$district, na.rm=TRUE) else 0

    active <- character(0)
    if (!is.null(input$ov_block)    && input$ov_block    != "All") active <- c(active, input$ov_block)
    if (!is.null(input$ov_country)  && input$ov_country  != "All") active <- c(active, input$ov_country)
    if (!is.null(input$ov_vaccine)  && input$ov_vaccine  != "All") active <- c(active, input$ov_vaccine)
    if (!is.null(input$ov_response) && input$ov_response != "All") active <- c(active, input$ov_response)
    if (length(input$ov_round) > 0) active <- c(active, paste("Rnd", paste(input$ov_round, collapse=",")))
    if (!is.null(input$ov_date_type) && input$ov_date_type != "All time") active <- c(active, input$ov_date_type)

    ctx <- if (length(active) > 0) paste(active, collapse=" · ") else "All countries · All campaigns"

    div(class="hero-ctx fade-up",
      div(style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:14px;position:relative;z-index:1;",
        div(
          div(class="hero-ctx-title", "AFRO Regional IM Intelligence"),
          div(class="hero-ctx-sub",
            tagList(bs_icon("geo-alt-fill", class = "me-1",
                             style = "vertical-align:-0.1em;"), ctx))
        ),
        div(class="hero-stats",
          div(class="hero-stat",
            div(class="hero-stat-val", formatC(n_rec,      format="d", big.mark=",")),
            div(class="hero-stat-lbl", "Records")
          ),
          div(class="hero-stat",
            div(class="hero-stat-val", n_country),
            div(class="hero-stat-lbl", "Countries")
          ),
          div(class="hero-stat",
            div(class="hero-stat-val", formatC(n_district, format="d", big.mark=",")),
            div(class="hero-stat-lbl", "Districts")
          )
        )
      )
    )
  })

  # ── Executive KPI snapshot card (live replica of report Visual 0) ───────────
  output$exec_kpi_card <- renderUI({
    df <- tryCatch(ov_data(), error = function(e) NULL)
    df <- if (!is.null(df)) df else rv$data
    if (is.null(df) || !nrow(df)) return(NULL)
    dfr <- tryCatch(with_risk(df), error = function(e) NULL)

    who_blue  <- "#0093D5"; dark_blue <- "#003A70"; alert_red <- "#C00000"
    gold      <- "#F2B600"; soft_grey <- "#F5F7FA"

    n_country  <- if ("country" %in% names(df)) n_distinct(df$country, na.rm=TRUE) else 0
    n_district <- if (all(c("country","province","district") %in% names(df)))
                     n_distinct(paste(df$country, df$province, df$district)) else 0
    n_rounds   <- if (all(c("country","response","roundnumber") %in% names(df)))
                     n_distinct(paste(df$country, df$response, df$roundnumber)) else NA

    hh_visited <- if ("number_of_hh_visited" %in% names(df))
                     sum(as.numeric(df$number_of_hh_visited), na.rm=TRUE) else NA

    tp <- if ("u5_present" %in% names(df)) sum(as.numeric(df$u5_present), na.rm=TRUE) else NA
    tf <- if ("u5_fm"      %in% names(df)) sum(as.numeric(df$u5_fm),      na.rm=TRUE) else NA
    regional_cv  <- if (!is.na(tp) && !is.na(tf) && tp > 0) tf / tp else NA
    total_missed <- if (!is.na(tp) && !is.na(tf)) pmax(tp - tf, 0) else NA

    mean_awareness <- if (!is.null(dfr) && "awareness_rate" %in% names(dfr))
                         mean(dfr$awareness_rate, na.rm=TRUE) else NA
    mean_risk <- if (!is.null(dfr) && "risk_score" %in% names(dfr))
                    mean(dfr$risk_score, na.rm=TRUE) else NA

    risk_counts <- list(critical=0, high=0, moderate=0)
    if (!is.null(dfr) && all(c("risk_class","country","province","district") %in% names(dfr))) {
      rc <- dfr %>%
        group_by(country, province, district) %>%
        summarise(rc = first(risk_class), .groups="drop") %>%
        count(rc)
      g <- function(x) { v <- rc$n[rc$rc == x]; if (length(v)) v else 0 }
      risk_counts <- list(critical=g("Critical"), high=g("High"), moderate=g("Moderate"))
    }

    fmt_pct <- function(x) if (is.na(x)) "—" else paste0(round(x*100,1), "%")
    fmt_n   <- function(x) if (is.na(x)) "—" else fmt_num(x)

    metric_box <- function(val, label, border_col) {
      div(style=paste0(
            "background:#fff;border:2px solid ",border_col,";border-radius:10px;",
            "padding:14px 10px;text-align:center;flex:1;min-width:150px;"),
        div(style=paste0("font-size:1.9rem;font-weight:800;color:",border_col,";line-height:1.1;"), val),
        div(style="font-size:.72rem;font-weight:700;color:#3A3A3A;margin-top:4px;text-transform:uppercase;letter-spacing:.03em;",
            label)
      )
    }

    div(class="fade-up", style=paste0(
          "border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,92,151,.10);",
          "margin-bottom:1rem;background:",soft_grey,";"),
      div(style=paste0("background:",dark_blue,";padding:14px 20px;color:#fff;",
                       "display:flex;justify-content:space-between;align-items:flex-start;gap:10px;flex-wrap:wrap;"),
        div(
          div(style="font-size:1.05rem;font-weight:800;letter-spacing:.02em;",
              "AFRO REGIONAL INDEPENDENT MONITORING INTELLIGENCE"),
          div(style="font-size:.78rem;opacity:.85;margin-top:2px;",
              paste0("Generated: ", format(Sys.Date(), "%d %b %Y"), "  |  Live filtered snapshot"))
        ),
        div(style="display:flex;gap:6px;height:fit-content;",
          tags$button(type="button", onclick="captureExecKPI()",
            style="background:transparent;border:1px solid rgba(255,255,255,.55);color:#fff;font-size:.7rem;padding:2px 10px;border-radius:6px;cursor:pointer;",
            bs_icon("camera-fill", class="me-1"), "PNG"),
          downloadButton("dl_exec_snapshot", tagList(bs_icon("download", class="me-1"), "CSV"),
            style="background:transparent;border:1px solid rgba(255,255,255,.55);color:#fff;font-size:.7rem;padding:2px 10px;border-radius:6px;height:fit-content;")
        )
      ),
      div(style="padding:18px 20px;",
        div(style="display:flex;gap:14px;flex-wrap:wrap;margin-bottom:14px;",
          metric_box(fmt_n(hh_visited),    "Households visited", who_blue),
          metric_box(fmt_pct(regional_cv), "Regional coverage",  who_blue),
          metric_box(fmt_n(total_missed),  "Missed children",    alert_red)
        ),
        div(style="display:flex;gap:14px;flex-wrap:wrap;margin-bottom:16px;",
          metric_box(fmt_pct(mean_awareness), "Caregiver awareness", gold),
          metric_box(if (is.na(mean_risk)) "—" else round(mean_risk,1), "Mean risk score", alert_red),
          metric_box(if (is.na(n_rounds))  "—" else n_rounds,           "Campaign rounds", dark_blue)
        ),
        div(style=paste0("font-size:.82rem;font-weight:700;color:",dark_blue,";margin-bottom:4px;"),
            paste0("Countries analysed: ", n_country, "  |  Districts analysed: ", n_district)),
        div(style="font-size:.74rem;color:#3A3A3A;margin-bottom:10px;",
            paste0("Critical events: ", risk_counts$critical,
                   "  |  High-risk events: ", risk_counts$high,
                   "  |  Moderate-risk events: ", risk_counts$moderate)),
        div(style="font-size:.68rem;color:#808080;",
            "Source: AFRO Independent Monitoring repository | District uniqueness: Country + Province + District")
      )
    )
  })

  output$data_freshness <- renderUI({
    if (is.null(rv$data)) return(div(tags$span(class="dot dot-err"), "No data loaded"))
    src_file <- Filter(file.exists, c(CLEANED_RDS, CLEANED_PARQUET, CLEANED_CSV, RAW_RDS))[1]
    if (is.na(src_file)) return(NULL)
    age <- difftime(Sys.time(), file.mtime(src_file), units="hours")
    cls <- if (age < 2) "dot-ok" else if (age < 24) "dot-warn" else "dot-err"
    div(tags$span(class=paste("dot",cls)),
        sprintf("%s rows · %s cols", fmt_num(nrow(rv$data)), ncol(rv$data)))
  })
  output$data_freshness_mini <- renderUI({
    src_file <- Filter(file.exists, c(CLEANED_RDS, CLEANED_PARQUET, CLEANED_CSV, RAW_RDS))[1]
    if (is.na(src_file)) return("—")
    format(file.mtime(src_file), "%Y-%m-%d %H:%M")
  })

  # ── Overview filtered data ────────────────────────────────────────────────────
  ov_data <- reactive({
    df <- rv$data; if (is.null(df)) return(NULL)

    if (!is.null(input$ov_block) && input$ov_block != "All" && "afro_block" %in% names(df))
      df <- df[!is.na(df$afro_block) & df$afro_block == input$ov_block, ]

    if (!is.null(input$ov_country) && input$ov_country != "All" && "country" %in% names(df))
      df <- df[!is.na(df$country) & df$country == input$ov_country, ]

    if (!is.null(input$ov_province) && input$ov_province != "All" && "province" %in% names(df))
      df <- df[!is.na(df$province) & df$province == input$ov_province, ]

    if (!is.null(input$ov_district) && input$ov_district != "All" && "district" %in% names(df))
      df <- df[!is.na(df$district) & df$district == input$ov_district, ]

    if (!is.null(input$ov_vaccine) && input$ov_vaccine != "All" && "vaccine_type" %in% names(df))
      df <- df[!is.na(df$vaccine_type) & df$vaccine_type == input$ov_vaccine, ]

    if (!is.null(input$ov_response) && input$ov_response != "All" && "response" %in% names(df))
      df <- df[!is.na(df$response) & df$response == input$ov_response, ]

    if (!is.null(input$ov_round) && length(input$ov_round) > 0 && "roundnumber" %in% names(df))
      df <- df[!is.na(df$roundnumber) & as.character(df$roundnumber) %in% input$ov_round, ]

    # Date filter
    # NOTE: variable named "df_dates" (not "dates") to avoid masking lubridate::dates generic
    dc    <- date_col_of(df)
    dtype <- input$ov_date_type %||% "All time"
    if (!is.na(dc) && dtype != "All time" && nrow(df) > 0) {
      df_dates <- suppressWarnings(as.Date(df[[dc]]))
      max_d    <- suppressWarnings(max(df_dates, na.rm=TRUE))

      if (!is.na(max_d) && is.finite(as.numeric(max_d))) {
        if (dtype == "Last N months" && !is.null(input$ov_n_months)) {
          cutoff <- max_d - months(as.integer(input$ov_n_months))
          df <- df[!is.na(df_dates) & df_dates >= cutoff, ]

        } else if (dtype == "Last N years" && !is.null(input$ov_n_years)) {
          cutoff <- max_d - years(as.integer(input$ov_n_years))
          df <- df[!is.na(df_dates) & df_dates >= cutoff, ]

        } else if (dtype == "Date range" && !is.null(input$ov_daterange)) {
          df <- df[!is.na(df_dates) & df_dates >= input$ov_daterange[1] &
                     df_dates <= input$ov_daterange[2], ]

        } else if (dtype == "Last N consecutive rounds" &&
                   !is.null(input$ov_n_rounds) && "roundnumber" %in% names(df)) {
          dc_local <- dc
          recent <- df %>%
            mutate(.tmp_d = as.Date(.data[[dc_local]])) %>%
            group_by(roundnumber) %>%
            summarise(last_d = max(.tmp_d, na.rm=TRUE), .groups="drop") %>%
            arrange(desc(last_d)) %>%
            slice_head(n=as.integer(input$ov_n_rounds)) %>%
            pull(roundnumber)
          df <- df[!is.na(df$roundnumber) & df$roundnumber %in% recent, ]

        } else if (dtype == "Last N rounds in last 12 months" &&
                   !is.null(input$ov_n_rounds_12m) && "roundnumber" %in% names(df)) {
          dc_local  <- dc
          cutoff_12m <- max_d - months(12L)
          recent <- df %>%
            mutate(.tmp_d = as.Date(.data[[dc_local]])) %>%
            filter(.tmp_d >= cutoff_12m) %>%          # restrict to last 12 months first
            group_by(roundnumber) %>%
            summarise(last_d = max(.tmp_d, na.rm=TRUE), .groups="drop") %>%
            arrange(desc(last_d)) %>%
            slice_head(n=as.integer(input$ov_n_rounds_12m)) %>%
            pull(roundnumber)
          df <- df[!is.na(df$roundnumber) & df$roundnumber %in% recent, ]
        }
      }
    }
    if (nrow(df) == 0) return(NULL)
    df
  })

  # %||% helper
  `%||%` <- function(a,b) if (!is.null(a)) a else b

  # ── Overview: dynamic cascade observers ──────────────────────────────────────
  # Block → Country
  observeEvent(input$ov_block, {
    req(rv$data); df <- rv$data
    if (!"country" %in% names(df)) return()
    ctrs <- if (input$ov_block == "All" || !"afro_block" %in% names(df))
      sort(unique(df$country[!is.na(df$country)]))
    else
      df %>% filter(afro_block==input$ov_block, !is.na(country)) %>%
             pull(country) %>% unique() %>% sort()
    updateSelectInput(session,"ov_country",  choices=c("All",ctrs), selected="All")
    updateSelectInput(session,"ov_province", choices=c("All"),       selected="All")
    updateSelectInput(session,"ov_district", choices=c("All"),       selected="All")
  }, ignoreInit=TRUE)

  # Country → Province
  observeEvent(input$ov_country, {
    req(rv$data); df <- rv$data
    if (input$ov_country == "All") {
      updateSelectInput(session,"ov_province",choices=c("All"),selected="All")
      updateSelectInput(session,"ov_district",choices=c("All"),selected="All")
      return()
    }
    df2 <- df
    if (!is.null(input$ov_block) && input$ov_block!="All" && "afro_block" %in% names(df2))
      df2 <- df2[!is.na(df2$afro_block) & df2$afro_block==input$ov_block, ]
    df2 <- df2[!is.na(df2$country) & df2$country==input$ov_country, ]
    provs <- sort(unique(df2$province[!is.na(df2$province)]))
    updateSelectInput(session,"ov_province",choices=c("All",provs),selected="All")
    updateSelectInput(session,"ov_district",choices=c("All"),selected="All")
  }, ignoreInit=TRUE)

  # Province → District
  observeEvent(input$ov_province, {
    req(rv$data); df <- rv$data
    if (input$ov_province == "All") {
      updateSelectInput(session,"ov_district",choices=c("All"),selected="All"); return()
    }
    df2 <- df
    if (!is.null(input$ov_country) && input$ov_country!="All" && "country" %in% names(df2))
      df2 <- df2[!is.na(df2$country) & df2$country==input$ov_country, ]
    df2 <- df2[!is.na(df2$province) & df2$province==input$ov_province, ]
    dists <- sort(unique(df2$district[!is.na(df2$district)]))
    updateSelectInput(session,"ov_district",choices=c("All",dists),selected="All")
  }, ignoreInit=TRUE)

  # Populate Overview sidebar choices on data load
  observeEvent(rv$data, {
    req(rv$data); df <- rv$data
    ctrs <- sort(unique(df$country[!is.na(df$country)]))
    vacs <- sort(unique(df$vaccine_type[!is.na(df$vaccine_type)]))
    resp <- sort(unique(df$response[!is.na(df$response)]))
    rnds <- sort(unique(as.character(df$roundnumber[!is.na(df$roundnumber)])))

    updateSelectInput(session,"ov_country",  choices=c("All",ctrs))
    updateSelectInput(session,"ov_province", choices=c("All"))
    updateSelectInput(session,"ov_district", choices=c("All"))
    updateSelectInput(session,"ov_vaccine",  choices=c("All",vacs))
    updateSelectInput(session,"ov_response", choices=c("All",resp))
    updateSelectizeInput(session,"ov_round", choices=rnds, selected=NULL)

    dc <- date_col_of(df)
    if (!is.na(dc)) {
      v <- suppressWarnings(as.Date(df[[dc]])); v <- v[!is.na(v)]
      if (length(v)) updateDateRangeInput(session,"ov_daterange",
                                          start=min(v), end=max(v))
    }
  }, ignoreInit=FALSE)

  # Reset overview filters
  observeEvent(input$ov_reset, {
    req(rv$data); df <- rv$data
    ctrs <- sort(unique(df$country[!is.na(df$country)]))
    vacs <- sort(unique(df$vaccine_type[!is.na(df$vaccine_type)]))
    resp <- sort(unique(df$response[!is.na(df$response)]))
    rnds <- sort(unique(as.character(df$roundnumber[!is.na(df$roundnumber)])))
    updateSelectInput(session,"ov_block",    selected="All")
    updateSelectInput(session,"ov_country",  choices=c("All",ctrs), selected="All")
    updateSelectInput(session,"ov_province", choices=c("All"),       selected="All")
    updateSelectInput(session,"ov_district", choices=c("All"),       selected="All")
    updateSelectInput(session,"ov_vaccine",  choices=c("All",vacs), selected="All")
    updateSelectInput(session,"ov_response", choices=c("All",resp), selected="All")
    updateSelectizeInput(session,"ov_round", choices=rnds, selected=NULL)
    updateSelectInput(session,"ov_date_type", selected="All time")
    showNotification("All filters reset.", type="message", duration=3)
  })

  # Filter badge
  output$ov_filter_badge <- renderUI({
    active_filters <- c(
      if (!is.null(input$ov_block)    && input$ov_block    != "All")         "Block",
      if (!is.null(input$ov_country)  && input$ov_country  != "All")         "Country",
      if (!is.null(input$ov_province) && input$ov_province != "All")         "Province",
      if (!is.null(input$ov_district) && input$ov_district != "All")         "District",
      if (!is.null(input$ov_vaccine)  && input$ov_vaccine  != "All")         "Vaccine",
      if (!is.null(input$ov_response) && input$ov_response != "All")         "Response",
      if (!is.null(input$ov_round)    && length(input$ov_round) > 0)         "Rounds",
      if (!is.null(input$ov_date_type)&& input$ov_date_type != "All time")   "Date"
    )
    n   <- length(active_filters)
    df  <- ov_data()
    rows <- if (!is.null(df)) fmt_num(nrow(df)) else "—"
    if (n == 0)
      div(style="color:rgba(255,255,255,.45);font-size:.72rem;margin-bottom:4px;",
          paste0("Showing all data (", rows, " records)"))
    else
      div(style="margin-bottom:4px;",
        div(style="color:rgba(255,255,255,.55);font-size:.7rem;",
            paste0(n," filter(s) active · ",rows," records")),
        div(style="display:flex;flex-wrap:wrap;gap:4px;margin-top:4px;",
          lapply(active_filters, function(f)
            tags$span(class="badge",
                      style="background:rgba(0,201,200,.25);color:rgba(255,255,255,.9);
                             font-size:.65rem;padding:3px 7px;border-radius:6px;", f)))
      )
  })

  # Dynamic card titles
  output$chart_cv_title <- renderUI({
    geo <- c(input$ov_district, input$ov_province, input$ov_country)
    geo <- geo[!is.null(geo) & geo != "All"]
    if (length(geo))
      tagList(bs_icon("bar-chart-fill", class = "me-2", style = "vertical-align:-0.15em;"),
              "CV by Area in ", tags$b(geo[1]))
    else
      tagList(bs_icon("bar-chart-fill", class = "me-2", style = "vertical-align:-0.15em;"),
              "Coverage (CV) by Country")
  })
  output$chart_topbot_title <- renderUI({
    lv <- if (!is.null(input$ov_country) && input$ov_country != "All") "Province"
          else if (!is.null(input$ov_block) && input$ov_block != "All") "Country"
          else "Country"
    tagList(bs_icon("trophy-fill", class = "me-2", style = "vertical-align:-0.15em;"),
            paste0("Top 5 vs Bottom 5 (", lv, ")"))
  })

  # Re-animate KPIs whenever ov_data changes
  observeEvent(ov_data(), {
    df <- ov_data(); if (is.null(df)) return()

    session$sendCustomMessage("countUp", list(id="v_records", v=nrow(df), ms=800, delay=0))

    if ("country" %in% names(df))
      session$sendCustomMessage("countUp",
        list(id="v_countries", v=n_distinct(df$country,na.rm=TRUE), ms=700, delay=50))

    if (all(c("u5_fm","u5_present") %in% names(df))) {
      tp <- as.numeric(sum(df$u5_present,na.rm=TRUE))
      tf <- as.numeric(sum(df$u5_fm,     na.rm=TRUE))
      mc <- pmax(tp-tf, 0)
      if (tp > 0) {
        session$sendCustomMessage("countUp",
          list(id="v_cv",     v=round(tf/tp*100,1), ms=900, pct=TRUE,  delay=80,  bar_max=90))
        session$sendCustomMessage("countUp",
          list(id="v_missed", v=round(mc),           ms=800, delay=100))
      }
    }

    if ("number_of_hh_visited" %in% names(df))
      session$sendCustomMessage("countUp",
        list(id="v_hh", v=round(sum(as.numeric(df$number_of_hh_visited),na.rm=TRUE)),
             ms=800, delay=120))

    if (all(c("number_of_hh_visited","care_giver_informed_sia") %in% names(df))) {
      th <- sum(as.numeric(df$number_of_hh_visited),    na.rm=TRUE)
      ti <- sum(as.numeric(df$care_giver_informed_sia), na.rm=TRUE)
      if (th > 0)
        session$sendCustomMessage("countUp",
          list(id="v_awareness", v=round(ti/th*100,1), ms=900, pct=TRUE, delay=140, bar_max=80))
    }

    dfr <- tryCatch(with_risk(df), error=function(e) NULL)
    if (!is.null(dfr) && "risk_class" %in% names(dfr)) {
      crit <- dfr %>%
        group_by(country,province,district) %>%
        summarise(rc=first(risk_class),.groups="drop") %>%
        filter(rc=="Critical") %>% nrow()
      session$sendCustomMessage("countUp",
        list(id="v_risk_crit", v=crit, ms=700, delay=160))
    }
  }, ignoreNULL=TRUE)

  output$v_run <- renderText({
    info <- last_run_info()
    updateTextInput(session, "v_run_placeholder", value=info$time)
    info$time
  })

  observe({
    info <- last_run_info()
    shinyjs::html("v_run", info$time)
  })

  observeEvent(input$btn_refresh, {
    rv$data <- load_im_data(); showNotification("Data refreshed.", type="message")
  })
  observeEvent(input$btn_rl_data, {
    rv$data <- load_im_data(); showNotification("Data reloaded.", type="message")
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

  # ── Overview charts ──────────────────────────────────────────────────────────
  output$chart_cv <- renderPlotly({
    df <- ov_data(); req(df)
    # Decide grouping level based on active filters
    grp <- if (!is.null(input$ov_district) && input$ov_district != "All") "province"
           else if (!is.null(input$ov_province) && input$ov_province != "All") "district"
           else if (!is.null(input$ov_country)  && input$ov_country  != "All") "province"
           else "country"
    grp <- intersect(grp, names(df))
    if (!length(grp) || !all(c("u5_fm","u5_present") %in% names(df))) return(NULL)
    grp <- grp[1]

    smry <- df %>%
      group_by(.data[[grp]]) %>%
      summarise(cv=sum(as.numeric(u5_fm),na.rm=T)/
                   pmax(sum(as.numeric(u5_present),na.rm=T),1),
                n=n(), .groups="drop") %>%
      mutate(cv=pmin(cv,1),
             col=case_when(cv>=.9~C_$green, cv>=.8~C_$orange, TRUE~C_$red)) %>%
      arrange(cv) %>% slice_tail(n=35)

    plot_ly(smry, x=~cv, y=~reorder(.data[[grp]],cv), type="bar", orientation="h",
            marker=list(color=~col, line=list(width=0)),
            text=~paste0(fmt_pct(cv)," · ",fmt_num(n)," records"),
            textposition="outside", insidetextanchor="start",
            hovertemplate="%{y}<br>CV: %{x:.1%}<extra></extra>") %>%
      im_layout(
             .title    = paste0("Coverage (CV) by ", tools::toTitleCase(grp)),
             .filename = "IM_cv_chart",
             xaxis=list(title="Coverage Rate", tickformat=".0%", range=c(0,1.15),
                        showgrid=TRUE, gridcolor="rgba(0,92,151,.07)"),
             yaxis=list(title="", tickfont=list(size=11)),
             margin=list(l=130,r=90,b=40),
             shapes=list(
               list(type="line",x0=.9,x1=.9,y0=-.5,y1=nrow(smry)-.5,
                    line=list(color=C_$green, dash="dot",width=1.5)),
               list(type="line",x0=.8,x1=.8,y0=-.5,y1=nrow(smry)-.5,
                    line=list(color=C_$orange,dash="dot",width=1.5))
             ))
  })

  output$chart_qc_pie <- renderPlotly({
    df <- ov_data(); req(df)
    qc_col <- intersect(c("qc_flag","reconciliation_flag"), names(df))[1]
    if (is.na(qc_col)) return(NULL)

    tbl <- df %>% count(!!sym(qc_col),name="n") %>% rename(flag=1) %>%
           filter(!is.na(flag)) %>% arrange(desc(n))

    pal <- case_when(tbl$flag=="OK" ~ C_$green,
                     grepl("review",tbl$flag,ignore.case=T) ~ C_$orange,
                     TRUE ~ C_$red)

    plot_ly(tbl, labels=~flag, values=~n, type="pie",
            marker=list(colors=pal, line=list(color="#F0F4F8",width=2)),
            textinfo="label+percent",
            hovertemplate="%{label}<br><b>%{value:,}</b> records<extra></extra>",
            hole=0.38) %>%
      im_layout(
             .title    = "QC Flag Distribution",
             .filename = "IM_qc_flags",
             showlegend=TRUE,
             legend=list(orientation="h",y=-.12,font=list(size=11)))
  })

  output$chart_trend <- renderPlotly({
    df <- ov_data(); req(df)
    dc <- date_col_of(df); if (is.na(dc)) return(NULL)

    has_cv_cols <- all(c("u5_fm","u5_present") %in% names(df))
    agg <- df %>%
      mutate(period = floor_date(as.Date(.data[[dc]]), "month")) %>%
      filter(!is.na(period), period >= as.Date("2020-01-01")) %>%
      group_by(period) %>%
      summarise(
        records = n(),
        cv = if (has_cv_cols)
               sum(as.numeric(u5_fm), na.rm=TRUE) /
               pmax(sum(as.numeric(u5_present), na.rm=TRUE), 1)
             else NA_real_,
        .groups = "drop"
      )

    p <- plot_ly(agg, x=~period)
    p <- add_bars(p, y=~records, name="Records",
                  marker=list(color=C_$blue, opacity=.75,
                              line=list(color=C_$blue2,width=.5)))
    if (!all(is.na(agg$cv)))
      p <- add_lines(p, y=~cv, name="CV", yaxis="y2",
                     line=list(color=C_$green, width=2.5, shape="spline"),
                     fill="tozeroy", fillcolor="rgba(39,174,96,.08)")

    im_layout(p,
           .title    = "Records & Coverage Trend Over Time",
           .filename = "IM_trend",
           yaxis=list(title="Records", showgrid=TRUE,
                      gridcolor="rgba(0,92,151,.07)"),
           yaxis2=list(title="CV", overlaying="y", side="right",
                       tickformat=".0%", range=c(0,1.1)),
           xaxis=list(title="", showgrid=FALSE),
           legend=list(orientation="h",y=-.22))
  })

  # ── Block performance chart ───────────────────────────────────────────────────
  output$chart_block <- renderPlotly({
    df <- ov_data(); req(df)
    if (!all(c("u5_fm","u5_present") %in% names(df))) return(NULL)

    # If a specific block is selected, drill down to country level
    block_selected <- !is.null(input$ov_block) && input$ov_block != "All"

    if (block_selected && "country" %in% names(df)) {
      # Country-level bar chart for the selected block
      smry <- df %>%
        group_by(x_var = country) %>%
        summarise(
          cv      = sum(as.numeric(u5_fm),na.rm=T) /
                    pmax(sum(as.numeric(u5_present),na.rm=T),1),
          records = n(), .groups = "drop"
        ) %>%
        filter(!is.na(x_var)) %>%
        mutate(cv = pmin(cv, 1),
               col = case_when(cv>=.9~C_$green, cv>=.8~C_$orange, TRUE~C_$red)) %>%
        arrange(desc(cv))

      x_n    <- nrow(smry)
      x_title <- paste0("Countries in ", input$ov_block)
    } else {
      blocks <- c("LCB","WA","DRC","CEA","ESA")
      if (!"afro_block" %in% names(df)) return(NULL)
      smry <- df %>%
        filter(afro_block %in% blocks) %>%
        group_by(x_var = afro_block) %>%
        summarise(
          cv      = sum(as.numeric(u5_fm),na.rm=T) /
                    pmax(sum(as.numeric(u5_present),na.rm=T),1),
          records = n(), .groups = "drop"
        ) %>%
        mutate(cv = pmin(cv, 1),
               col = case_when(cv>=.9~C_$green, cv>=.8~C_$orange, TRUE~C_$red),
               x_var = factor(x_var, levels=blocks)) %>%
        arrange(x_var)

      x_n     <- 5
      x_title <- "AFRO Block"
    }

    if (!nrow(smry)) return(NULL)
    chart_title <- if (block_selected) paste0("CV by Country — ", input$ov_block)
                   else "CV Performance by AFRO Block"

    plot_ly(smry,
            x = ~x_var, y = ~cv, type = "bar",
            marker = list(color = ~col,
                          line  = list(color="rgba(255,255,255,.3)", width=1.5)),
            text  = ~paste0(fmt_pct(cv)),
            textposition = "outside",
            customdata = ~records,
            hovertemplate = "<b>%{x}</b><br>CV: %{y:.1%}<br>Records: %{customdata:,}<extra></extra>") %>%
      im_layout(
        .title    = chart_title,
        .filename = "IM_block_cv",
        xaxis  = list(title=x_title, showgrid=FALSE, tickangle=if(x_n>6) -35 else 0),
        yaxis  = list(title="Coverage Rate", tickformat=".0%",
                      range=c(0,1.18), showgrid=TRUE,
                      gridcolor="rgba(0,92,151,.07)"),
        shapes = list(
          list(type="line", x0=-.5, x1=x_n-.5, y0=.9, y1=.9,
               line=list(color=C_$green, dash="dot", width=2)),
          list(type="line", x0=-.5, x1=x_n-.5, y0=.8, y1=.8,
               line=list(color=C_$orange, dash="dot", width=1.5))
        ),
        annotations = list(
          list(x=x_n-.5, y=.9,  text="90% target", showarrow=FALSE,
               font=list(color=C_$green,  size=10), xanchor="right"),
          list(x=x_n-.5, y=.8,  text="80% min",    showarrow=FALSE,
               font=list(color=C_$orange, size=10), xanchor="right")
        )
      )
  })

  # ── Alert: countries below 80% CV ────────────────────────────────────────────
  output$alert_low_cv <- renderUI({
    df <- ov_data(); req(df)
    if (!all(c("u5_fm","u5_present") %in% names(df))) return(
      div(class="text-muted p-3 small", "CV data not available."))

    # Drill-down: province when country selected, district when province selected
    grp <- if (!is.null(input$ov_province) && input$ov_province != "All") "district"
           else if (!is.null(input$ov_country) && input$ov_country != "All") "province"
           else "country"
    grp <- intersect(grp, names(df))[1]
    if (is.na(grp)) return(div(class="text-muted p-3 small", "Geographic data not available."))

    grp_label <- switch(grp, country="countries", province="provinces", district="districts", grp)

    low <- df %>%
      group_by(.data[[grp]]) %>%
      summarise(cv = sum(as.numeric(u5_fm),na.rm=T) /
                     pmax(sum(as.numeric(u5_present),na.rm=T),1),
                n  = n(), .groups="drop") %>%
      filter(!is.na(.data[[grp]]), cv < .8) %>%
      mutate(cv=pmin(cv,1)) %>%
      arrange(cv) %>%
      slice_head(n=10)

    if (!nrow(low)) return(
      div(class="d-flex align-items-center justify-content-center",
          style="height:160px;",
        div(
          div(style="text-align:center;",
              bs_icon("check-circle-fill", size="2.5rem", style="color:#27AE60;")),
          div(style="color:#27AE60;font-weight:700;text-align:center;margin-top:8px;",
              paste0("All ", grp_label, " above 80% CV!"))
        )
      )
    )

    tagList(
      div(style="font-size:.72rem;color:var(--muted);font-weight:700;
                 letter-spacing:.06em;text-transform:uppercase;padding:8px 12px 4px;",
          paste0(nrow(low), " ", grp_label, " need attention")),
      lapply(seq_len(nrow(low)), function(i) {
        r   <- low[i,]
        pct <- round(r$cv * 100, 1)
        col <- if(pct < 60) C_$red else C_$orange
        div(style="padding:7px 12px;border-bottom:1px solid rgba(0,92,151,.05);
                   display:flex;align-items:center;justify-content:space-between;",
          div(style="font-size:.82rem;font-weight:600;", r[[grp]]),
          div(style="display:flex;align-items:center;gap:8px;",
            div(style=paste0("width:80px;height:6px;background:#eee;border-radius:3px;overflow:hidden;"),
              div(style=paste0("width:",pct,"%  ;height:100%;background:",col,
                               ";border-radius:3px;transition:.4s;"))
            ),
            div(style=paste0("font-size:.8rem;font-weight:700;color:",col,";min-width:38px;"),
                paste0(pct,"%"))
          )
        )
      })
    )
  })

  # ── Top 5 / Bottom 5 performers ───────────────────────────────────────────────
  output$chart_top_bottom <- renderPlotly({
    df <- ov_data(); req(df)
    if (!all(c("u5_fm","u5_present") %in% names(df))) return(NULL)

    # Drill-down grouping
    grp <- if (!is.null(input$ov_province) && input$ov_province != "All") "district"
           else if (!is.null(input$ov_country) && input$ov_country != "All") "province"
           else "country"
    grp <- intersect(grp, names(df))[1]
    if (is.na(grp)) return(NULL)

    grp_label <- tools::toTitleCase(grp)

    smry <- df %>%
      group_by(.data[[grp]]) %>%
      summarise(cv = sum(as.numeric(u5_fm),na.rm=T) /
                     pmax(sum(as.numeric(u5_present),na.rm=T),1),
                n  = n(), .groups="drop") %>%
      filter(!is.na(.data[[grp]]), n >= 5) %>%
      mutate(cv = pmin(cv,1)) %>%
      arrange(cv)

    if (nrow(smry) < 2) return(NULL)

    n_each <- min(5, floor(nrow(smry)/2))
    top_n  <- tail(smry, n_each) %>% mutate(grp_label=paste0("Top ", n_each))
    bot_n  <- head(smry, n_each) %>% mutate(grp_label=paste0("Bottom ", n_each))
    tbl    <- bind_rows(bot_n, top_n)
    col_map <- setNames(c(C_$green, C_$red),
                        c(paste0("Top ", n_each), paste0("Bottom ", n_each)))

    plot_ly(tbl,
            x = ~cv, y = ~reorder(.data[[grp]], cv), type = "bar", orientation = "h",
            color = ~grp_label, colors = col_map,
            marker = list(line=list(width=0)),
            text   = ~paste0(fmt_pct(cv)),
            textposition = "outside",
            hovertemplate = paste0("%{y}<br>CV: %{x:.1%}<br>Records: %{customdata:,}<extra></extra>"),
            customdata = ~n) %>%
      im_layout(
        .title    = paste0("Top vs Bottom ", grp_label, "s — Coverage"),
        .filename = "IM_top_bottom",
        xaxis  = list(title=paste0("Coverage Rate by ", grp_label), tickformat=".0%",
                      range=c(0,1.18), showgrid=TRUE,
                      gridcolor="rgba(0,92,151,.07)"),
        yaxis  = list(title="", tickfont=list(size=11)),
        legend = list(orientation="h", y=-.18),
        margin = list(l=110, r=70, b=30),
        shapes = list(
          list(type="line", x0=.9,x1=.9,y0=-.5,y1=nrow(tbl)-.5,
               line=list(color=C_$green,dash="dot",width=1.5))
        )
      )
  })

  # ── Heatmap: geo-level × round ────────────────────────────────────────────────
  output$chart_heatmap <- renderPlotly({
    df <- ov_data(); req(df)
    if (!all(c("u5_fm","u5_present") %in% names(df))) return(NULL)

    # Drill-down Y-axis grouping
    grp_y <- if (!is.null(input$ov_province) && input$ov_province != "All") "district"
             else if (!is.null(input$ov_country) && input$ov_country != "All") "province"
             else "country"
    grp_y <- intersect(grp_y, names(df))[1]
    if (is.na(grp_y)) return(NULL)

    y_label <- tools::toTitleCase(grp_y)

    # X-axis: use roundnumber if available, else quarter
    if ("roundnumber" %in% names(df) && !all(is.na(df$roundnumber))) {
      agg <- df %>%
        filter(!is.na(.data[[grp_y]]), !is.na(roundnumber)) %>%
        group_by(geo=.data[[grp_y]], round=as.character(roundnumber)) %>%
        summarise(cv=sum(as.numeric(u5_fm),na.rm=T)/
                       pmax(sum(as.numeric(u5_present),na.rm=T),1),
                  .groups="drop") %>%
        mutate(cv=pmin(pmax(cv,0),1))
      x_title <- "Campaign Round"
    } else {
      dc <- date_col_of(df)
      if (is.na(dc)) return(NULL)
      agg <- df %>%
        filter(!is.na(.data[[grp_y]])) %>%
        mutate(round=format(floor_date(as.Date(.data[[dc]]),"quarter"), "%Y Q%q")) %>%
        filter(!is.na(round)) %>%
        group_by(geo=.data[[grp_y]], round) %>%
        summarise(cv=sum(as.numeric(u5_fm),na.rm=T)/
                       pmax(sum(as.numeric(u5_present),na.rm=T),1),
                  .groups="drop") %>%
        mutate(cv=pmin(pmax(cv,0),1))
      x_title <- "Quarter"
    }

    if (!nrow(agg)) return(NULL)

    # Pivot to matrix
    rounds <- sort(unique(agg$round))
    geos   <- agg %>% group_by(geo) %>%
              summarise(m=mean(cv,na.rm=T),.groups="drop") %>%
              arrange(m) %>% pull(geo)

    mat <- matrix(NA_real_, nrow=length(geos), ncol=length(rounds),
                  dimnames=list(geos, rounds))
    for (i in seq_len(nrow(agg)))
      mat[agg$geo[i], agg$round[i]] <- agg$cv[i]

    text_mat <- matrix(
      ifelse(is.na(mat), "—", paste0(round(mat*100,1),"%")),
      nrow=nrow(mat)
    )

    plot_ly(
      x = rounds, y = geos,
      z = mat,
      type = "heatmap",
      colorscale = list(
        c(0,   "#C0392B"),
        c(0.5, "#E8730A"),
        c(0.8, "#F1C40F"),
        c(0.9, "#27AE60"),
        c(1,   "#1A7A44")
      ),
      zmin=0, zmax=1,
      text = text_mat, hovertemplate=paste0("%{y} · %{x}<br>CV: %{text}<extra></extra>"),
      colorbar=list(title="CV",tickformat=".0%",
                    len=0.8, thickness=14,
                    tickvals=c(0,.5,.8,.9,1))
    ) %>%
      im_layout(
        .title    = paste0("CV Heatmap: ", y_label, " × ", x_title),
        .filename = "IM_heatmap",
        xaxis  = list(title=x_title, tickangle=-35, showgrid=FALSE),
        yaxis  = list(title=y_label, showgrid=FALSE, tickfont=list(size=11)),
        margin = list(l=120, r=80, b=60)
      )
  })

  # ── CV95 proportion table (Country × Vaccine × Month) ───────────────────────
  cv95_tbl <- reactive({
    df <- ov_data(); req(df)
    dc <- date_col_of(df)
    if (is.na(dc)) return(NULL)
    if (!all(c("u5_fm","u5_present") %in% names(df))) return(NULL)

    uid_cols <- intersect(c("country","province","district"), names(df))
    row_grp  <- intersect(c("country","vaccine_type"), names(df))
    if (!"country" %in% row_grp) return(NULL)

    df2 <- df %>%
      mutate(
        cam_date    = as.Date(.data[[dc]]),
        yr          = lubridate::year(cam_date),
        mo          = lubridate::month(cam_date),
        # Always English: "Nov '25" style
        period      = paste0(month.abb[lubridate::month(cam_date)], " '",
                             substr(as.character(lubridate::year(cam_date)), 3, 4)),
        period_key  = paste0(lubridate::year(cam_date),
                             sprintf("%02d", lubridate::month(cam_date))),
        district_id = do.call(paste, c(as.list(.[uid_cols]), list(sep="|")))
      ) %>%
      filter(!is.na(period), !is.na(district_id))

    df2 %>%
      group_by(across(all_of(c(row_grp, "yr", "mo", "period", "period_key", "district_id")))) %>%
      summarise(
        dist_cv = sum(as.numeric(u5_fm), na.rm=TRUE) /
                  pmax(sum(as.numeric(u5_present), na.rm=TRUE), 1),
        .groups = "drop"
      ) %>%
      group_by(across(all_of(c(row_grp, "yr", "mo", "period", "period_key")))) %>%
      summarise(
        n_dist    = n_distinct(district_id),
        n_cv95    = sum(dist_cv >= 0.95),
        prop_cv95 = n_cv95 / n_dist,
        .groups   = "drop"
      ) %>%
      arrange(period_key)
  })

  output$chart_cv95 <- renderPlotly({
    tbl <- cv95_tbl(); req(tbl)
    if (!nrow(tbl)) return(NULL)

    row_grp <- intersect(c("country","vaccine_type"), names(tbl))

    tbl <- tbl %>%
      mutate(row_lbl = if (length(row_grp) > 1)
               paste0(.data[[row_grp[1]]], "  ·  ", .data[[row_grp[2]]])
             else
               .data[[row_grp[1]]])

    row_order    <- tbl %>% distinct(row_lbl) %>% arrange(row_lbl) %>% pull(row_lbl)
    period_order <- tbl %>% distinct(period_key, period) %>%
                    arrange(period_key) %>% pull(period)

    rows    <- rev(row_order)   # alphabetical top-to-bottom
    periods <- period_order

    # Build value & count matrices
    mat <- matrix(NA_real_, nrow=length(rows), ncol=length(periods),
                  dimnames=list(rows, periods))
    cnt <- matrix("",       nrow=length(rows), ncol=length(periods),
                  dimnames=list(rows, periods))

    for (i in seq_len(nrow(tbl))) {
      r <- tbl$row_lbl[i]; p <- tbl$period[i]
      mat[r, p] <- tbl$prop_cv95[i]
      cnt[r, p] <- paste0(tbl$n_cv95[i], " / ", tbl$n_dist[i], " districts")
    }

    hover_mat <- matrix("", nrow=length(rows), ncol=length(periods))
    for (ri in seq_along(rows))
      for (ci in seq_along(periods)) {
        v <- mat[rows[ri], periods[ci]]
        hover_mat[ri, ci] <- if (!is.na(v))
          paste0(rows[ri], "<br>", periods[ci],
                 "<br><b>", round(v*100,1), "%</b> of districts ≥95% CV",
                 "<br>", cnt[rows[ri], periods[ci]])
        else paste0(rows[ri], "<br>", periods[ci], "<br>No data")
      }

    # Bold percentage annotations inside each filled cell
    annots <- list()
    for (ri in seq_along(rows)) {
      for (ci in seq_along(periods)) {
        v <- mat[rows[ri], periods[ci]]
        if (!is.na(v)) {
          # Light text on dark cells (red/green), dark text on yellow cells
          txt_col <- if (v < 0.78 || v >= 0.95) "white" else "#1A2637"
          annots <- c(annots, list(list(
            x         = periods[ci],
            y         = rows[ri],
            text      = paste0("<b>", round(v * 100, 1), "%</b>"),
            showarrow = FALSE,
            font      = list(size = 11, color = txt_col, family = "Inter, sans-serif")
          )))
        }
      }
    }

    plot_ly(
      x    = periods, y = rows,
      z    = mat,
      type = "heatmap",
      text = hover_mat,
      hovertemplate = "%{text}<extra></extra>",
      # Sharp threshold colour scale: <80 red | 80-95 amber | ≥95 green
      colorscale = list(
        c(0,     "#B71C1C"),   # 0 %  deep red
        c(0.599, "#E53935"),   # 59 % red
        c(0.600, "#E53935"),
        c(0.799, "#EF6C00"),   # 79 % orange-red
        c(0.800, "#FFB300"),   # 80 % amber threshold
        c(0.944, "#FFD600"),   # 94 % yellow
        c(0.945, "#2E7D32"),   # 95 % green threshold
        c(1,     "#1B5E20")    # 100 % deep green
      ),
      zmin     = 0, zmax = 1,
      xgap     = 3, ygap = 3,   # modern tile-gap look
      colorbar = list(
        title      = list(text = "% Districts<br>≥ 95% CV",
                          font = list(size = 11, color = "#4A5568")),
        tickformat = ".0%",
        len        = 0.65, thickness = 12,
        outlinewidth = 0,
        tickvals   = c(0, 0.80, 0.95, 1),
        ticktext   = c("0 %", "80 %", "95 %", "100 %"),
        tickfont   = list(size = 10)
      )
    ) %>%
      im_layout(
        .title    = "% of Districts Achieving ≥ 95% CV — Country · Vaccine Type · Month",
        .filename = "IM_cv95_heatmap",
        xaxis      = list(title      = "",
                          tickangle  = -40,
                          showgrid   = FALSE,
                          tickfont   = list(size = 11, color = "#4A5568", family = "Inter")),
        yaxis      = list(title      = "",
                          showgrid   = FALSE,
                          tickfont   = list(size = 10, color = "#1A2637", family = "Inter")),
        margin     = list(l = 210, r = 80, t = 10, b = 70),
        annotations = annots,
        plot_bgcolor  = "#F8FAFC",   # very light blue-grey tile background
        paper_bgcolor = "rgba(0,0,0,0)"
      )
  })

  # ── Risk distribution donut ───────────────────────────────────────────────────
  output$chart_risk_dist <- renderPlotly({
    df <- ov_data(); req(df)
    dfr <- tryCatch(with_risk(df), error=function(e) NULL)
    if (is.null(dfr) || !"risk_class" %in% names(dfr)) return(NULL)

    tbl <- dfr %>%
      group_by(country, province, district) %>%
      summarise(risk_class=first(risk_class), .groups="drop") %>%
      count(risk_class) %>%
      mutate(
        risk_class = factor(risk_class, levels=c("Critical","High","Moderate","Low")),
        col = case_when(
          risk_class=="Critical" ~ C_$red,
          risk_class=="High"     ~ C_$orange,
          risk_class=="Moderate" ~ C_$blue,
          TRUE                   ~ C_$green
        )
      ) %>% arrange(risk_class)

    plot_ly(tbl, labels=~risk_class, values=~n, type="pie", hole=0.52,
            marker=list(colors=~col, line=list(color="#F0F4F8", width=3)),
            textinfo="label+percent",
            hovertemplate="<b>%{label}</b><br>%{value:,} districts<br>%{percent}<extra></extra>") %>%
      im_layout(
        .title    = "District Risk Classification",
        .filename = "IM_risk_dist",
        showlegend=TRUE,
        legend=list(orientation="h", y=-.15, font=list(size=11)),
        annotations=list(list(
          text=paste0("<b>",sum(tbl$n,na.rm=TRUE),"</b><br>districts"),
          x=0.5, y=0.5, showarrow=FALSE,
          font=list(size=14, color=C_$dark)
        ))
      )
  })

  # ── SM Quadrant bubble chart (star chart) ─────────────────────────────────────
  output$chart_sm_quadrant <- renderPlotly({
    df <- ov_data(); req(df)
    dfr <- tryCatch(with_risk(df), error=function(e) NULL)
    if (is.null(dfr) || !"awareness_rate" %in% names(dfr)) return(
      plotly_empty() %>% im_layout() %>%
        add_annotations(text="⚠️ Awareness data (care_giver_informed_sia) not available in this dataset",
                        showarrow=FALSE, font=list(size=13, color=C_$muted))
    )
    if (all(is.na(dfr$awareness_rate))) return(
      plotly_empty() %>% im_layout() %>%
        add_annotations(text="⚠️ Awareness data is all NA — column exists but has no values",
                        showarrow=FALSE, font=list(size=13, color=C_$muted))
    )

    grp_cols <- intersect(c("country","province","district"), names(dfr))
    s <- dfr %>%
      group_by(across(all_of(grp_cols))) %>%
      summarise(
        cv_d           = sum(as.numeric(u5_fm),na.rm=T)/pmax(sum(as.numeric(u5_present),na.rm=T),1),
        awareness_rate = mean(awareness_rate, na.rm=TRUE),
        missed_child   = sum(as.numeric(missed_child), na.rm=TRUE),
        .groups="drop"
      ) %>%
      filter(!is.na(awareness_rate), !is.na(cv_d),
             is.finite(awareness_rate), is.finite(cv_d)) %>%
      mutate(
        # Labels match generate_afro_im_intelligence_report() exactly
        quadrant = case_when(
          awareness_rate <  0.80 & cv_d <  0.90 ~ "Low awareness + low coverage",
          awareness_rate <  0.80 & cv_d >= 0.90 ~ "Low awareness but acceptable coverage",
          awareness_rate >= 0.80 & cv_d <  0.90 ~ "High awareness but low coverage",
          TRUE                                   ~ "High awareness + good coverage"
        ),
        sz  = pmax(pmin(sqrt(missed_child + 1) * 1.5, 28), 5),
        # Advocacy message per district (mirrors priority_districts advocacy_message)
        advocacy = case_when(
          awareness_rate < 0.80 ~
            "Pre-campaign social mobilisation and household awareness should be intensified.",
          TRUE ~
            "Continue routine monitoring and rapid corrective action."
        ),
        lbl = paste0(
          if ("district" %in% names(.)) district else "",
          if ("country"  %in% names(.)) paste0(" (", country, ")") else "",
          "<br>Awareness: ", fmt_pct(awareness_rate),
          " | CV: ", fmt_pct(cv_d),
          "<br>Missed: ", fmt_num(missed_child),
          "<br><i>", advocacy, "</i>")
      )

    if (nrow(s) == 0) return(NULL)
    s <- slice_sample(s, n = min(2000, nrow(s)))

    # Quadrant definitions — labels and colours aligned to report script
    q_defs <- list(
      list(q   = "Low awareness + low coverage",
           col = C_$red,
           adv = "Pre-campaign social mobilisation and household awareness should be intensified."),
      list(q   = "Low awareness but acceptable coverage",
           col = C_$orange,
           adv = "Pre-campaign social mobilisation and household awareness should be intensified."),
      list(q   = "High awareness but low coverage",
           col = C_$purple,
           adv = "Investigate operational barriers; strengthen vaccinator accountability and microplan."),
      list(q   = "High awareness + good coverage",
           col = C_$blue,
           adv = "Continue routine monitoring and rapid corrective action.")
    )

    # Build one trace per quadrant (enables named legend + correct PNG export)
    p <- plot_ly()
    for (qd in q_defs) {
      sub <- s[s$quadrant == qd$q, ]
      if (!nrow(sub)) next
      p <- add_trace(p,
        data        = sub,
        x           = ~awareness_rate, y = ~cv_d,
        type        = "scatter", mode = "markers",
        name        = qd$q,
        legendgroup = qd$q,
        marker      = list(color   = qd$col,
                           size    = ~sz,
                           opacity = 0.72,
                           line    = list(color = "white", width = 0.8)),
        text              = ~lbl,
        hoverinfo         = "text",
        showlegend        = TRUE
      )
    }

    # Count per quadrant for annotation
    q_counts <- table(s$quadrant)
    ann_lbl <- function(q) {
      n <- if (q %in% names(q_counts)) q_counts[[q]] else 0
      paste0("<b>", q, "</b><br><span style='font-size:9px'>", n, " areas</span>")
    }

    # Advocacy annotation: quadrant with most missed children
    worst_q <- s %>%
      group_by(quadrant) %>%
      summarise(tot_missed = sum(missed_child, na.rm=TRUE), .groups="drop") %>%
      arrange(desc(tot_missed)) %>%
      slice_head(n=1)

    adv_msg <- ""
    if (nrow(worst_q) > 0) {
      qd_match <- Filter(function(x) x$q == worst_q$quadrant[1], q_defs)
      if (length(qd_match))
        adv_msg <- paste0("<b>Priority quadrant:</b> ", worst_q$quadrant[1],
                          "<br>", qd_match[[1]]$adv)
    }

    im_layout(p,
      .title    = "Social Mobilisation Awareness vs Vaccination Coverage",
      .filename = "IM_sm_quadrant",
      xaxis = list(title = "Caregiver Awareness Rate (%)", tickformat = ".0%",
                   range = c(-.02, 1.05), showgrid = TRUE,
                   gridcolor = "rgba(0,92,151,.07)", zeroline = FALSE),
      yaxis = list(title = "Vaccination Coverage — CV (%)", tickformat = ".0%",
                   range = c(-.02, 1.08), showgrid = TRUE,
                   gridcolor = "rgba(0,92,151,.07)", zeroline = FALSE),
      showlegend = TRUE,
      shapes = list(
        list(type="line", x0=.8, x1=.8, y0=0, y1=1.08,
             line=list(color=C_$muted, dash="dot", width=1.5)),
        list(type="line", x0=0, x1=1.05, y0=.9, y1=.9,
             line=list(color=C_$muted, dash="dot", width=1.5))
      ),
      annotations = list(
        # Quadrant corner labels with counts (labels match report script)
        list(x=.39,  y=1.06, text=ann_lbl("Low awareness but acceptable coverage"),
             showarrow=FALSE, font=list(color=C_$orange, size=10),
             bgcolor="rgba(255,255,255,.82)", bordercolor=C_$orange,
             borderwidth=1, borderpad=4, xanchor="center"),
        list(x=.39,  y=.48,  text=ann_lbl("Low awareness + low coverage"),
             showarrow=FALSE, font=list(color=C_$red,    size=10),
             bgcolor="rgba(255,255,255,.82)", bordercolor=C_$red,
             borderwidth=1, borderpad=4, xanchor="center"),
        list(x=.92,  y=.48,  text=ann_lbl("High awareness but low coverage"),
             showarrow=FALSE, font=list(color=C_$purple, size=10),
             bgcolor="rgba(255,255,255,.82)", bordercolor=C_$purple,
             borderwidth=1, borderpad=4, xanchor="center"),
        list(x=.92,  y=1.06, text=ann_lbl("High awareness + good coverage"),
             showarrow=FALSE, font=list(color=C_$blue,   size=10),
             bgcolor="rgba(255,255,255,.82)", bordercolor=C_$blue,
             borderwidth=1, borderpad=4, xanchor="center"),
        # Threshold labels
        list(x=.79, y=1.04, text="Awareness threshold: 80%", showarrow=FALSE,
             textangle=-90, font=list(color=C_$muted, size=9), xanchor="right"),
        list(x=0.85, y=0.87, text="CV target: 90%",
             showarrow=FALSE, font=list(color="grey", size=9)),
        # Advocacy: sits right after the x-axis title, before the legend row
        list(x=1.0, y=-0.19, xref="paper", yref="paper",
             text="Advocacy message: low-awareness districts require intensified pre-campaign mobilisation",
             showarrow=FALSE, xanchor="right", yanchor="top",
             font=list(size=8, color="grey50"))
      ),
      # b=140 keeps y=-0.19 (advocacy) and y=-0.30 (legend) inside the figure
      # for both the 450px browser display and the 640px PNG download
      margin = list(l=60, r=70, t=50, b=140)
    ) %>%
      # Apply legend AFTER im_layout so it overrides plotly_base()'s legend key
      plotly::layout(legend = list(
        orientation = "h",
        x = 0.5, y = -0.30,
        xanchor = "center", yanchor = "top",
        bgcolor = "rgba(255,255,255,0)",
        borderwidth = 0,
        font = list(size = 7, color = C_$dark),
        tracegroupgap = 2
      )) %>%
      plotly::config(toImageButtonOptions = list(
        format   = "png",
        filename = "IM_sm_quadrant",
        height   = 660,
        width    = 960,
        scale    = 2
      ))
  })

  # ── Root causes (Overview simplified) ────────────────────────────────────────
  output$chart_root_ov <- renderPlotly({
    df <- ov_data(); req(df)

    root_labels <- c(
      r_non_fm_absent                = "Absent",
      r_non_fm_nc                    = "Non-compliance",
      r_non_fm_hh_notvisited         = "House not visited",
      r_non_fm_hh_notrevisited       = "House not revisited",
      r_non_fm_sleep                 = "Sleeping child",
      r_non_fm_vaccinatedroutine     = "Vaccinated (routine)",
      r_non_fm_other                 = "Other reason",
      r_non_fm_vaccinated_but_not_fm = "Vaccinated but not FM",
      r_non_fm_child_is_a_visitor    = "Visitor child",
      r_non_fm_childnotborn          = "Child not born",
      r_non_fm_security              = "Security"
    )

    # Per-cause advocacy text aligned to report recommendation cards
    advocacy_map <- c(
      "Non-compliance"        = "Intensify pre-campaign social mobilisation; engage community and religious leaders.",
      "House not visited"     = "Review vaccinator route plans and strengthen daily supervisory accountability.",
      "House not revisited"   = "'House not revisited' should become a campaign accountability indicator — strengthen revisit tracking and defaulter follow-up.",
      "Absent"                = "Deploy fixed-post strategies and time-flexible schedules to reach absent caregivers.",
      "Sleeping child"        = "Train vaccinators on appropriate wake-up protocol for sleeping children.",
      "Vaccinated (routine)"  = "Link EPI records and clarify FM eligibility criteria to avoid missed-dose under-reporting.",
      "Vaccinated but not FM" = "Strengthen FM recording and reconciliation at team and district level.",
      "Visitor child"         = "Map and register migrant and transient populations in microplans.",
      "Child not born"        = "Update community microplans with current birth data and dynamic household registers.",
      "Security"              = "Engage traditional/religious leaders for humanitarian access corridors in insecure areas.",
      "Other reason"          = "Use district-level risk profiles to guide microplanning and corrective action."
    )

    # 2-group categorisation matching generate_afro_im_intelligence_report()
    # Priority group: the three behavioural/operational causes singled out in the report
    cat_priority <- c("Non-compliance", "House not visited", "House not revisited")
    # Everything else → other missed-child driver

    cat_cols <- c(
      "Priority operational/behavioral issue" = "#C00000",   # alert_red (report)
      "Other missed-child driver"             = "#0093D5"    # who_blue  (report)
    )

    rcols <- intersect(names(root_labels), names(df))
    if (!length(rcols)) {
      rcols <- grep("r_non_fm|r_non_", names(df), value=TRUE, ignore.case=TRUE)
      rcols <- rcols[sapply(df[, rcols, drop=FALSE],
                            function(x) is.numeric(x) || is.integer(x))]
      if (!length(rcols)) return(
        plotly_empty() %>% im_layout() %>%
          add_annotations(text = "No root-cause columns (r_non_fm_*) found",
                          showarrow = FALSE, font = list(size=13, color=C_$muted))
      )
      labels <- sub("r_non_fm_|r_non_", "", rcols)
    } else {
      labels <- root_labels[rcols]
    }

    tots <- colSums(df[, rcols, drop=FALSE], na.rm=TRUE)
    tbl  <- data.frame(reason = as.character(labels),
                       total  = as.numeric(tots),
                       stringsAsFactors = FALSE) %>%
      filter(total > 0) %>%
      arrange(desc(total)) %>%
      slice_head(n = 12) %>%
      mutate(
        share    = total / sum(total),
        category = case_when(
          reason %in% cat_priority ~ "Priority operational/behavioral issue",
          TRUE                     ~ "Other missed-child driver"
        ),
        advocacy = advocacy_map[reason],
        lbl      = paste0(fmt_num(total), " (", round(share * 100, 1), "%)")
      )

    if (!nrow(tbl)) return(NULL)

    # Primary advocacy annotation — recommendation from report script
    top_reason  <- tbl$reason[1]
    top_adv     <- tbl$advocacy[1]
    top_cat     <- tbl$category[1]
    top_col     <- cat_cols[top_cat]
    adv_ann_txt <- paste0(
      "<b>Priority cause — ", top_reason, ":</b> ",
      if (!is.na(top_adv)) top_adv else "Investigate and address underlying barriers"
    )
    # Fixed caption (from report p_root subtitle)
    caption_txt <- "Advocacy use: tailor corrective action by dominant cause — use IM risk ranking to focus supervision, partner support and rapid action."


    # Build one trace per category → named legend entries in PNG download
    p <- plot_ly()
    for (cat_name in names(cat_cols)) {
      sub <- tbl[tbl$category == cat_name, ]
      if (!nrow(sub)) next
      adv_vec <- as.character(sub$advocacy)
      adv_vec[is.na(adv_vec)] <- "Investigate & address underlying barriers"
      p <- add_bars(p,
        data          = sub,
        x             = ~total,
        y             = ~reorder(reason, total),
        orientation   = "h",
        name          = cat_name,
        legendgroup   = cat_name,
        marker        = list(color = cat_cols[cat_name],
                             line  = list(width = 0)),
        text          = ~lbl,
        textposition  = "outside",
        cliponaxis    = FALSE,
        customdata    = adv_vec,
        hovertemplate = paste0(
          "<b>%{y}</b><br>",
          "Missed children: <b>%{x:,}</b><br>",
          "<i>Recommended action:</i> %{customdata}",
          "<extra></extra>"
        ),
        showlegend    = TRUE
      )
    }

    im_layout(p,
      .title    = "Root Causes of Missed Children",
      .filename = "IM_root_causes",
      barmode   = "overlay",
      xaxis     = list(title = "Missed Children", showgrid = TRUE,
                       gridcolor = "rgba(0,92,151,.07)",
                       range = list(0, max(tbl$total, na.rm=TRUE) * 1.25)),
      yaxis     = list(title = "", tickfont = list(size = 11)),
      showlegend = TRUE
    ) %>%
      # Apply legend, margin + annotations AFTER im_layout so plotly_base() doesn't win
      plotly::layout(
        legend = list(
          x = 1.01, y = 0.80, xanchor = "left", yanchor = "top",
          bgcolor = "rgba(255,255,255,.85)",
          bordercolor = "rgba(0,92,151,.12)", borderwidth = 1,
          font = list(size = 11, color = C_$dark),
          title = list(text = "<b>Category</b>", font = list(size = 11))
        ),
        margin = list(l = 170, r = 185, t = 46, b = 130),
        annotations = list(
          list(x = 0, y = -0.22, xref = "paper", yref = "paper",
               text = caption_txt, showarrow = FALSE, xanchor = "left",
               font = list(size = 9, color = "grey50")),
          list(x = 0, y = -0.32, xref = "paper", yref = "paper",
               text = adv_ann_txt, showarrow = FALSE, xanchor = "left",
               font = list(size = 9, color = "grey50"))
        )
      )
  })

  # ── Country-level IM risk profile (ported from intelligence report Visual 3) ──
  output$chart_country_risk <- renderPlotly({
    df  <- ov_data(); req(df)
    dfr <- tryCatch(with_risk(df), error=function(e) NULL)
    if (is.null(dfr) || !all(c("risk_score","country") %in% names(dfr))) return(
      plotly_empty() %>% im_layout() %>%
        add_annotations(text = "Country risk profile unavailable — missing u5_present/u5_fm/country columns",
                        showarrow = FALSE, font = list(size=13, color=C_$muted))
    )

    tbl <- dfr %>%
      group_by(country) %>%
      summarise(
        mean_risk_score = mean(risk_score, na.rm = TRUE),
        total_missed    = sum(missed_child, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      filter(!is.na(mean_risk_score)) %>%
      mutate(
        risk_group = case_when(
          mean_risk_score >= 70 ~ "Critical",
          mean_risk_score >= 50 ~ "High",
          mean_risk_score >= 30 ~ "Moderate",
          TRUE                  ~ "Low"
        ),
        lbl = paste0("Missed: ", fmt_num(total_missed))
      ) %>%
      arrange(mean_risk_score)

    if (!nrow(tbl)) return(NULL)

    risk_cols <- c(Critical = C_$red, High = C_$orange, Moderate = C_$blue, Low = C_$green)

    p <- plot_ly()
    for (grp in names(risk_cols)) {
      sub <- tbl[tbl$risk_group == grp, ]
      if (!nrow(sub)) next
      p <- add_bars(p,
        data          = sub,
        x             = ~mean_risk_score,
        y             = ~reorder(country, mean_risk_score),
        orientation   = "h",
        name          = grp,
        legendgroup   = grp,
        marker        = list(color = risk_cols[[grp]], line = list(width = 0)),
        text          = ~lbl,
        textposition  = "outside",
        cliponaxis    = FALSE,
        hovertemplate = "<b>%{y}</b><br>Mean risk score: <b>%{x:.1f}</b><br>%{text}<extra></extra>",
        showlegend    = TRUE
      )
    }

    im_layout(p,
      .title    = "Country-Level IM Risk Profile",
      .filename = "IM_country_risk",
      barmode   = "overlay",
      xaxis     = list(title = "Mean Risk Score", showgrid = TRUE,
                       gridcolor = "rgba(0,92,151,.07)",
                       range = list(0, max(tbl$mean_risk_score, na.rm=TRUE) * 1.3)),
      yaxis     = list(title = "", tickfont = list(size = 11)),
      showlegend = TRUE
    ) %>%
      plotly::layout(
        legend = list(
          x = 1.01, y = 0.85, xanchor = "left", yanchor = "top",
          bgcolor = "rgba(255,255,255,.85)",
          bordercolor = "rgba(0,92,151,.12)", borderwidth = 1,
          font = list(size = 11, color = C_$dark),
          title = list(text = "<b>Risk Tier</b>", font = list(size = 11))
        ),
        margin = list(l = 150, r = 185, t = 46, b = 60),
        annotations = list(
          list(x = 0, y = -0.14, xref = "paper", yref = "paper",
               text = "Focus countries with both high risk score and high missed-child burden.",
               showarrow = FALSE, xanchor = "left", font = list(size = 9, color = "grey50"))
        )
      )
  })

  # ── Operational failure profile (ported from intelligence report Visual 5) ───
  output$chart_op_failure <- renderPlotly({
    df <- ov_data(); req(df)

    needed <- c("r_non_fm_absent","r_non_fm_nc","r_non_fm_hh_notvisited","r_non_fm_hh_notrevisited")
    if (!all(needed %in% names(df))) return(
      plotly_empty() %>% im_layout() %>%
        add_annotations(text = "Operational failure profile unavailable — missing r_non_fm_* columns",
                        showarrow = FALSE, font = list(size=13, color=C_$muted))
    )

    grp_cols <- intersect(c("country","province","district","response","roundnumber"), names(df))
    if (!length(grp_cols)) grp_cols <- intersect(c("country","district"), names(df))
    mc_col <- if ("missed_child" %in% names(df)) "missed_child" else NA

    op <- df %>%
      group_by(across(all_of(grp_cols))) %>%
      summarise(
        missed_child = if (!is.na(mc_col)) sum(.data[[mc_col]], na.rm = TRUE)
                       else sum(pmax(as.numeric(u5_present) - as.numeric(u5_fm), 0), na.rm = TRUE),
        absent               = sum(r_non_fm_absent, na.rm = TRUE),
        non_compliance       = sum(r_non_fm_nc, na.rm = TRUE),
        house_not_visited    = sum(r_non_fm_hh_notvisited, na.rm = TRUE),
        house_not_revisited  = sum(r_non_fm_hh_notrevisited, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        operational_failure_type = case_when(
          house_not_visited >= house_not_revisited &
            house_not_visited >= absent &
            house_not_visited >= non_compliance &
            house_not_visited > 0 ~ "Team did not visit households",
          house_not_revisited >= house_not_visited &
            house_not_revisited >= absent &
            house_not_revisited >= non_compliance &
            house_not_revisited > 0 ~ "Weak revisit / supervision failure",
          absent >= house_not_visited &
            absent >= house_not_revisited &
            absent >= non_compliance &
            absent > 0 ~ "Population absence / timing issue",
          non_compliance >= house_not_visited &
            non_compliance >= house_not_revisited &
            non_compliance >= absent &
            non_compliance > 0 ~ "Community resistance / refusal",
          missed_child == 0 ~ "No operational failure detected",
          TRUE ~ "Mixed / other operational issue"
        )
      )

    tbl <- op %>%
      filter(operational_failure_type != "No operational failure detected") %>%
      group_by(operational_failure_type) %>%
      summarise(total_missed = sum(missed_child, na.rm = TRUE), .groups = "drop") %>%
      filter(total_missed > 0) %>%
      arrange(desc(total_missed)) %>%
      mutate(lbl = fmt_num(total_missed))

    if (!nrow(tbl)) return(NULL)

    p <- plot_ly(tbl,
      x = ~total_missed,
      y = ~reorder(operational_failure_type, total_missed),
      type = "bar",
      orientation = "h",
      marker = list(color = C_$blue2, line = list(width = 0)),
      text = ~lbl,
      textposition = "outside",
      cliponaxis = FALSE,
      hovertemplate = "<b>%{y}</b><br>Missed children: <b>%{x:,}</b><extra></extra>"
    )

    im_layout(p,
      .title    = "Operational Failure Profile",
      .filename = "IM_op_failure",
      xaxis     = list(title = "Missed Children", showgrid = TRUE,
                       gridcolor = "rgba(0,92,151,.07)",
                       range = list(0, max(tbl$total_missed, na.rm=TRUE) * 1.25)),
      yaxis     = list(title = "", tickfont = list(size = 11))
    ) %>%
      plotly::layout(
        margin = list(l = 230, r = 80, t = 46, b = 60),
        annotations = list(
          list(x = 0, y = -0.16, xref = "paper", yref = "paper",
               text = "Use for regional discussion on team deployment, revisit tracking and supervision accountability.",
               showarrow = FALSE, xanchor = "left", font = list(size = 9, color = "grey50"))
        )
      )
  })

  # ── Top priority districts for advocacy (ported from report Visual 2) ────────
  output$chart_priority_districts <- renderPlotly({
    df  <- ov_data(); req(df)
    dfr <- tryCatch(with_risk(df), error=function(e) NULL)
    if (is.null(dfr) || !all(c("risk_score","country","province","district") %in% names(dfr))) return(
      plotly_empty() %>% im_layout() %>%
        add_annotations(text = "Priority districts unavailable — missing risk inputs or country/province/district columns",
                        showarrow = FALSE, font = list(size=13, color=C_$muted))
    )

    tbl <- dfr %>%
      group_by(country, province, district) %>%
      summarise(
        mean_risk_score = mean(risk_score, na.rm = TRUE),
        total_missed    = sum(missed_child, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      filter(!is.na(mean_risk_score)) %>%
      arrange(desc(mean_risk_score)) %>%
      slice_head(n = 25) %>%
      mutate(
        district_label = paste(country, province, district, sep = " | "),
        priority = case_when(
          mean_risk_score >= 70 ~ "Priority 1",
          mean_risk_score >= 50 ~ "Priority 2",
          mean_risk_score >= 30 ~ "Priority 3",
          TRUE                  ~ "Routine"
        ),
        lbl = round(mean_risk_score, 1),
        missed_lbl = fmt_num(total_missed)
      )

    if (!nrow(tbl)) return(NULL)

    pr_cols <- c("Priority 1" = C_$red, "Priority 2" = C_$orange,
                 "Priority 3" = C_$blue, "Routine" = C_$green)

    p <- plot_ly()
    for (grp in names(pr_cols)) {
      sub <- tbl[tbl$priority == grp, ]
      if (!nrow(sub)) next
      p <- add_bars(p,
        data          = sub,
        x             = ~mean_risk_score,
        y             = ~reorder(district_label, mean_risk_score),
        orientation   = "h",
        name          = grp,
        legendgroup   = grp,
        marker        = list(color = pr_cols[[grp]], line = list(width = 0)),
        text          = ~lbl,
        textposition  = "outside",
        cliponaxis    = FALSE,
        customdata    = ~missed_lbl,
        hovertemplate = paste0(
          "<b>%{y}</b><br>Mean risk score: <b>%{x:.1f}</b><br>",
          "Missed children: <b>%{customdata}</b><extra></extra>"
        ),
        showlegend    = TRUE
      )
    }

    im_layout(p,
      .title    = "Top Priority Districts for Advocacy",
      .filename = "IM_priority_districts",
      barmode   = "overlay",
      xaxis     = list(title = "Mean Risk Score", showgrid = TRUE,
                       gridcolor = "rgba(0,92,151,.07)", range = list(0, 100)),
      yaxis     = list(title = "", tickfont = list(size = 10)),
      showlegend = TRUE
    ) %>%
      plotly::layout(
        legend = list(
          x = 1.01, y = 0.92, xanchor = "left", yanchor = "top",
          bgcolor = "rgba(255,255,255,.85)",
          bordercolor = "rgba(0,92,151,.12)", borderwidth = 1,
          font = list(size = 11, color = C_$dark),
          title = list(text = "<b>Priority</b>", font = list(size = 11))
        ),
        margin = list(l = 260, r = 185, t = 46, b = 60),
        annotations = list(
          list(x = 0, y = -0.05, xref = "paper", yref = "paper",
               text = "Use this list for prioritization, partner support and accountability tracking.",
               showarrow = FALSE, xanchor = "left", font = list(size = 9, color = "grey50"))
        )
      )
  })

  # ── Active filters badge ──────────────────────────────────────────────────────
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

  # ── Per-chart CSV download handlers ──────────────────────────────────────────
  snap <- function() {
    df <- tryCatch(active(), error=function(e) rv$data)
    if (is.null(df)) data.frame() else df
  }
  output$dl_ov_all <- downloadHandler(
    filename=function() paste0("IM_filtered_",Sys.Date(),".csv"),
    content =function(f) write.csv(snap(),f,row.names=FALSE))
  output$dl_block <- downloadHandler(
    filename=function() paste0("IM_block_",Sys.Date(),".csv"),
    content =function(f) {
      df <- snap()
      if ("afro_block"%in%names(df)&&!is.null(input$ov_block)&&input$ov_block!="All")
        df <- df[df$afro_block==input$ov_block,]
      write.csv(df,f,row.names=FALSE)
    })
  output$dl_risk_dist <- downloadHandler(
    filename=function() paste0("IM_risk_dist_",Sys.Date(),".csv"),
    content =function(f) write.csv(snap(),f,row.names=FALSE))
  output$dl_sm_quad <- downloadHandler(
    filename=function() paste0("IM_sm_quadrant_",Sys.Date(),".csv"),
    content =function(f) {
      df   <- snap()
      cols <- intersect(c("country","province","district","cv",
                          "mean_awareness_rate","sm_gap_flag","sm_priority_flag"),names(df))
      write.csv(df[,cols,drop=FALSE],f,row.names=FALSE)
    })
  output$dl_alert_cv <- downloadHandler(
    filename=function() paste0("IM_low_cv_alerts_",Sys.Date(),".csv"),
    content =function(f) {
      df <- snap()
      if ("cv"%in%names(df)) df <- df[!is.na(df$cv)&df$cv<0.8,]
      write.csv(df,f,row.names=FALSE)
    })
  output$dl_root_ov <- downloadHandler(
    filename=function() paste0("IM_root_causes_",Sys.Date(),".csv"),
    content =function(f) {
      df   <- snap()
      cols <- intersect(c("country","province","district","missed_child",
                          "qc_flag","abs_detail_flag","nc_detail_flag",
                          "reconciliation_flag"),names(df))
      write.csv(df[,cols,drop=FALSE],f,row.names=FALSE)
    })
  output$dl_cv <- downloadHandler(
    filename=function() paste0("IM_cv_",Sys.Date(),".csv"),
    content =function(f) {
      df   <- snap()
      cols <- intersect(c("country","province","district","roundnumber",
                          "cv","vaccine_type","response"),names(df))
      write.csv(df[,cols,drop=FALSE],f,row.names=FALSE)
    })
  output$dl_top_bottom <- downloadHandler(
    filename=function() paste0("IM_top_bottom_",Sys.Date(),".csv"),
    content =function(f) write.csv(snap(),f,row.names=FALSE))
  output$dl_trend <- downloadHandler(
    filename=function() paste0("IM_trend_",Sys.Date(),".csv"),
    content =function(f) {
      df   <- snap()
      cols <- intersect(c("country","province","district","roundnumber",
                          "round_start_date","cv","missed_child"),names(df))
      write.csv(df[,cols,drop=FALSE],f,row.names=FALSE)
    })
  output$dl_heatmap <- downloadHandler(
    filename=function() paste0("IM_heatmap_",Sys.Date(),".csv"),
    content =function(f) write.csv(snap(),f,row.names=FALSE))
  output$dl_qc_pie <- downloadHandler(
    filename=function() paste0("IM_qc_flags_",Sys.Date(),".csv"),
    content =function(f) {
      df <- tryCatch(ov_data(), error=function(e) snap())
      if (is.null(df)) df <- snap()
      write.csv(df,f,row.names=FALSE)
    })
  output$dl_cv95 <- downloadHandler(
    filename=function() paste0("IM_cv95_",Sys.Date(),".csv"),
    content =function(f) {
      tbl <- tryCatch(cv95_tbl(), error=function(e) NULL)
      if (is.null(tbl)) tbl <- data.frame()
      write.csv(tbl,f,row.names=FALSE)
    })


  # ═══════════════════════════════════════════════════════════════════════════
  output$dl_exec_snapshot <- downloadHandler(
    filename=function() paste0("IM_executive_snapshot_",Sys.Date(),".csv"),
    content =function(f) {
      df  <- snap()
      dfr <- tryCatch(with_risk(df), error=function(e) NULL)

      n_country  <- if ("country" %in% names(df)) n_distinct(df$country, na.rm=TRUE) else NA
      n_district <- if (all(c("country","province","district") %in% names(df)))
                       n_distinct(paste(df$country, df$province, df$district)) else NA
      n_rounds   <- if (all(c("country","response","roundnumber") %in% names(df)))
                       n_distinct(paste(df$country, df$response, df$roundnumber)) else NA

      hh_visited <- if ("number_of_hh_visited" %in% names(df))
                       sum(as.numeric(df$number_of_hh_visited), na.rm=TRUE) else NA

      tp <- if ("u5_present" %in% names(df)) sum(as.numeric(df$u5_present), na.rm=TRUE) else NA
      tf <- if ("u5_fm"      %in% names(df)) sum(as.numeric(df$u5_fm),      na.rm=TRUE) else NA
      regional_cv  <- if (!is.na(tp) && !is.na(tf) && tp > 0) tf / tp else NA
      total_missed <- if (!is.na(tp) && !is.na(tf)) pmax(tp - tf, 0) else NA

      mean_awareness <- if (!is.null(dfr) && "awareness_rate" %in% names(dfr))
                           mean(dfr$awareness_rate, na.rm=TRUE) else NA
      mean_risk <- if (!is.null(dfr) && "risk_score" %in% names(dfr))
                      mean(dfr$risk_score, na.rm=TRUE) else NA

      risk_counts <- list(critical=0, high=0, moderate=0, low=0)
      if (!is.null(dfr) && all(c("risk_class","country","province","district") %in% names(dfr))) {
        rc <- dfr %>%
          group_by(country, province, district) %>%
          summarise(rc = first(risk_class), .groups="drop") %>%
          count(rc)
        g <- function(x) { v <- rc$n[rc$rc == x]; if (length(v)) v else 0 }
        risk_counts <- list(critical=g("Critical"), high=g("High"), moderate=g("Moderate"), low=g("Low"))
      }

      out <- data.frame(
        generated_on           = as.character(Sys.Date()),
        countries               = n_country,
        districts                = n_district,
        campaign_rounds          = n_rounds,
        total_hh_visited         = hh_visited,
        regional_coverage_pct    = if (is.na(regional_cv))  NA else round(regional_cv*100,1),
        total_missed_children    = total_missed,
        mean_awareness_pct       = if (is.na(mean_awareness)) NA else round(mean_awareness*100,1),
        mean_risk_score          = if (is.na(mean_risk)) NA else round(mean_risk,1),
        critical_risk_events     = risk_counts$critical,
        high_risk_events         = risk_counts$high,
        moderate_risk_events     = risk_counts$moderate,
        low_risk_events          = risk_counts$low
      )
      write.csv(out, f, row.names=FALSE)
    })
  output$dl_country_risk <- downloadHandler(
    filename=function() paste0("IM_country_risk_",Sys.Date(),".csv"),
    content =function(f) {
      df  <- snap()
      dfr <- tryCatch(with_risk(df), error=function(e) NULL)
      if (is.null(dfr) || !all(c("risk_score","country") %in% names(dfr))) {
        write.csv(data.frame(), f, row.names=FALSE); return(invisible())
      }
      tbl <- dfr %>%
        group_by(country) %>%
        summarise(mean_risk_score = mean(risk_score, na.rm=TRUE),
                  total_missed    = sum(missed_child, na.rm=TRUE), .groups="drop") %>%
        arrange(desc(mean_risk_score))
      write.csv(tbl, f, row.names=FALSE)
    })
  output$dl_op_failure <- downloadHandler(
    filename=function() paste0("IM_operational_failure_",Sys.Date(),".csv"),
    content =function(f) {
      df     <- snap()
      needed <- c("r_non_fm_absent","r_non_fm_nc","r_non_fm_hh_notvisited","r_non_fm_hh_notrevisited")
      if (!all(needed %in% names(df))) {
        write.csv(data.frame(), f, row.names=FALSE); return(invisible())
      }
      grp_cols <- intersect(c("country","province","district","response","roundnumber"), names(df))
      if (!length(grp_cols)) grp_cols <- intersect(c("country","district"), names(df))
      mc_col <- if ("missed_child" %in% names(df)) "missed_child" else NA
      op <- df %>%
        group_by(across(all_of(grp_cols))) %>%
        summarise(
          missed_child = if (!is.na(mc_col)) sum(.data[[mc_col]], na.rm = TRUE)
                         else sum(pmax(as.numeric(u5_present) - as.numeric(u5_fm), 0), na.rm = TRUE),
          absent               = sum(r_non_fm_absent, na.rm = TRUE),
          non_compliance       = sum(r_non_fm_nc, na.rm = TRUE),
          house_not_visited    = sum(r_non_fm_hh_notvisited, na.rm = TRUE),
          house_not_revisited  = sum(r_non_fm_hh_notrevisited, na.rm = TRUE),
          .groups = "drop"
        ) %>%
        mutate(
          operational_failure_type = case_when(
            house_not_visited >= house_not_revisited &
              house_not_visited >= absent &
              house_not_visited >= non_compliance &
              house_not_visited > 0 ~ "Team did not visit households",
            house_not_revisited >= house_not_visited &
              house_not_revisited >= absent &
              house_not_revisited >= non_compliance &
              house_not_revisited > 0 ~ "Weak revisit / supervision failure",
            absent >= house_not_visited &
              absent >= house_not_revisited &
              absent >= non_compliance &
              absent > 0 ~ "Population absence / timing issue",
            non_compliance >= house_not_visited &
              non_compliance >= house_not_revisited &
              non_compliance >= absent &
              non_compliance > 0 ~ "Community resistance / refusal",
            missed_child == 0 ~ "No operational failure detected",
            TRUE ~ "Mixed / other operational issue"
          )
        )
      tbl <- op %>%
        group_by(operational_failure_type) %>%
        summarise(total_missed = sum(missed_child, na.rm = TRUE), .groups = "drop") %>%
        arrange(desc(total_missed))
      write.csv(tbl, f, row.names=FALSE)
    })
  output$dl_priority_districts <- downloadHandler(
    filename=function() paste0("IM_priority_districts_",Sys.Date(),".csv"),
    content =function(f) {
      df  <- snap()
      dfr <- tryCatch(with_risk(df), error=function(e) NULL)
      if (is.null(dfr) || !all(c("risk_score","country","province","district") %in% names(dfr))) {
        write.csv(data.frame(), f, row.names=FALSE); return(invisible())
      }
      tbl <- dfr %>%
        group_by(country, province, district) %>%
        summarise(mean_risk_score = mean(risk_score, na.rm=TRUE),
                  total_missed    = sum(missed_child, na.rm=TRUE), .groups="drop") %>%
        arrange(desc(mean_risk_score)) %>%
        mutate(priority = case_when(
          mean_risk_score >= 70 ~ "Priority 1",
          mean_risk_score >= 50 ~ "Priority 2",
          mean_risk_score >= 30 ~ "Priority 3",
          TRUE                  ~ "Routine"
        ))
      write.csv(tbl, f, row.names=FALSE)
    })

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

  rv_log   <- reactiveVal(get_log_lines())
  rv_stat  <- reactiveVal("idle")
  rv_steps <- reactiveVal(rep("pending", 6L))
  rv_proc  <- reactiveVal(NULL)   # list(proc, step_idx, lf, pos)
  rv_queue <- reactiveVal(integer(0))

  # Stop button only makes sense while something is actually running.
  observe({
    if (rv_stat() == "running") shinyjs::enable("btn_stop")
    else                        shinyjs::disable("btn_stop")
  })

  observeEvent(input$btn_stop, {
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
    list(n=4L, label="Upload SharePoint", icon="cloud-arrow-up-fill",
         cmd="python",
         args=c(file.path(WORKFLOW_DIR,"scripts","upload_to_sharepoint.py"),
                "--base-dir", WORKFLOW_DIR, "--all")),
    list(n=5L, label="Intelligence Engine", icon="cpu-fill",
         cmd="Rscript",
         args=c(file.path(WORKFLOW_DIR,"scripts","afro_im_intilligence_analysis_engine.R"))),
    list(n=6L, label="Generate Reports",  icon="file-earmark-bar-graph-fill",
         cmd="Rscript",
         args=c(file.path(WORKFLOW_DIR,"scripts","AFRO_Advocacy_Intelligence_Report.R")))
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
        rv_stat("error"); rv_proc(NULL); rv_queue(integer(0))
      } else {
        rv_log(paste0(isolate(rv_log()),
                      "\n[OK] Step ", step_idx, " complete\n"))
        rv_proc(NULL)
        q <- isolate(rv_queue())
        if (length(q) == 0L) {
          rv_stat("ok")
          rv$data <- load_im_data()
          showNotification("Pipeline complete — data refreshed.",
                           type="message", duration=6)
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
    reset_log_pos()   # start reading workflow log from current EOF
    if (clear_log) {
      msg <- if (!is.null(header)) paste0(header, "\n") else
             paste0("── ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ──\n")
      rv_log(msg)
    }
  }

  observeEvent(input$run_fetch, {
    step_start(header = "[1] FETCH DATA\n")
    launch_step(1L)
  })
  observeEvent(input$run_build, {
    step_start(header = "[2] BUILD REPOSITORY\n")
    launch_step(2L)
  })
  observeEvent(input$run_clean, {
    step_start(header = "[3] CLEAN GEONAMES\n")
    launch_step(3L)
  })
  observeEvent(input$run_upload, {
    step_start(header = "[4] UPLOAD SHAREPOINT\n")
    launch_step(4L)
  })
  observeEvent(input$run_rpts, {
    step_start(header = "[5-6] GENERATE REPORTS (Intelligence Engine + Advocacy Report)\n")
    rv_queue(6L)
    launch_step(5L)
  })
  observeEvent(input$run_all, {
    step_start(header = paste0("▶  FULL PIPELINE STARTED\n── ",
                               format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                               " ──\n"))
    rv_queue(2:6)
    launch_step(1L)
  })

  # Refresh log from file on button click ----------------------------------
  observeEvent(input$btn_rl_log, {
    rv_log(get_log_lines())
    rv_stat(last_run_info()$status)
  })

  # Reload data manually ---------------------------------------------------
  observeEvent(input$btn_rl_data, {
    rv$data <- load_im_data()
    showNotification("Data reloaded.", type="message")
  })

  # Outputs ----------------------------------------------------------------
  output$log_txt <- renderText({ rv_log() })

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
  # SHAREPOINT MANUAL PUSH (relocated from the removed Reports tab; the
  # queued "4. Upload SharePoint" pipeline step above is the full-pipeline
  # version of this same upload -- this one is for a quick ad hoc
  # test/check/push outside a full run, writing into the same Pipeline log.)
  # ═══════════════════════════════════════════════════════════════════════════

  rv_sp_stat  <- reactiveVal(NULL)
  rv_sp_scope <- reactiveVal(NULL)

  observeEvent(input$btn_push_sp, {
    rv_log(paste0(rv_log(), "\n[SharePoint] Pushing...\n"))
    rv_sp_stat(NULL)
    scope <- if (!is.null(input$sp_scope)) input$sp_scope else "--check"
    rv_sp_scope(scope)
    py <- file.path(WORKFLOW_DIR, "scripts", "upload_to_sharepoint.py")
    if (!file.exists(py)) {
      rv_log(paste0(rv_log(), "[ERROR] upload_to_sharepoint.py not found."))
      rv_sp_stat("error"); return()
    }
    tryCatch({
      # "python" here, not "python3" -- matches the one invocation already
      # proven to work everywhere else in this project (run_workflow.R's
      # fetch step, the lookup refresh script); "python3" isn't guaranteed
      # to resolve in the plain Windows PATH a Shiny/RStudio R session sees,
      # even when it works fine from a Git Bash prompt.
      out    <- system2("python", args=c(shQuote(py), scope),
                        stdout=TRUE, stderr=TRUE)
      # system2() with stdout=TRUE only throws an R error if the process
      # can't be launched at all (e.g. "python" missing from PATH) -- a
      # script that runs to completion but reports failure just returns
      # normally, so the actual outcome has to be read from the exit
      # status and from the script's own [FAIL] markers.
      status <- attr(out, "status")
      if (is.null(status)) status <- 0L
      failed <- status != 0L || any(grepl("\\[FAIL\\]", out))
      rv_log(paste0(rv_log(), paste(out, collapse="\n")))
      rv_sp_stat(if (failed) "error" else "ok")
    }, error=function(e) {
      rv_log(paste0(rv_log(), "[ERROR] ", e$message)); rv_sp_stat("error")
    })
  })

  output$sp_badge_ui <- renderUI({
    st <- rv_sp_stat(); if (is.null(st)) return(NULL)
    scope <- rv_sp_scope()
    ok_label <- switch(scope,
      "--test"  = "Connection OK",
      "--check" = "Local files check complete",
      "Upload complete")
    if (st == "ok")
      div(class="alert alert-success p-2 mt-2 small",
          tags$span(class="dot dot-ok"), ok_label)
    else
      div(class="alert alert-danger p-2 mt-2 small",
          tags$span(class="dot dot-err"), "Error — check log")
  })
} # end server
shinyApp(ui, server)
