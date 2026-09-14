# ============================================================
# AI ASSISTANT — DATA HELPERS, TOOLS & WIDGET UI
# ============================================================
# Moved out of shiny_app/app.R during the app.R modularization pass.
# This file lives in shiny_app/R/ , which Shiny's runApp() sources
# automatically before app.R itself runs (shiny::loadSupport()), so
# no explicit source() call is needed anywhere -- everything defined
# here is available to app.R exactly as if it were still inline.
# Content is verbatim from the original app.R (byte-identical). who_theme (originally between these two blocks) was left inline in app.R.
# ============================================================

# ── Data helpers shared by the AI tools ──────────────────────────────────
# country/province/district each accept EITHER a single value ("NIGERIA")
# OR a comma-separated list ("NIGERIA, NIGER, CHAD, CAMEROON") -- a plain
# single value behaves exactly as before (a 1-element split), so every
# existing call site keeps working unchanged. months_back optionally
# restricts to the most recent N months present in the data (using
# whichever date column date_col_of() finds); leave it NA for no date
# filtering.
im_filter_scope <- function(df, country = "", province = "", district = "",
                             months_back = NA) {
  if (is.null(df) || !nrow(df)) return(df)
  match_multi <- function(col, spec) {
    vals <- trimws(strsplit(spec, ",", fixed = TRUE)[[1]])
    vals <- vals[nzchar(vals)]
    if (!length(vals)) return(rep(TRUE, length(col)))
    !is.na(col) & toupper(col) %in% toupper(vals)
  }
  if (nzchar(country)  && "country"  %in% names(df))
    df <- df[match_multi(df$country,  country), ]
  if (nzchar(province) && "province" %in% names(df))
    df <- df[match_multi(df$province, province), ]
  if (nzchar(district) && "district" %in% names(df))
    df <- df[match_multi(df$district, district), ]
  if (!is.null(months_back) && !is.na(months_back) && is.numeric(months_back) &&
      months_back > 0 && nrow(df) > 0) {
    dcol <- date_col_of(df)
    if (!is.na(dcol) && nzchar(dcol) && dcol %in% names(df)) {
      dates <- suppressWarnings(as.Date(df[[dcol]]))
      if (any(!is.na(dates))) {
        cutoff <- max(dates, na.rm = TRUE) - round(months_back * 30.4)
        df <- df[!is.na(dates) & dates >= cutoff, ]
      }
    }
  }
  df
}

im_kpi_summary_text <- function(df, scope_label = "the whole loaded repository") {
  if (is.null(df) || !nrow(df))
    return(paste0("No data is loaded or matches that scope (", scope_label, ")."))
  dfr <- tryCatch(with_risk(df), error = function(e) NULL)
  hh  <- if ("number_of_hh_visited" %in% names(df)) sum(as.numeric(df$number_of_hh_visited), na.rm=TRUE) else NA
  tp  <- if ("u5_present" %in% names(df)) sum(as.numeric(df$u5_present), na.rm=TRUE) else NA
  tf  <- if ("u5_fm"      %in% names(df)) sum(as.numeric(df$u5_fm),      na.rm=TRUE) else NA
  cv     <- if (!is.na(tp) && !is.na(tf) && tp > 0) tf / tp else NA
  missed <- if (!is.na(tp) && !is.na(tf)) max(tp - tf, 0) else NA
  awareness <- if (!is.null(dfr) && "awareness_rate" %in% names(dfr)) mean(dfr$awareness_rate, na.rm=TRUE) else NA
  risk_counts <- c(Critical = 0, High = 0, Moderate = 0, Low = 0)
  n_country <- n_district <- 0
  if (!is.null(dfr) && all(c("risk_class","country","province","district") %in% names(dfr))) {
    per_area <- dfr %>%
      group_by(country, province, district) %>%
      summarise(rc = first(risk_class), .groups = "drop")
    tab <- table(per_area$rc)
    for (nm in names(risk_counts)) if (nm %in% names(tab)) risk_counts[nm] <- unname(tab[nm])
    n_country  <- n_distinct(df$country, na.rm = TRUE)
    n_district <- nrow(per_area)
  }
  paste0(
    "Summary for ", scope_label, " (", format(nrow(df), big.mark=","), " records):\n",
    "- Households visited: ", if (is.na(hh)) "n/a" else format(round(hh), big.mark=","), "\n",
    "- Coverage rate: ", if (is.na(cv)) "n/a" else paste0(round(cv*100,1), "%"), " (target 90%)\n",
    "- Missed children: ", if (is.na(missed)) "n/a" else format(round(missed), big.mark=","), "\n",
    "- Caregiver awareness: ", if (is.na(awareness)) "n/a" else paste0(round(awareness*100,1), "%"), " (target 80%)\n",
    "- Countries in scope: ", n_country, "; Districts in scope: ", n_district, "\n",
    "- District risk classes - Critical: ", risk_counts["Critical"],
    ", High: ", risk_counts["High"], ", Moderate: ", risk_counts["Moderate"],
    ", Low: ", risk_counts["Low"]
  )
}

