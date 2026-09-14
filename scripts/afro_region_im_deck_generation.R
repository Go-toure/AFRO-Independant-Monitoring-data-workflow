# ============================================================
# AFRO REGIONAL IM POWERPOINT GENERATOR
# Stable version - native PowerPoint widescreen 16:9
# Slide size: 33.867 cm x 19.05 cm
# ============================================================

pacman::p_load(
  officer, flextable, readxl, dplyr, stringr, scales, tidyverse
)

# ============================================================
# PATHS - CONNECTED TO IM WORKFLOW
# ============================================================

# Main workflow directory
# Set once via `setx IM_WORKFLOW_HOME "D:/new/path"` (Windows) if this
# project ever moves off this laptop/drive -- every script in the pipeline
# reads the same variable, so nothing else needs editing.
workflow_dir <- Sys.getenv("IM_WORKFLOW_HOME", unset = "C:/Users/TOURE/Documents/im_workflow")

# Input: Intelligence report outputs from AFRO_Advocacy_Intelligence_Report.R
intelligence_dir <- file.path(workflow_dir, "outputs/reports/IM_Intelligence_Report")
plot_dir <- file.path(intelligence_dir, "plots")
xlsx_file <- file.path(intelligence_dir, "AFRO_Regional_IM_Intelligence_Report.xlsx")

# Country scope (optional, cosmetic only here): if AI_REPORT_COUNTRIES was set
# for the AFRO_Advocacy_Intelligence_Report.R run that produced xlsx_file/
# plot_dir above, mirror it on the cover slide and in the output filename so a
# scoped deck doesn't read as (or overwrite) the full regional one. The actual
# data filtering already happened upstream in that report - this script only
# assembles the images/tables it produced, so no filtering logic is needed here.
report_target_countries <- trimws(strsplit(Sys.getenv("AI_REPORT_COUNTRIES", unset = ""), ",", fixed = TRUE)[[1]])
report_target_countries <- report_target_countries[nzchar(report_target_countries)]
report_scope_label <- if (length(report_target_countries)) paste(report_target_countries, collapse = ", ") else "AFRO Regional (all countries)"
report_scope_suffix <- if (length(report_target_countries))
  paste0("_", gsub("[^A-Za-z0-9]+", "", paste(substr(report_target_countries, 1, 3), collapse = ""))) else ""

# Output: PowerPoint deck
pptx_out <- file.path(intelligence_dir, paste0("AFRO_Regional_IM_Intelligence_Deck", report_scope_suffix, ".pptx"))

# Check if required files exist
if (!file.exists(xlsx_file)) {
  stop("Excel report not found. Please run AFRO_Advocacy_Intelligence_Report.R first.")
}

if (!dir.exists(plot_dir)) {
  stop("Plots directory not found. Please run AFRO_Advocacy_Intelligence_Report.R first.")
}

# ============================================================
# POWERPOINT GENERATION
# ============================================================

ppt <- read_pptx()

ppt_size <- slide_size(ppt)
message("PowerPoint slide width: ", round(ppt_size$width * 2.54, 3), " cm")
message("PowerPoint slide height: ", round(ppt_size$height * 2.54, 3), " cm")

add_blank_slide <- function(ppt) {
  add_slide(ppt, layout = "Blank", master = "Office Theme")
}

add_title <- function(ppt, title, subtitle = NULL) {
  ppt <- ph_with(
    ppt, title,
    location = ph_location(left = 0.25, top = 0.15, width = 12.9, height = 0.45)
  )
  
  if (!is.null(subtitle)) {
    ppt <- ph_with(
      ppt, subtitle,
      location = ph_location(left = 0.25, top = 0.65, width = 12.9, height = 0.35)
    )
  }
  
  ppt
}

add_footer <- function(ppt) {
  ph_with(
    ppt,
    "AFRO Regional Independent Monitoring Intelligence | Regional Programme Review",
    location = ph_location(left = 0.25, top = 7.08, width = 12.9, height = 0.22)
  )
}

add_image_slide <- function(ppt, title, img, subtitle = NULL) {
  if (!file.exists(img)) {
    warning("Image not found: ", img)
    return(ppt)
  }
  
  ppt <- add_blank_slide(ppt)
  ppt <- add_title(ppt, title, subtitle)
  
  ppt <- ph_with(
    ppt,
    external_img(img),
    location = ph_location(left = 0.15, top = 0.95, width = 13.05, height = 6.10)
  )
  
  add_footer(ppt)
}

# ============================================================
# COVER SLIDE
# ============================================================
ppt <- add_blank_slide(ppt)

