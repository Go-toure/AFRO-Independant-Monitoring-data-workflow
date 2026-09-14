# ============================================================
# AI ASSISTANT — GENERIC REPORT/DECK BUILDER
# ============================================================
# New file (not moved from app.R): the rendering primitives behind the
# AI Assistant's start_report / add_*_slide / finish_report tools (see
# ai_assistant_tools.R). The assistant decides WHAT goes in a report
# (titles, bullet text, which numbers, chart data) by calling these
# functions through its tools; it never writes or executes R code itself
# -- every function below is fixed, ordinary R using packages already
# loaded by this app (officer, ggplot2, flextable), so the actual
# document-building logic is exactly as testable/reviewable as any other
# script in this project.
#
# Colors and the ggplot theme are reused from the existing premium report
# scripts (AFRO_Advocacy_Intelligence_Report.R) for visual consistency
# with the "full" intelligence deck.
#
# A "builder" is a plain list: list(doc=<officer object>, format=<"pptx"|
# "docx">, tmp_dir=<scratch folder for chart PNGs>, n_sections=<count>).
# Every ai_report_add_*() function takes a builder and returns an updated
# one (officer documents are immutable-per-call, like ggplot layers), so
# callers must always reassign: builder <- ai_report_add_bullets(builder, ...).
# ============================================================

AI_RPT_COLORS <- list(
  who_blue   = "#0093D5", dark_blue = "#003A70", alert_red = "#C00000",
  warning_orange = "#F28C28", soft_grey = "#F5F7FA", dark_grey = "#3A3A3A",
  green_ok   = "#8CC63E", purple_alert = "#7A1FA2"
)

ai_report_theme <- function(base_size = 13) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(face = "bold", size = base_size + 4, color = AI_RPT_COLORS$dark_blue),
      plot.subtitle    = ggplot2::element_text(size = base_size, color = AI_RPT_COLORS$dark_grey),
      axis.title       = ggplot2::element_text(face = "bold", color = AI_RPT_COLORS$dark_grey),
      axis.text        = ggplot2::element_text(color = AI_RPT_COLORS$dark_grey),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_line(color = "grey88"),
      plot.background  = ggplot2::element_rect(fill = "white", color = NA),
      panel.background = ggplot2::element_rect(fill = "white", color = NA),
      legend.position  = "bottom",
      legend.title     = ggplot2::element_blank()
    )
}

# ── Start a new report ───────────────────────────────────────────────────
ai_report_new <- function(format = c("pptx", "docx"), title, subtitle = "") {
  format <- match.arg(format)
  tmp_dir <- tempfile("ai_report_")
  dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)

  if (format == "pptx") {
    doc <- officer::read_pptx()
    doc <- officer::add_slide(doc, layout = "Blank", master = "Office Theme")
    doc <- officer::ph_with(doc, title,
             location = officer::ph_location(left = 0.65, top = 1.8, width = 12.1, height = 0.9))
    if (nzchar(subtitle))
      doc <- officer::ph_with(doc, subtitle,
               location = officer::ph_location(left = 0.65, top = 2.85, width = 12.1, height = 0.6))
    doc <- officer::ph_with(doc, paste0("Generated: ", Sys.Date(), " | AFRO IM Assistant"),
             location = officer::ph_location(left = 0.65, top = 3.8, width = 12.1, height = 0.4))
  } else {
    doc <- officer::read_docx()
    doc <- officer::body_add_par(doc, title, style = "Title")
    if (nzchar(subtitle)) doc <- officer::body_add_par(doc, subtitle, style = "Subtitle")
    doc <- officer::body_add_par(doc, paste0("Generated: ", Sys.Date(), " | AFRO IM Assistant"), style = "Normal")
  }

  list(doc = doc, format = format, tmp_dir = tmp_dir, n_sections = 1)
}