im_top_risk_text <- function(df, n = 10) {
  if (is.null(df) || !nrow(df)) return("No data loaded or matching that scope.")
  dfr <- tryCatch(with_risk(df), error = function(e) NULL)
  if (is.null(dfr) || !all(c("risk_score","country","province","district") %in% names(dfr)))
    return("Risk scoring isn't available for this dataset (missing required columns).")
  tbl <- dfr %>%
    group_by(country, province, district) %>%
    summarise(mean_risk_score = mean(risk_score, na.rm = TRUE),
              mean_coverage_pct = mean(cv_d, na.rm = TRUE) * 100,
              .groups = "drop") %>%
    filter(!is.na(mean_risk_score)) %>%
    arrange(desc(mean_risk_score)) %>%
    head(max(1, min(n, 50)))
  if (!nrow(tbl)) return("No districts with a computable risk score in this scope.")
  lines <- sprintf("%d. %s / %s / %s - risk score %.0f, coverage %.1f%%",
                    seq_len(nrow(tbl)), tbl$country, tbl$province, tbl$district,
                    tbl$mean_risk_score, tbl$mean_coverage_pct)
  paste0("Highest-risk districts (mean risk_score, highest first):\n", paste(lines, collapse = "\n"))
}

im_trend_text <- function(df, metric = "coverage", country = "", months_back = NA) {
  if (!metric %in% c("coverage","missed_children","awareness")) metric <- "coverage"
  df <- im_filter_scope(df, country = country, months_back = months_back)
  if (is.null(df) || !nrow(df)) return("No data available for that scope.")
  if (!"roundnumber" %in% names(df))
    return("This dataset has no 'roundnumber' field, so a round-over-round trend can't be computed.")
  dfr <- tryCatch(with_risk(df), error = function(e) NULL)
  if (is.null(dfr)) return("Couldn't compute the underlying metrics for this scope.")
  agg <- dfr %>%
    filter(!is.na(roundnumber)) %>%
    group_by(roundnumber) %>%
    summarise(
      coverage_pct    = mean(cv_d, na.rm = TRUE) * 100,
      missed_children = sum(missed_child, na.rm = TRUE),
      awareness_pct   = mean(awareness_rate, na.rm = TRUE) * 100,
      .groups = "drop"
    )
  agg <- agg[order(suppressWarnings(as.numeric(as.character(agg$roundnumber)))), ]
  y <- switch(metric,
    coverage         = agg$coverage_pct,
    missed_children  = agg$missed_children,
    awareness        = agg$awareness_pct)
  ok <- is.finite(y)
  if (sum(ok) < 3)
    return(paste0("Not enough campaign rounds with usable ", metric,
                   " data in this scope to fit a trend (need at least 3)."))
  x <- seq_along(y)[ok]
  fit  <- stats::lm(y[ok] ~ x)
  pred <- as.numeric(stats::predict(fit, newdata = data.frame(x = max(x) + 1)))
  slope <- unname(stats::coef(fit)[2])
  direction <- if (abs(slope) < 1e-6) "flat" else if (slope > 0) "increasing" else "decreasing"
  metric_label <- switch(metric,
    coverage = "coverage rate (%)", missed_children = "missed children (count)",
    awareness = "caregiver awareness (%)")
  paste0(
    "Linear trend for ", metric_label, " across ", sum(ok), " campaign rounds: ",
    direction, " (", sprintf("%+.2f", slope), " per round). ",
    "Naive next-round projection: ", sprintf("%.1f", pred), ". ",
    "Caveat: this is a simple linear extrapolation over the rounds present in ",
    "the currently loaded data, not a validated epidemiological forecast - ",
    "treat it as a directional signal only."
  )
}