ppt <- ph_with(
  ppt,
  if (length(report_target_countries)) paste0(report_scope_label, " - Independent Monitoring Intelligence")
  else "AFRO Regional Independent Monitoring Intelligence",
  location = ph_location(left = 0.65, top = 1.8, width = 12.1, height = 0.9)
)

ppt <- ph_with(
  ppt,
  "Programme review: missed children, operational gaps, social mobilisation and priority districts",
  location = ph_location(left = 0.65, top = 2.85, width = 12.1, height = 0.6)
)

ppt <- ph_with(
  ppt,
  paste0("Generated: ", Sys.Date(), " | Source: AFRO IM Workflow"),
  location = ph_location(left = 0.65, top = 3.8, width = 12.1, height = 0.4)
)

ppt <- add_footer(ppt)

# ============================================================
# MAIN REGIONAL SLIDES
# ============================================================

# Try different possible filenames (the report may use different naming conventions)
possible_names <- list(
  kpi = c("00_AFRO_executive_KPI_card.png", "00_AFRO_executive_KPI_card_EXECUTIVE.png"),
  root_causes = c("01_AFRO_root_causes_missed_children.png", "01_AFRO_root_causes_missed_children_EXECUTIVE.png"),
  priority = c("02_AFRO_top_priority_districts.png", "02_AFRO_top_priority_districts_EXECUTIVE.png"),
  country_risk = c("03_AFRO_country_risk_profile.png", "03_AFRO_country_risk_profile_EXECUTIVE.png"),
  sm_awareness = c("04_AFRO_SM_awareness_vs_coverage.png", "04_AFRO_SM_awareness_vs_coverage_EXECUTIVE.png"),
  cv_heatmap = c("05_AFRO_cv_heatmap.png"),
  advocacy = c("06_AFRO_advocacy_recommendation_card.png", "05_AFRO_advocacy_recommendation_card.png")
)

# Find existing images
find_image <- function(possible_paths) {
  for (path in possible_paths) {
    full_path <- file.path(plot_dir, path)
    if (file.exists(full_path)) {
      return(full_path)
    }
  }
  return(NULL)
}

# Executive KPI Card
img <- find_image(possible_names$kpi)
if (!is.null(img)) {
  ppt <- add_image_slide(ppt, "Executive Regional Snapshot", img)
} else {
  warning("Executive KPI card image not found")
}

# Root Causes
img <- find_image(possible_names$root_causes)
if (!is.null(img)) {
  ppt <- add_image_slide(ppt, "Why Children Are Missed Across AFRO Countries", img)
} else {
  warning("Root causes image not found")
}

# Priority Districts
img <- find_image(possible_names$priority)
if (!is.null(img)) {
  ppt <- add_image_slide(ppt, "Priority Districts Requiring Regional Action", img)
} else {
  warning("Priority districts image not found")
}

# Country Risk Profile
img <- find_image(possible_names$country_risk)
if (!is.null(img)) {
  ppt <- add_image_slide(ppt, "Country-Level Risk Profile", img)
} else {
  warning("Country risk profile image not found")
}

# Social Mobilisation
img <- find_image(possible_names$sm_awareness)
if (!is.null(img)) {
  ppt <- add_image_slide(ppt, "Social Mobilisation Awareness vs Coverage", img)
} else {
  warning("Social mobilisation image not found")
}

# CV Heatmap
img <- find_image(possible_names$cv_heatmap)
if (!is.null(img)) {
  ppt <- add_image_slide(ppt, "CV Heatmap — Country × Campaign Round", img)
} else {
  message("CV heatmap image not found (will be skipped)")
}

# Advocacy Recommendations
img <- find_image(possible_names$advocacy)
if (!is.null(img)) {
  ppt <- add_image_slide(ppt, "Priority Regional Advocacy Actions", img)
} else {
  warning("Advocacy recommendations image not found")
}