# ── Bullet-point section ─────────────────────────────────────────────────
ai_report_add_bullets <- function(builder, title, body_text) {
  bullets <- strsplit(body_text, "\n", fixed = TRUE)[[1]]
  bullets <- trimws(bullets)
  bullets <- sub("^[-*•]\\s*", "", bullets)
  bullets <- bullets[nzchar(bullets)]
  if (!length(bullets)) bullets <- "(no content provided)"

  doc <- builder$doc
  if (builder$format == "pptx") {
    doc <- officer::add_slide(doc, layout = "Blank", master = "Office Theme")
    doc <- officer::ph_with(doc, title,
             location = officer::ph_location(left = 0.25, top = 0.15, width = 12.9, height = 0.5))
    doc <- officer::ph_with(doc, paste0("•  ", bullets),
             location = officer::ph_location(left = 0.5, top = 0.95, width = 12.4, height = 5.9))
  } else {
    doc <- officer::body_add_par(doc, title, style = "heading 1")
    for (b in bullets) doc <- officer::body_add_par(doc, b, style = "List Bullet")
  }
  builder$doc <- doc
  builder$n_sections <- builder$n_sections + 1
  builder
}

# ── Key-numbers ("stat card") section ────────────────────────────────────
ai_report_add_stats <- function(builder, title, stats_text) {
  lines <- strsplit(stats_text, "\n", fixed = TRUE)[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  labels <- character(0); values <- character(0)
  for (ln in lines) {
    parts <- strsplit(ln, ":", fixed = TRUE)[[1]]
    if (length(parts) >= 2) {
      labels <- c(labels, trimws(parts[1]))
      values <- c(values, trimws(paste(parts[-1], collapse = ":")))
    }
  }
  if (!length(labels)) { labels <- "Note"; values <- "No parsable 'Label: Value' lines were provided." }

  stat_df <- as.data.frame(setNames(as.list(values), labels),
                            check.names = FALSE, stringsAsFactors = FALSE)
  ft <- flextable::flextable(stat_df)
  ft <- flextable::align(ft, align = "center", part = "all")
  ft <- flextable::bold(ft, part = "all")
  ft <- flextable::fontsize(ft, size = 12, part = "header")
  ft <- flextable::fontsize(ft, size = 22, part = "body")
  ft <- flextable::color(ft, color = AI_RPT_COLORS$dark_blue, part = "body")
  ft <- flextable::color(ft, color = AI_RPT_COLORS$dark_grey, part = "header")
  ft <- flextable::border_outer(ft, part = "all",
          border = officer::fp_border(color = AI_RPT_COLORS$who_blue, width = 1))
  ft <- flextable::autofit(ft)

  doc <- builder$doc
  if (builder$format == "pptx") {
    doc <- officer::add_slide(doc, layout = "Blank", master = "Office Theme")
    doc <- officer::ph_with(doc, title,
             location = officer::ph_location(left = 0.25, top = 0.15, width = 12.9, height = 0.5))
    doc <- officer::ph_with(doc, ft,
             location = officer::ph_location(left = 0.4, top = 1.4, width = 12.6, height = 2.4))
  } else {
    doc <- officer::body_add_par(doc, title, style = "heading 1")
    doc <- flextable::body_add_flextable(doc, ft)
  }
  builder$doc <- doc
  builder$n_sections <- builder$n_sections + 1
  builder
}

# ── Table section ────────────────────────────────────────────────────────
ai_report_add_table <- function(builder, title, headers_csv, rows_text) {
  headers <- trimws(strsplit(headers_csv, ",", fixed = TRUE)[[1]])
  headers <- headers[nzchar(headers)]
  if (!length(headers)) headers <- "Column 1"

  row_lines <- strsplit(rows_text, "\n", fixed = TRUE)[[1]]
  row_lines <- trimws(row_lines)
  row_lines <- row_lines[nzchar(row_lines)]

  rows <- lapply(row_lines, function(rl) {
    cells <- trimws(strsplit(rl, ",", fixed = TRUE)[[1]])
    length(cells) <- length(headers)
    cells[is.na(cells)] <- ""
    cells
  })
  if (!length(rows)) rows <- list(rep("", length(headers)))

  df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(df) <- headers

  ft <- flextable::flextable(df)
  ft <- flextable::theme_vanilla(ft)
  ft <- flextable::fontsize(ft, size = 9, part = "all")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::autofit(ft)

  doc <- builder$doc
  if (builder$format == "pptx") {
    doc <- officer::add_slide(doc, layout = "Blank", master = "Office Theme")
    doc <- officer::ph_with(doc, title,
             location = officer::ph_location(left = 0.25, top = 0.15, width = 12.9, height = 0.5))
    doc <- officer::ph_with(doc, ft,
             location = officer::ph_location(left = 0.2, top = 1.0, width = 13.0, height = 6.0))
  } else {
    doc <- officer::body_add_par(doc, title, style = "heading 1")
    doc <- flextable::body_add_flextable(doc, ft)
  }
  builder$doc <- doc
  builder$n_sections <- builder$n_sections + 1
  builder
}

# ── Chart section (simple bar/line) ──────────────────────────────────────
ai_report_add_chart <- function(builder, title, chart_type = c("bar", "line"),
                                  categories_csv, values_csv, value_label = "") {
  chart_type <- match.arg(chart_type)
  categories <- trimws(strsplit(categories_csv, ",", fixed = TRUE)[[1]])
  values     <- suppressWarnings(as.numeric(trimws(strsplit(values_csv, ",", fixed = TRUE)[[1]])))
  n <- min(length(categories), length(values))
  if (n < 1) stop("Need at least one matching category/value pair to draw a chart.")
  categories <- categories[seq_len(n)]
  values     <- values[seq_len(n)]
  if (all(is.na(values))) stop("None of the supplied values could be read as numbers.")

  df <- data.frame(category = factor(categories, levels = categories), value = values)
  y_lab <- if (nzchar(value_label)) value_label else NULL

  p <- if (chart_type == "bar") {
    ggplot2::ggplot(df, ggplot2::aes(x = category, y = value)) +
      ggplot2::geom_col(fill = AI_RPT_COLORS$who_blue) +
      ggplot2::labs(x = NULL, y = y_lab, title = title) +
      ai_report_theme()
  } else {
    ggplot2::ggplot(df, ggplot2::aes(x = category, y = value, group = 1)) +
      ggplot2::geom_line(color = AI_RPT_COLORS$who_blue, linewidth = 1.2) +
      ggplot2::geom_point(color = AI_RPT_COLORS$dark_blue, size = 2.5) +
      ggplot2::labs(x = NULL, y = y_lab, title = title) +
      ai_report_theme()
  }

  img_path <- file.path(builder$tmp_dir, paste0("chart_", builder$n_sections, ".png"))
  ggplot2::ggsave(img_path, p, width = 9, height = 5, dpi = 200, bg = "white")

  doc <- builder$doc
  if (builder$format == "pptx") {
    doc <- officer::add_slide(doc, layout = "Blank", master = "Office Theme")
    doc <- officer::ph_with(doc, title,
             location = officer::ph_location(left = 0.25, top = 0.15, width = 12.9, height = 0.45))
    doc <- officer::ph_with(doc, officer::external_img(img_path),
             location = officer::ph_location(left = 0.5, top = 0.9, width = 12.4, height = 5.9))
  } else {
    doc <- officer::body_add_par(doc, title, style = "heading 1")
    doc <- officer::body_add_img(doc, img_path, width = 6, height = 3.3)
  }
  builder$doc <- doc
  builder$n_sections <- builder$n_sections + 1
  builder
}

# ── Save & clean up ───────────────────────────────────────────────────────
ai_report_save <- function(builder, filename_hint = "") {
  out_dir <- file.path(BASE_DIR, "outputs", "reports", "ai_generated")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  slug <- tolower(gsub("[^A-Za-z0-9]+", "_", filename_hint))
  slug <- gsub("^_+|_+$", "", slug)
  if (!nzchar(slug)) slug <- "report"

  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  ext <- if (builder$format == "pptx") "pptx" else "docx"
  out_file <- file.path(out_dir, paste0(stamp, "_", slug, ".", ext))

  print(builder$doc, target = out_file)
  tryCatch(unlink(builder$tmp_dir, recursive = TRUE, force = TRUE), error = function(e) NULL)

  out_file
}