# ── Tool definitions — each closes over rv so it reads whatever is loaded
#    in THIS session, via isolate() so it can be called from an async
#    tool-calling loop outside a normal reactive context ──────────────────
build_im_ai_tools <- function(rv) {
  list(
    ellmer::tool(
      function(country = "", province = "", district = "", months_back = NA) {
        base <- shiny::isolate(rv$data)
        df   <- im_filter_scope(base, country, province, district, months_back = months_back)
        bits <- Filter(nzchar, c(district, province, country))
        scope_label <- if (length(bits)) paste(bits, collapse = ", ") else "the whole loaded repository"
        if (!is.na(months_back)) scope_label <- paste0(scope_label, ", last ", months_back, " month(s)")
        im_kpi_summary_text(df, scope_label)
      },
      name = "get_data_summary",
      description = paste(
        "Compute live summary statistics (records, households visited,",
        "coverage rate, missed children, caregiver awareness, risk-class",
        "breakdown) from the IM repository currently loaded in this",
        "dashboard session, optionally narrowed to one or more countries/",
        "a province/a district and/or a recent time window. Leave arguments",
        "blank for the whole loaded dataset with no date restriction."
      ),
      arguments = list(
        country     = type_string("Country name(s) to filter to, exact spelling as in the data; comma-separate for several, e.g. 'NIGERIA, NIGER, CHAD, CAMEROON' (optional)", required = FALSE),
        province    = type_string("Province/region name to filter to (optional)", required = FALSE),
        district    = type_string("District name to filter to (optional)", required = FALSE),
        months_back = type_integer("Restrict to the most recent N months of data (optional; omit for no date restriction)", required = FALSE)
      )
    ),
    ellmer::tool(
      function(n = 10, country = "", months_back = NA) {
        base <- shiny::isolate(rv$data)
        df   <- im_filter_scope(base, country = country, months_back = months_back)
        im_top_risk_text(df, n = n)
      },
      name = "get_top_priority_districts",
      description = "List the highest-risk districts (by mean risk_score) in the currently loaded repository, optionally restricted to one or more countries and/or a recent time window.",
      arguments = list(
        n           = type_integer("How many districts to return (default 10, max 50)", required = FALSE),
        country     = type_string("Restrict to this country, or a comma-separated list of countries (optional)", required = FALSE),
        months_back = type_integer("Restrict to the most recent N months of data (optional)", required = FALSE)
      )
    ),
    ellmer::tool(
      function() {
        info <- last_run_info()
        cleaned <- Filter(file.exists, c(CLEANED_RDS, CLEANED_PARQUET, CLEANED_CSV))
        fresh <- if (length(cleaned))
          paste0("Cleaned repository file: ", basename(cleaned[1]), ", last modified ",
                 format(file.info(cleaned[1])$mtime, "%Y-%m-%d %H:%M"))
        else "No cleaned repository file found yet - the pipeline may not have run."
        paste0("Last pipeline log time: ", info$time, " (status: ", info$status, ").\n", fresh)
      },
      name = "get_pipeline_status",
      description = "Check when the IM data pipeline last ran and whether the cleaned repository file the dashboard reads from is present and fresh."
    ),
    ellmer::tool(
      function(metric = "coverage", country = "", months_back = NA) {
        base <- shiny::isolate(rv$data)
        im_trend_text(base, metric = metric, country = country, months_back = months_back)
      },
      name = "get_trend_forecast",
      description = paste(
        "Fit a simple linear trend across campaign rounds (roundnumber) for",
        "coverage, missed_children, or awareness, and project the next round.",
        "This is a lightweight heuristic, not a validated forecasting model -",
        "always relay it with that caveat."
      ),
      arguments = list(
        metric      = type_enum(values = c("coverage","missed_children","awareness"),
                             description = "Which metric to project", required = FALSE),
        country     = type_string("Restrict to this country, or a comma-separated list of countries (optional)", required = FALSE),
        months_back = type_integer("Restrict to the most recent N months of data (optional)", required = FALSE)
      )
    ),
    ellmer::tool(
      function(format = "pptx", title = "", subtitle = "") {
        if (!nzchar(title)) return("Error: a title is required to start a report.")
        if (!format %in% c("pptx", "docx")) format <- "pptx"
        tryCatch({
          rv$report_builder <- ai_report_new(format = format, title = title, subtitle = subtitle)
          paste0(
            "Started a new ", toupper(format), " report titled '", title, "'. ",
            "Add sections with add_bullets_slide / add_stats_slide / add_chart_slide / ",
            "add_table_slide (call as many as needed, in any order), then call ",
            "finish_report when done. Base slide content on real numbers from ",
            "get_data_summary / get_top_priority_districts / get_trend_forecast - ",
            "never invent figures."
          )
        }, error = function(e) paste0("Error starting the report: ", conditionMessage(e)))
      },
      name = "start_report",
      description = paste(
        "Start a new, blank report/presentation that sections can then be added",
        "to one at a time. Call this ONCE per report, before any add_*_slide",
        "calls, and call finish_report exactly once at the end. Formats:",
        "pptx (PowerPoint deck) or docx (Word document)."
      ),
      arguments = list(
        format   = type_enum(values = c("pptx","docx"), description = "Output format", required = FALSE),
        title    = type_string("Report/deck title, shown on the cover", required = TRUE),
        subtitle = type_string("Optional one-line subtitle/description", required = FALSE)
      )
    ),
    ellmer::tool(
      function(title = "", body = "") {
        b <- shiny::isolate(rv$report_builder)
        if (is.null(b)) return("Error: no report in progress. Call start_report first.")
        if (!nzchar(title) || !nzchar(body))
          return("Error: both title and body (bullet points, one per line) are required.")
        tryCatch({
          new_b <- ai_report_add_bullets(b, title, body)
          rv$report_builder <- new_b
          paste0("Added a bullet-point section '", title, "'. The report now has ",
                 new_b$n_sections, " section(s) including the cover.")
        }, error = function(e) paste0("Error adding the section: ", conditionMessage(e)))
      },
      name = "add_bullets_slide",
      description = "Add a titled section with a short list of bullet points to the report currently in progress (start_report must be called first).",
      arguments = list(
        title = type_string("Section/slide title", required = TRUE),
        body  = type_string("Bullet points, one per line (a leading '-' or '*' is fine and will be stripped)", required = TRUE)
      )
    ),
    ellmer::tool(
      function(title = "", stats = "") {
        b <- shiny::isolate(rv$report_builder)
        if (is.null(b)) return("Error: no report in progress. Call start_report first.")
        if (!nzchar(title) || !nzchar(stats))
          return("Error: both title and stats ('Label: Value' lines) are required.")
        tryCatch({
          new_b <- ai_report_add_stats(b, title, stats)
          rv$report_builder <- new_b
          paste0("Added a key-numbers section '", title, "'. The report now has ",
                 new_b$n_sections, " section(s) including the cover.")
        }, error = function(e) paste0("Error adding the section: ", conditionMessage(e)))
      },
      name = "add_stats_slide",
      description = paste(
        "Add a titled section showing a row of big key numbers (like a KPI card)",
        "to the report currently in progress - good for an executive-summary slide.",
        "Give one 'Label: Value' pair per line, e.g. 'Coverage: 95.5%'. Use real",
        "numbers from get_data_summary / get_top_priority_districts, not invented ones."
      ),
      arguments = list(
        title = type_string("Section/slide title", required = TRUE),
        stats = type_string("One 'Label: Value' pair per line", required = TRUE)
      )
    ),
    ellmer::tool(
      function(title = "", headers = "", rows = "") {
        b <- shiny::isolate(rv$report_builder)
        if (is.null(b)) return("Error: no report in progress. Call start_report first.")
        if (!nzchar(title) || !nzchar(headers) || !nzchar(rows))
          return("Error: title, headers, and rows are all required.")
        tryCatch({
          new_b <- ai_report_add_table(b, title, headers, rows)
          rv$report_builder <- new_b
          paste0("Added a table section '", title, "'. The report now has ",
                 new_b$n_sections, " section(s) including the cover.")
        }, error = function(e) paste0("Error adding the table: ", conditionMessage(e)))
      },
      name = "add_table_slide",
      description = "Add a titled section containing a data table to the report currently in progress.",
      arguments = list(
        title   = type_string("Section/slide title", required = TRUE),
        headers = type_string("Column headers, comma-separated, e.g. 'Country, Coverage, Missed children'", required = TRUE),
        rows    = type_string("Table rows, one per line, cells comma-separated in the same order as headers", required = TRUE)
      )
    ),
    ellmer::tool(
      function(title = "", chart_type = "bar", categories = "", values = "", value_label = "") {
        b <- shiny::isolate(rv$report_builder)
        if (is.null(b)) return("Error: no report in progress. Call start_report first.")
        if (!chart_type %in% c("bar", "line")) chart_type <- "bar"
        if (!nzchar(title) || !nzchar(categories) || !nzchar(values))
          return("Error: title, categories, and values are all required.")
        tryCatch({
          new_b <- ai_report_add_chart(b, title, chart_type, categories, values, value_label)
          rv$report_builder <- new_b
          paste0("Added a ", chart_type, " chart section '", title, "'. The report now has ",
                 new_b$n_sections, " section(s) including the cover.")
        }, error = function(e) paste0("Error adding the chart: ", conditionMessage(e)))
      },
      name = "add_chart_slide",
      description = "Add a titled section containing a simple bar or line chart to the report currently in progress.",
      arguments = list(
        title       = type_string("Section/slide title", required = TRUE),
        chart_type  = type_enum(values = c("bar","line"), description = "Chart type", required = FALSE),
        categories  = type_string("X-axis category labels, comma-separated, e.g. 'Nigeria, Niger, Chad, Cameroon'", required = TRUE),
        values      = type_string("Numeric values, comma-separated, matching the categories in order", required = TRUE),
        value_label = type_string("Optional Y-axis/value label, e.g. 'Coverage (%)'", required = FALSE)
      )
    ),
    ellmer::tool(
      function() {
        b <- shiny::isolate(rv$report_builder)
        if (is.null(b)) return("There is no report in progress to discard.")
        tryCatch(unlink(b$tmp_dir, recursive = TRUE, force = TRUE), error = function(e) NULL)
        rv$report_builder <- NULL
        "Discarded the in-progress report."
      },
      name = "discard_report",
      description = "Discard the report currently in progress without saving it, e.g. if the user wants to start over or changes their mind."
    ),
    ellmer::tool(
      function(filename_hint = "") {
        b <- shiny::isolate(rv$report_builder)
        if (is.null(b))
          return("Error: no report in progress. Call start_report first, then add some sections.")
        if (b$n_sections <= 1)
          return(paste(
            "Error: the report only has a cover so far - add at least one section",
            "with add_bullets_slide / add_stats_slide / add_chart_slide / add_table_slide",
            "before finishing."
          ))
        tryCatch({
          path <- ai_report_save(b, filename_hint)
          rv$report_builder <- NULL
          paste0(
            "Report saved. Tell the user it is ready at this exact path on their own ",
            "computer: ", path, " (", b$n_sections, " section(s), ", toupper(b$format), ")."
          )
        }, error = function(e) paste0("Error saving the report: ", conditionMessage(e)))
      },
      name = "finish_report",
      description = "Save the report currently in progress to disk and return its file path. Call this exactly once, after all sections have been added.",
      arguments = list(
        filename_hint = type_string("A few words to use in the saved filename, e.g. 'lcb_weekly_brief' (optional)", required = FALSE)
      )
    ),
    ellmer::tool(
      function(countries = "", months_back = NA) {
        engine_script <- file.path(WORKFLOW_DIR, "scripts", "afro_im_intilligence_analysis_engine.R")
        report_script <- file.path(WORKFLOW_DIR, "scripts", "AFRO_Advocacy_Intelligence_Report.R")
        deck_script   <- file.path(WORKFLOW_DIR, "scripts", "afro_region_im_deck_generation.R")
        for (s in c(engine_script, report_script, deck_script))
          if (!file.exists(s)) return(paste0("Error: required script not found: ", s))

        old_countries <- Sys.getenv("AI_REPORT_COUNTRIES", unset = NA)
        old_months    <- Sys.getenv("AI_REPORT_MONTHS", unset = NA)
        restore_env <- function() {
          if (is.na(old_countries)) Sys.unsetenv("AI_REPORT_COUNTRIES") else Sys.setenv(AI_REPORT_COUNTRIES = old_countries)
          if (is.na(old_months))    Sys.unsetenv("AI_REPORT_MONTHS")    else Sys.setenv(AI_REPORT_MONTHS = old_months)
        }
        on.exit(restore_env(), add = TRUE)

        Sys.setenv(AI_REPORT_COUNTRIES = countries)
        if (!is.na(months_back) && is.numeric(months_back) && months_back > 0)
          Sys.setenv(AI_REPORT_MONTHS = as.character(round(months_back)))
        else
          Sys.unsetenv("AI_REPORT_MONTHS")

        tryCatch({
          out1 <- system2("Rscript", args = c(shQuote(engine_script)), stdout = TRUE, stderr = TRUE)
          out2 <- system2("Rscript", args = c(shQuote(report_script)), stdout = TRUE, stderr = TRUE)
          if (any(grepl("^Error", out2))) {
            return(paste0(
              "Error generating the full intelligence deck (advocacy report step failed):\n",
              paste(tail(out2, 15), collapse = "\n")
            ))
          }
          out3 <- system2("Rscript", args = c(shQuote(deck_script)), stdout = TRUE, stderr = TRUE)
          suffix <- if (nzchar(trimws(countries)))
            paste0("_", gsub("[^A-Za-z0-9]+", "", paste(substr(trimws(strsplit(countries, ",")[[1]]), 1, 3), collapse = "")))
          else ""
          pptx <- file.path(WORKFLOW_DIR, "outputs", "reports", "IM_Intelligence_Report",
                             paste0("AFRO_Regional_IM_Intelligence_Deck", suffix, ".pptx"))
          if (file.exists(pptx)) {
            paste0(
              "Full intelligence deck generated successfully. Tell the user it is ready at this ",
              "exact path on their own computer: ", pptx
            )
          } else {
            paste0(
              "The scripts ran but the expected deck file wasn't found (", pptx, "). Last output:\n",
              paste(tail(out3, 15), collapse = "\n")
            )
          }
        }, error = function(e) paste0("Error generating the full intelligence deck: ", conditionMessage(e)))
      },
      name = "generate_full_intelligence_deck",
      description = paste(
        "Regenerate the full, comprehensive AFRO Regional Intelligence PowerPoint deck",
        "(the same ~11-slide template used for quarterly/regional review: executive KPI",
        "card, root causes, priority districts, country risk profile, social",
        "mobilisation, risk heatmap, advocacy recommendations, and annex tables),",
        "optionally scoped to one or more countries and/or a recent time window.",
        "Use this for a comprehensive, all-of-the-above report; use start_report/",
        "add_*_slide/finish_report instead for a short bespoke deck with just the",
        "sections the user actually asked for. This runs several R scripts in",
        "sequence and can take a minute or two - tell the user to expect a short wait."
      ),
      arguments = list(
        countries   = type_string("Country name(s) to scope the deck to, comma-separated (optional; leave blank for the full region)", required = FALSE),
        months_back = type_integer("Restrict the analysis to the most recent N months (optional; defaults to 12 if omitted)", required = FALSE)
      )
    )
  )
}