# ============================================================
# ANNEX TABLE: TOP 30 PRIORITY DISTRICTS
# ============================================================
if (file.exists(xlsx_file)) {
  # Try different possible sheet names
  sheet_name <- NULL
  possible_sheets <- c("Top 30 Priority", "07_AFRO_top_30_priority_districts", "Top 30 Priority Districts")
  
  for (sheet in possible_sheets) {
    if (sheet %in% excel_sheets(xlsx_file)) {
      sheet_name <- sheet
      break
    }
  }
  
  if (!is.null(sheet_name)) {
    top30 <- read_excel(xlsx_file, sheet = sheet_name) %>%
      select(any_of(c(
        "country", "province", "district", "total_missed", "mean_cv",
        "mean_awareness_rate", "mean_risk_score", "priority_class"
      ))) %>%
      mutate(
        mean_cv = if("mean_cv" %in% names(.)) percent(mean_cv, accuracy = 0.1) else NA,
        mean_awareness_rate = if("mean_awareness_rate" %in% names(.)) percent(mean_awareness_rate, accuracy = 0.1) else NA,
        mean_risk_score = if("mean_risk_score" %in% names(.)) round(mean_risk_score, 1) else NA
      )
    
    ft <- flextable(top30) %>%
      theme_vanilla() %>%
      fontsize(size = 7, part = "all") %>%
      bold(part = "header") %>%
      autofit()
    
    ppt <- add_blank_slide(ppt)
    
    ppt <- add_title(
      ppt,
      "Annex: Top 30 Priority Districts",
      "Districts requiring priority regional action and partner support"
    )
    
    ppt <- ph_with(
      ppt,
      ft,
      location = ph_location(left = 0.2, top = 1.05, width = 13.0, height = 5.95)
    )
    
    ppt <- add_footer(ppt)
  } else {
    warning("Top 30 Priority sheet not found in Excel file")
  }
  
  # ============================================================
  # ANNEX TABLE: COUNTRY SUMMARY
  # ============================================================
  sheet_name <- NULL
  possible_sheets <- c("Country Summary", "08_AFRO_country_summary", "Country Summary Regional")
  
  for (sheet in possible_sheets) {
    if (sheet %in% excel_sheets(xlsx_file)) {
      sheet_name <- sheet
      break
    }
  }
  
  if (!is.null(sheet_name)) {
    country_summary <- read_excel(xlsx_file, sheet = sheet_name) %>%
      select(any_of(c(
        "country", "provinces", "districts", "total_missed",
        "mean_cv", "mean_awareness_rate", "mean_risk_score",
        "critical_events", "high_risk_events"
      ))) %>%
      mutate(
        mean_cv = if("mean_cv" %in% names(.)) percent(mean_cv, accuracy = 0.1) else NA,
        mean_awareness_rate = if("mean_awareness_rate" %in% names(.)) percent(mean_awareness_rate, accuracy = 0.1) else NA,
        mean_risk_score = if("mean_risk_score" %in% names(.)) round(mean_risk_score, 1) else NA
      )
    
    ft_country <- flextable(country_summary) %>%
      theme_vanilla() %>%
      fontsize(size = 8, part = "all") %>%
      bold(part = "header") %>%
      autofit()
    
    ppt <- add_blank_slide(ppt)
    
    ppt <- add_title(
      ppt,
      "Annex: Country Summary",
      "Regional overview by country"
    )
    
    ppt <- ph_with(
      ppt,
      ft_country,
      location = ph_location(left = 0.25, top = 1.1, width = 12.9, height = 5.8)
    )
    
    ppt <- add_footer(ppt)
  } else {
    warning("Country Summary sheet not found in Excel file")
  }
} else {
  warning("Excel file not found: ", xlsx_file)
}

# ============================================================
# CLOSING SLIDE (Optional)
# ============================================================
ppt <- add_blank_slide(ppt)

ppt <- add_title(
  ppt,
  "Thank You",
  "For more information, contact the AFRO IM Team"
)

closing_img <- find_image(possible_names$advocacy)
if (!is.null(closing_img)) {
  ppt <- ph_with(
    ppt,
    external_img(closing_img),
    location = ph_location(left = 1.5, top = 1.5, width = 10.5, height = 5.0)
  )
}

ppt <- add_footer(ppt)

# ============================================================
# SAVE POWERPOINT
# ============================================================
print(ppt, target = pptx_out)

# ============================================================
# SUMMARY
# ============================================================
cat("\n")
cat("============================================================\n")
cat("AFRO REGIONAL IM POWERPOINT DECK GENERATED\n")
cat("============================================================\n")
cat("File:", pptx_out, "\n")
cat("Expected slide size: 33.867 cm x 19.05 cm\n")
cat("Actual width:", round(ppt_size$width * 2.54, 3), "cm\n")
cat("Actual height:", round(ppt_size$height * 2.54, 3), "cm\n")
cat("============================================================\n")

# List all slides in the deck
message("\nSlides generated:")
message("  - Cover slide")
message("  - Executive Regional Snapshot")
message("  - Why Children Are Missed Across AFRO Countries")
message("  - Priority Districts Requiring Regional Action")
message("  - Country-Level Risk Profile")
message("  - Social Mobilisation Awareness vs Coverage")
message("  - CV Heatmap — Country × Campaign Round")
message("  - Priority Regional Advocacy Actions")
message("  - Annex: Top 30 Priority Districts")
message("  - Annex: Country Summary")
message("  - Closing slide")
message("============================================================")