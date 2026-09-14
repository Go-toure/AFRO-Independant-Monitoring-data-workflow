# ============================================================
# UI COMPONENT HELPERS
# ============================================================
# Moved out of shiny_app/app.R during the app.R modularization pass.
# This file lives in shiny_app/R/ , which Shiny's runApp() sources
# automatically before app.R itself runs (shiny::loadSupport()), so
# no explicit source() call is needed anywhere -- everything defined
# here is available to app.R exactly as if it were still inline.
# Content is verbatim from the original app.R (byte-identical).
# ============================================================

# ── UI COMPONENTS ─────────────────────────────────────────────────────────────
kpi <- function(id, label, icon_chr, style, sub = "",
                trend = NULL, bar_pct = NULL, compact = FALSE) {
  # Map old style names → new gradient classes
  grad <- switch(style,
    "kpi-blue"   = "background:linear-gradient(140deg,#003F6B 0%,#005C97 55%,#1A7BBF 100%);",
    "kpi-teal"   = "background:linear-gradient(140deg,#007B8A 0%,#00C9C8 100%);",
    "kpi-green"  = "background:linear-gradient(140deg,#1A7A44 0%,#27AE60 55%,#2ECC71 100%);",
    "kpi-orange" = "background:linear-gradient(140deg,#B8520A 0%,#E8730A 55%,#F39C12 100%);",
    "kpi-purple" = "background:linear-gradient(140deg,#5D2A7A 0%,#8E44AD 55%,#9B59B6 100%);",
    "kpi-red"    = "background:linear-gradient(140deg,#922B21 0%,#C0392B 55%,#E74C3C 100%);",
    "background:linear-gradient(140deg,#003F6B,#005C97);"
  )
  div(class = paste0("kpi2", if (compact) " kpi2-compact" else ""), style = grad,
    # top row: chip + optional trend pill
    div(class = "kpi2-top",
      div(class = "kpi2-chip", icon_chr),
      if (!is.null(trend))
        div(class = "kpi2-trend", trend)
    ),
    # main value + label
    div(class = "kpi2-body",
      div(class = "kpi2-val", id = id, "—"),
      div(class = "kpi2-label", label),
      if (nchar(sub) > 0)
        div(style = paste0("font-size:", if (compact) ".58rem" else ".67rem",
                            ";opacity:.68;margin-top:3px;position:relative;z-index:1;"), sub)
    ),
    # thin progress bar
    if (!is.null(bar_pct))
      div(class = "kpi2-bar",
        div(class = "kpi2-bar-fill",
            style = paste0("width:", min(bar_pct * 100, 100), "%;")))
  )
}

plotly_base <- function() {
  list(
    plot_bgcolor  = "rgba(0,0,0,0)",
    paper_bgcolor = "rgba(0,0,0,0)",
    font          = list(family="Inter, sans-serif", color="#1A2637", size=12),
    hoverlabel    = list(bgcolor="#1A2637", bordercolor="transparent",
                         font=list(color="white", family="Inter", size=12)),
    margin        = list(t=10, b=10, l=10, r=10),
    legend        = list(bgcolor="rgba(0,0,0,0)", bordercolor="rgba(0,0,0,0)")
  )
}

# !!! splicing doesn't work in plotly::layout — use do.call wrapper instead
im_layout <- function(p, ..., .filename = "im_chart", .title = NULL) {
  base   <- plotly_base()
  extras <- list(...)
  # Inject title into layout only when .title is given and caller didn't pass title= directly
  if (!is.null(.title) && !"title" %in% names(extras)) {
    base$margin$t <- 46
    title_arg <- list(
      title = list(
        text    = .title,
        font    = list(family = "Inter, sans-serif", size = 13, color = "#1A2637"),
        x       = 0.01,
        xanchor = "left",
        pad     = list(b = 2)
      )
    )
  } else {
    title_arg <- list()
  }
  do.call(plotly::layout, c(list(p), base, title_arg, extras)) %>%
    plotly::config(
      displayModeBar         = TRUE,
      displaylogo            = FALSE,
      modeBarButtonsToRemove = list("lasso2d","select2d","autoScale2d"),
      toImageButtonOptions   = list(
        format   = "png",
        filename = .filename,
        height   = 550,
        width    = 900,
        scale    = 2
      )
    )
}

# Small download button helpers (for card headers)
dl_btn <- function(id, label = NULL) {
  if (is.null(label)) label <- tagList(bs_icon("download", class = "me-1"), "CSV")
  downloadButton(id, label, class = "btn-dl")
}

# Icon + text helper — keeps icon/label spacing consistent everywhere a
# bsicons glyph replaces what used to be an emoji (nav tabs, card headers,
# section titles, buttons). Bootstrap Icons render as inline SVG, so unlike
# emoji they're crisp, recolorable via CSS, and identical across OS/browser.
hdr_icon <- function(icon_name, text, icon_size = "1rem") {
  tagList(
    bs_icon(icon_name, size = icon_size, class = "me-2",
            style = "vertical-align:-0.15em;"),
    text
  )
}