# ── AI Assistant floating widget UI ─────────────────────────────────────────
# Available from every tab (rendered via page_navbar's `footer`, which bslib
# includes once regardless of the active nav_panel). Fixed-position CSS means
# its place in the DOM doesn't matter for where it visually sits.
ai_assistant_widget_ui <- function() {
  tagList(
    tags$button(id="ai_fab", class="ai-fab",
                 title="AFRO IM Assistant", type="button",
      bs_icon("robot", size="1.5rem")
    ),
    div(id="ai_panel", class="ai-panel",
      div(class="ai-panel-header",
        div(class="d-flex align-items-center gap-2",
          bs_icon("robot", size="1.1rem"),
          div(
            div(style="font-weight:800;font-size:.85rem;line-height:1.2;", "AFRO IM Assistant"),
            div(style="font-size:.65rem;opacity:.8;", "Data, workflow, and report questions")
          )
        ),
        tags$button(class="ai-panel-close",
                     title="Close", type="button", bs_icon("x-lg"))
      ),
      div(class="ai-panel-body",
        if (AI_ASSISTANT_ENABLED)
          shinychat::chat_ui("ai_chat",
            placeholder = "Ask about coverage, risk, the pipeline...",
            height = "100%", fill = TRUE,
            greeting = paste(
              "Hi! I'm the AFRO IM Assistant. I know the IM workflow, the",
              "data dictionary, and can pull live stats, risk rankings,",
              "pipeline status, and simple trends from what's currently",
              "loaded. What would you like to know?"
            )
          )
        else
          div(style="padding:16px;font-size:.82rem;color:var(--muted);",
            p(style="margin-bottom:8px;",
              "The AI Assistant isn't configured yet."),
            p(style="margin-bottom:8px;",
              "Add your Anthropic API key to ", tags$code("config/secrets.env"),
              " as:"),
            tags$pre(style="background:#F0F4F8;padding:8px;border-radius:8px;font-size:.72rem;",
                      "ANTHROPIC_API_KEY=sk-ant-..."),
            p("Then restart the app.")
          )
      )
    )
  )
}
