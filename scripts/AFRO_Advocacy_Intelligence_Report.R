# ============================================================
# AFRO REGIONAL IM INTELLIGENCE REPORT
# Purpose: Regional Independent Monitoring intelligence analysis
# Input: Phase1_IM_Intelligence outputs
# Outputs: Excel, Word brief, CSV tables, premium PNG visuals
# District uniqueness: country + province + district
# ============================================================

pacman::p_load(
  tidyverse, lubridate, readr, openxlsx, janitor,
  scales, glue, flextable, officer, ggplot2,
  patchwork, cowplot, stringr, forcats
)

# ============================================================
# PATHS
# ============================================================
# Connected to the im_workflow pipeline: phase1_dir must match the output_dir
# used by afro_im_intilligence_analysis_engine.R (runs immediately before this
# script in run_workflow.R). output_dir matches the existing
# outputs/reports/IM_Intelligence_Report folder that
# afro_region_im_deck_generation.R reads from afterwards.
# BASE_DIR: when this script runs the normal way -- source_safely()
# from inside run_workflow.R, for Step 4's optional reports --
# run_workflow.R's own BASE_DIR (already resolved via the shared
# find_workflow_home()) is sitting right there in this same R
# session, so just reuse it. Only resolve it fresh (searching upward
# from the working directory, same logic find_workflow_home() itself
# uses) for a standalone run. This replaces a hardcoded Windows-laptop
# fallback path that was silently wrong on Connect Cloud otherwise.
if (!exists("BASE_DIR", inherits = TRUE)) {
  .aair_dir <- getwd()
  .aair_fwh <- NULL
  for (.aair_i in 1:6) {
    .aair_candidate <- file.path(.aair_dir, "scripts", "find_workflow_home.R")
    if (file.exists(.aair_candidate)) { .aair_fwh <- .aair_candidate; break }
    .aair_parent <- dirname(.aair_dir)
    if (identical(.aair_parent, .aair_dir)) break
    .aair_dir <- .aair_parent
  }
  if (is.null(.aair_fwh))
    stop("Could not locate scripts/find_workflow_home.R by searching upward from: ", getwd())
  source(.aair_fwh)
  BASE_DIR <- find_workflow_home()
  rm(.aair_dir, .aair_fwh, .aair_i, .aair_candidate)
  if (exists(".aair_parent")) rm(.aair_parent)
}
phase1_dir <- file.path(BASE_DIR, "outputs/phase1_intelligence")
tables_dir <- file.path(phase1_dir, "tables")

output_dir <- file.path(BASE_DIR, "outputs/reports/IM_Intelligence_Report")
plot_dir   <- file.path(output_dir, "plots")
table_dir  <- file.path(output_dir, "tables")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

risk_file <- file.path(tables_dir, "04_district_risk_scoring.csv")
root_file <- file.path(tables_dir, "01_missed_children_root_cause.csv")
op_file   <- file.path(tables_dir, "03_operational_failure_analysis.csv")
sm_file   <- file.path(tables_dir, "02_sm_effectiveness_analysis.csv")

# ============================================================
# ANALYSIS PERIOD
# Change analysis_months to the number of most recent campaign months
# to include.  Set analysis_end_date to a specific Date if required;
# otherwise the newest campaign date in the source repository is used.
# Can be overridden without editing this file by setting the AI_REPORT_MONTHS
# environment variable (used by the AFRO IM Assistant's on-demand report
# generation, and available for manual runs too via `setx`/`Sys.setenv`).
# ============================================================
analysis_months <- suppressWarnings(as.integer(Sys.getenv("AI_REPORT_MONTHS", unset = "12")))
if (is.na(analysis_months) || analysis_months < 1) analysis_months <- 12L
analysis_end_date <- NULL  # e.g. as.Date("2026-07-31")

# ============================================================
# COUNTRY SCOPE (optional)
# Set the AI_REPORT_COUNTRIES environment variable to a comma-separated
# list (case-insensitive) to scope this report to a subset of countries,
# e.g. from the AI Assistant's on-demand report generation. Leave unset/
# blank for the full region - the original, unscoped behaviour.
# ============================================================
target_countries <- trimws(strsplit(Sys.getenv("AI_REPORT_COUNTRIES", unset = ""), ",", fixed = TRUE)[[1]])
target_countries <- target_countries[nzchar(target_countries)]
report_scope_label <- if (length(target_countries)) paste(target_countries, collapse = ", ") else "AFRO Regional (all countries)"

source_repository_file <- file.path(BASE_DIR, "data/final/Regional_IM_repository_cleaned.csv")

if (!is.numeric(analysis_months) || length(analysis_months) != 1 ||
    is.na(analysis_months) || analysis_months < 1 || analysis_months != as.integer(analysis_months)) {
  stop("analysis_months must be one whole number greater than or equal to 1.")
}

# Recover this script's inputs from SharePoint if the Shiny dashboard just
# launched this as its own standalone "Generate Report + Deck" step (via
# generate_reports_and_deck.R), on a fresh container where Clean Geonames
# and/or the Intelligence Engine didn't just run in this same session --
# see scripts/sharepoint_recovery.R's own header comment.
source(file.path(BASE_DIR, "scripts", "sharepoint_recovery.R"))
sp_load_secrets_env(BASE_DIR)
tryCatch({
  sp_recover_file(
    source_repository_file,
    paste0("7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/clean_state/", basename(source_repository_file))
  )
}, error = function(e) {
  # Best-effort recovery, not required -- an unexpected bug here should
  # never stop this script before it even attempts to load its inputs
  # (see afro_im_intilligence_analysis_engine.R's matching comment for
  # why this defensive wrapping was added).
  message("SharePoint recovery of ", basename(source_repository_file), " hit an unexpected error (continuing): ", conditionMessage(e))
})
for (phase1_file in c(risk_file, root_file, op_file, sm_file)) {
  tryCatch({
    sp_recover_file(
      phase1_file,
      paste0("7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/phase1_state/", basename(phase1_file))
    )
  }, error = function(e) {
    message("SharePoint recovery of ", basename(phase1_file), " hit an unexpected error (continuing): ", conditionMessage(e))
  })
}


# ============================================================
# LOAD PHASE 1 OUTPUTS
# ============================================================
risk <- read_csv(risk_file, show_col_types = FALSE) %>% clean_names()
root <- read_csv(root_file, show_col_types = FALSE) %>% clean_names()
op   <- read_csv(op_file, show_col_types = FALSE) %>% clean_names()
sm   <- read_csv(sm_file, show_col_types = FALSE) %>% clean_names()

if (!file.exists(source_repository_file)) {
  stop(
    "The date source file was not found: ", source_repository_file,
    "\nUpdate source_repository_file before running the report."
  )
}

# Phase 1 tables are aggregated and do not retain the campaign date.  Restore
# it from the cleaned repository using the campaign/district key, then apply
# the same recent-month window consistently to every report input.
campaign_dates <- read_csv(source_repository_file, show_col_types = FALSE) %>%
  clean_names() %>%
  transmute(
    country = as.character(country),
    province = as.character(province),
    district = as.character(district),
    response = as.character(response),
    round_number = as.character(round_number),
    campaign_start_date = suppressWarnings(ymd(round_start_date))
  ) %>%
  filter(!is.na(campaign_start_date)) %>%
  group_by(country, province, district, response, round_number) %>%
  summarise(campaign_start_date = max(campaign_start_date), .groups = "drop")

if (nrow(campaign_dates) == 0) {
  stop("No valid round_start_date values were found in source_repository_file.")
}

analysis_end_date <- if (is.null(analysis_end_date)) {
  max(campaign_dates$campaign_start_date)
} else {
  as.Date(analysis_end_date)
}

if (is.na(analysis_end_date)) {
  stop("analysis_end_date must be NULL or a valid Date.")
}

analysis_start_date <- analysis_end_date %m-% months(analysis_months) + days(1)
analysis_period_label <- glue(
  "Last {analysis_months} month{if_else(analysis_months == 1, '', 's')}: ",
  "{format(analysis_start_date, '%d %b %Y')} to {format(analysis_end_date, '%d %b %Y')}"
)

filter_to_analysis_period <- function(data, data_name) {
  dated_data <- data %>%
    mutate(
      across(c(country, province, district, response, round_number), as.character)
    ) %>%
    left_join(
      campaign_dates,
      by = c("country", "province", "district", "response", "round_number")
    )

  unmatched_rows <- sum(is.na(dated_data$campaign_start_date))
  if (unmatched_rows > 0) {
    warning(
      data_name, ": ", unmatched_rows,
      " row(s) could not be matched to a campaign start date and were excluded."
    )
  }

  dated_data %>%
    filter(between(campaign_start_date, analysis_start_date, analysis_end_date))
}

risk <- filter_to_analysis_period(risk, "Risk scoring")
root <- filter_to_analysis_period(root, "Root-cause analysis")
op   <- filter_to_analysis_period(op, "Operational-failure analysis")
sm   <- filter_to_analysis_period(sm, "Social-mobilisation analysis")

filter_to_country_scope <- function(data, data_name) {
  if (!length(target_countries)) return(data)
  data <- data[!is.na(data$country) & toupper(data$country) %in% toupper(target_countries), ]
  if (nrow(data) == 0) {
    stop(
      data_name, ": no rows remain after filtering to ", report_scope_label,
      ". Check the country name(s) against the loaded repository (spelling/case)."
    )
  }
  data
}

risk <- filter_to_country_scope(risk, "Risk scoring")
root <- filter_to_country_scope(root, "Root-cause analysis")
op   <- filter_to_country_scope(op, "Operational-failure analysis")
sm   <- filter_to_country_scope(sm, "Social-mobilisation analysis")

if (nrow(risk) == 0) {
  stop(
    "No risk-scoring data falls within the selected analysis period: ",
    analysis_period_label,
    ". Adjust analysis_months or analysis_end_date."
  )
}

# ============================================================
# PREPARE REGIONAL DATA
# ============================================================
risk_data <- risk %>%
  mutate(
    district_uid = paste(country, province, district, sep = " | ")
  )

root_data <- root %>%
  mutate(
    district_uid = paste(country, province, district, sep = " | ")
  )

op_data <- op %>%
  mutate(
    district_uid = paste(country, province, district, sep = " | ")
  )

sm_data <- sm %>%
  mutate(
    district_uid = paste(country, province, district, sep = " | ")
  )

if (nrow(risk_data) == 0) {
  stop("No regional data found in Phase 1 outputs.")
}

# ============================================================
# HELPER FUNCTIONS
# ============================================================
pct <- function(x, digits = 1) {
  percent(x, accuracy = 10^-digits)
}

safe_divide <- function(num, den) {
  ifelse(den > 0, num / den, NA_real_)
}

safe_sum <- function(x) {
  sum(x, na.rm = TRUE)
}

safe_mode <- function(x) {
  x <- x[!is.na(x) & x != ""]
  if (length(x) == 0) return(NA_character_)
  names(sort(table(x), decreasing = TRUE))[1]
}

# ============================================================
# EXECUTIVE REGIONAL SNAPSHOT
# ============================================================
executive_snapshot <- risk_data %>%
  summarise(
    scope = report_scope_label,
    analysis_period = analysis_period_label,
    analysis_start_date = analysis_start_date,
    analysis_end_date = analysis_end_date,
    countries = n_distinct(country),
    provinces = n_distinct(paste(country, province)),
    districts = n_distinct(district_uid),
    campaigns_rounds = n_distinct(paste(country, response, round_number)),
    total_hh_visited = safe_sum(number_of_hh_visited),
    total_u5_present = safe_sum(u5_present),
    total_u5_fm = safe_sum(u5_fm),
    total_missed_children = safe_sum(missed_child),
    regional_cv = safe_divide(total_u5_fm, total_u5_present),
    regional_missed_rate = safe_divide(total_missed_children, total_u5_present),
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    critical_risk_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
    moderate_risk_events = sum(district_risk_class == "Moderate risk", na.rm = TRUE),
    low_risk_events = sum(district_risk_class == "Low risk", na.rm = TRUE)
  ) %>%
  mutate(
    regional_cv_pct = pct(regional_cv),
    regional_missed_rate_pct = pct(regional_missed_rate),
    mean_awareness_rate_pct = pct(mean_awareness_rate)
  )

write_csv(executive_snapshot, file.path(table_dir, "01_AFRO_executive_snapshot.csv"))

# ============================================================
# MISSED CHILDREN ROOT CAUSE ANALYSIS
# ============================================================
root_cause_regional <- root_data %>%
  summarise(
    absent = safe_sum(absent),
    non_compliance = safe_sum(non_compliance),
    house_not_visited = safe_sum(house_not_visited),
    house_not_revisited = safe_sum(house_not_revisited),
    asleep = safe_sum(asleep),
    vaccinated_routine = safe_sum(vaccinated_routine),
    other = safe_sum(other)
  ) %>%
  pivot_longer(everything(), names_to = "root_cause", values_to = "missed_children") %>%
  mutate(
    root_cause = recode(
      root_cause,
      absent = "Absent",
      non_compliance = "Non-compliance",
      house_not_visited = "House not visited",
      house_not_revisited = "House not revisited",
      asleep = "Sleeping child",
      vaccinated_routine = "Vaccinated routine",
      other = "Other"
    ),
    share = safe_divide(missed_children, sum(missed_children, na.rm = TRUE))
  ) %>%
  arrange(desc(missed_children))

write_csv(root_cause_regional, file.path(table_dir, "02_AFRO_root_cause_regional.csv"))

root_cause_by_district <- root_data %>%
  group_by(country, province, district, district_uid) %>%
  summarise(
    total_missed = safe_sum(missed_child),
    absent = safe_sum(absent),
    non_compliance = safe_sum(non_compliance),
    house_not_visited = safe_sum(house_not_visited),
    house_not_revisited = safe_sum(house_not_revisited),
    asleep = safe_sum(asleep),
    vaccinated_routine = safe_sum(vaccinated_routine),
    other = safe_sum(other),
    .groups = "drop"
  ) %>%
  rowwise() %>%
  mutate(
    dominant_root_cause = names(which.max(c(
      "Absent" = absent,
      "Non-compliance" = non_compliance,
      "House not visited" = house_not_visited,
      "House not revisited" = house_not_revisited,
      "Sleeping child" = asleep,
      "Vaccinated routine" = vaccinated_routine,
      "Other" = other
    )))
  ) %>%
  ungroup() %>%
  arrange(desc(total_missed))

write_csv(root_cause_by_district, file.path(table_dir, "03_AFRO_root_cause_by_district.csv"))

# ============================================================
# OPERATIONAL FAILURE ANALYSIS
# ============================================================
operational_failure_regional <- op_data %>%
  group_by(country, province, district, district_uid, operational_failure_type) %>%
  summarise(
    events = n(),
    total_missed = safe_sum(missed_child),
    mean_missed_rate = mean(missed_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(total_missed))

write_csv(operational_failure_regional, file.path(table_dir, "04_AFRO_operational_failure_analysis.csv"))

top_not_visited <- risk_data %>%
  group_by(country, province, district, district_uid) %>%
  summarise(
    house_not_visited = safe_sum(house_not_visited),
    total_missed = safe_sum(missed_child),
    notvisited_share = safe_divide(house_not_visited, total_missed),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(house_not_visited)) %>%
  slice_head(n = 30)

top_not_revisited <- risk_data %>%
  group_by(country, province, district, district_uid) %>%
  summarise(
    house_not_revisited = safe_sum(house_not_revisited),
    total_missed = safe_sum(missed_child),
    notrevisited_share = safe_divide(house_not_revisited, total_missed),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(house_not_revisited)) %>%
  slice_head(n = 30)

write_csv(top_not_visited, file.path(table_dir, "05_AFRO_top_not_visited_districts.csv"))
write_csv(top_not_revisited, file.path(table_dir, "06_AFRO_top_not_revisited_districts.csv"))

# ============================================================
# SOCIAL MOBILISATION EFFECTIVENESS ANALYSIS
# ============================================================
sm_summary_regional <- sm_data %>%
  group_by(country, province, district, district_uid) %>%
  summarise(
    hh_visited = safe_sum(number_of_hh_visited),
    u5_present = safe_sum(u5_present),
    u5_fm = safe_sum(u5_fm),
    missed_child = safe_sum(missed_child),
    non_compliance = safe_sum(non_compliance),
    informed_hh = safe_sum(care_giver_informed_sia),
    sm_sources = safe_sum(sm_total_sources),
    cv = safe_divide(u5_fm, u5_present),
    missed_rate = safe_divide(missed_child, u5_present),
    nc_rate = safe_divide(non_compliance, u5_present),
    awareness_rate = safe_divide(informed_hh, hh_visited),
    sm_density = safe_divide(sm_sources, hh_visited),
    mean_sm_effectiveness_score = mean(sm_effectiveness_score, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    sm_gap_class = case_when(
      awareness_rate < 0.50 ~ "Severe SM awareness gap",
      awareness_rate < 0.80 ~ "Moderate SM awareness gap",
      TRUE ~ "Acceptable awareness"
    )
  ) %>%
  arrange(awareness_rate)

write_csv(sm_summary_regional, file.path(table_dir, "07_AFRO_social_mobilisation_summary.csv"))

top_sm_gap_districts <- sm_summary_regional %>%
  arrange(awareness_rate, desc(missed_child)) %>%
  slice_head(n = 30)

write_csv(top_sm_gap_districts, file.path(table_dir, "08_AFRO_top_SM_gap_districts.csv"))

# ============================================================
# DISTRICT RISK PRIORITIZATION
# ============================================================
priority_districts_regional <- risk_data %>%
  group_by(country, province, district, district_uid) %>%
  summarise(
    observations = n(),
    total_u5_present = safe_sum(u5_present),
    total_missed = safe_sum(missed_child),
    mean_cv = mean(cv, na.rm = TRUE),
    mean_missed_rate = mean(missed_rate, na.rm = TRUE),
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    max_risk_score = max(district_risk_score, na.rm = TRUE),
    critical_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
    main_root_cause = safe_mode(main_root_cause),
    main_operational_failure = safe_mode(operational_failure_type),
    .groups = "drop"
  ) %>%
  mutate(
    priority_class = case_when(
      critical_events >= 1 | mean_risk_score >= 75 ~ "Priority 1 - Immediate action",
      high_risk_events >= 1 | mean_risk_score >= 50 ~ "Priority 2 - Intensified support",
      mean_risk_score >= 25 ~ "Priority 3 - Close monitoring",
      TRUE ~ "Routine monitoring"
    ),
    advocacy_message = case_when(
      main_root_cause == "Non-compliance" ~
        "Community engagement and refusal conversion should be prioritized.",
      main_root_cause == "House not visited" ~
        "Team deployment, settlement tracking and access supervision should be strengthened.",
      main_root_cause == "House not revisited" ~
        "Revisit tracking and supervisor accountability should be reinforced.",
      mean_awareness_rate < 0.80 ~
        "Pre-campaign social mobilisation and household awareness should be intensified.",
      TRUE ~
        "Continue routine monitoring and rapid corrective action."
    )
  ) %>%
  arrange(priority_class, desc(mean_risk_score), desc(total_missed))

write_csv(priority_districts_regional, file.path(table_dir, "09_AFRO_priority_districts_for_advocacy.csv"))

top_30_priority <- priority_districts_regional %>% slice_head(n = 30)

write_csv(top_30_priority, file.path(table_dir, "10_AFRO_top_30_priority_districts.csv"))

# ============================================================
# COUNTRY AND PROVINCE SUMMARIES
# ============================================================
country_summary_regional <- risk_data %>%
  group_by(country) %>%
  summarise(
    provinces = n_distinct(province),
    districts = n_distinct(district_uid),
    total_hh_visited = safe_sum(number_of_hh_visited),
    total_u5_present = safe_sum(u5_present),
    total_u5_fm = safe_sum(u5_fm),
    total_missed = safe_sum(missed_child),
    mean_cv = safe_divide(total_u5_fm, total_u5_present),
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    critical_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_risk_score), desc(total_missed))

province_summary_regional <- risk_data %>%
  group_by(country, province) %>%
  summarise(
    districts = n_distinct(district_uid),
    total_hh_visited = safe_sum(number_of_hh_visited),
    total_u5_present = safe_sum(u5_present),
    total_u5_fm = safe_sum(u5_fm),
    total_missed = safe_sum(missed_child),
    mean_cv = safe_divide(total_u5_fm, total_u5_present),
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    critical_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_risk_score), desc(total_missed))

write_csv(country_summary_regional, file.path(table_dir, "11_AFRO_country_summary.csv"))
write_csv(province_summary_regional, file.path(table_dir, "12_AFRO_province_summary.csv"))

# ============================================================
# ADVOCACY RECOMMENDATIONS
# ============================================================
advocacy_recommendations <- tibble(
  priority_area = c(
    "Regional high-risk countries and districts",
    "Missed children root causes",
    "Social mobilisation gaps",
    "Operational failures",
    "Revisit and supervision",
    "Data-driven accountability"
  ),
  finding = c(
    "Some countries and districts require intensified support based on recurrent high-risk profiles.",
    "Missed children are concentrated around specific operational and behavioural causes.",
    "Several districts show weak caregiver awareness or incomplete SM source attribution.",
    "Households not visited and not revisited indicate microplanning and supervision weaknesses.",
    "Revisit failure should be treated as a key accountability indicator.",
    "District-level risk scoring can support prioritization before and during campaigns."
  ),
  recommended_action = c(
    "Agree on priority countries and districts for immediate corrective action.",
    "Use root cause profiles to tailor district-specific interventions.",
    "Strengthen pre-campaign communication, community leader engagement and H2H mobilisation.",
    "Review team deployment, settlement lists, daily tracking and end-process monitoring.",
    "Institutionalize revisit tracking with supervisor-level accountability.",
    "Use IM intelligence dashboard before every campaign round."
  )
)

write_csv(advocacy_recommendations, file.path(table_dir, "13_AFRO_advocacy_recommendations.csv"))

# ============================================================
# PREMIUM UN / WHO ADVOCACY VISUALS
# ============================================================
who_blue       <- "#0093D5"
dark_blue      <- "#003A70"
alert_red      <- "#C00000"
warning_orange <- "#F28C28"
soft_grey      <- "#F5F7FA"
dark_grey      <- "#3A3A3A"
green_ok       <- "#8CC63E"
purple_alert   <- "#7A1FA2"

theme_un_advocacy <- function(base_size = 15) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = base_size + 5, color = dark_blue),
      plot.subtitle = element_text(size = base_size, color = dark_grey),
      plot.caption = element_text(size = base_size - 3, color = "grey40"),
      axis.title = element_text(face = "bold", color = dark_grey),
      axis.text = element_text(color = dark_grey),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(color = "grey88"),
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      legend.position = "bottom",
      legend.title = element_blank()
    )
}

# ============================================================
# VISUAL 0: EXECUTIVE KPI CARD
# ============================================================
kpi <- executive_snapshot

kpi_card <- ggplot() +
  annotate("rect", xmin = 0, xmax = 16, ymin = 0, ymax = 10, fill = soft_grey, color = NA) +
  annotate("rect", xmin = 0, xmax = 16, ymin = 8.65, ymax = 10, fill = dark_blue, color = NA) +
  annotate("text", x = 0.8, y = 9.4, hjust = 0,
           label = if (length(target_countries)) toupper(paste0(report_scope_label, " - INDEPENDENT MONITORING INTELLIGENCE"))
                   else "AFRO REGIONAL INDEPENDENT MONITORING INTELLIGENCE",
           size = 7, fontface = "bold", color = "white") +
  annotate("text", x = 0.8, y = 8.9, hjust = 0,
           label = glue("Generated: {format(Sys.Date(), '%d %b %Y')}  |  {kpi$analysis_period}"),
           size = 3.6, color = "white") +
  # Top row: operational reach, outcome and missed-child burden
  annotate("rect", xmin = 0.5, xmax = 5.1, ymin = 6.85, ymax = 8.3, fill = "white", color = who_blue, linewidth = 1.1) +
  annotate("rect", xmin = 5.7, xmax = 10.3, ymin = 6.85, ymax = 8.3, fill = "white", color = who_blue, linewidth = 1.1) +
  annotate("rect", xmin = 10.9, xmax = 15.5, ymin = 6.85, ymax = 8.3, fill = "white", color = alert_red, linewidth = 1.1) +
  annotate("text", x = 2.8, y = 7.75, label = comma(kpi$total_hh_visited), size = 10, fontface = "bold", color = who_blue) +
  annotate("text", x = 2.8, y = 7.3, label = "Households visited", size = 4.2, fontface = "bold", color = dark_grey) +
  annotate("text", x = 8.0, y = 7.75, label = kpi$regional_cv_pct, size = 10, fontface = "bold", color = who_blue) +
  annotate("text", x = 8.0, y = 7.3, label = "Regional coverage", size = 4.2, fontface = "bold", color = dark_grey) +
  annotate("text", x = 13.2, y = 7.75, label = comma(kpi$total_missed_children), size = 10, fontface = "bold", color = alert_red) +
  annotate("text", x = 13.2, y = 7.3, label = "Missed children", size = 4.2, fontface = "bold", color = dark_grey) +
  # Bottom row: mobilisation, risk and campaign reach
  annotate("rect", xmin = 0.5, xmax = 5.1, ymin = 4.7, ymax = 6.15, fill = "white", color = "#F2B600", linewidth = 1.1) +
  annotate("rect", xmin = 5.7, xmax = 10.3, ymin = 4.7, ymax = 6.15, fill = "white", color = alert_red, linewidth = 1.1) +
  annotate("rect", xmin = 10.9, xmax = 15.5, ymin = 4.7, ymax = 6.15, fill = "white", color = dark_blue, linewidth = 1.1) +
  annotate("text", x = 2.8, y = 5.6, label = kpi$mean_awareness_rate_pct, size = 10, fontface = "bold", color = "#F2B600") +
  annotate("text", x = 2.8, y = 5.15, label = "Caregiver awareness", size = 4.2, fontface = "bold", color = dark_grey) +
  annotate("text", x = 8.0, y = 5.6, label = round(kpi$mean_risk_score, 1), size = 10, fontface = "bold", color = alert_red) +
  annotate("text", x = 8.0, y = 5.15, label = "Mean risk score", size = 4.2, fontface = "bold", color = dark_grey) +
  annotate("text", x = 13.2, y = 5.6, label = kpi$campaigns_rounds, size = 10, fontface = "bold", color = dark_blue) +
  annotate("text", x = 13.2, y = 5.15, label = "Campaign rounds", size = 4.2, fontface = "bold", color = dark_grey) +
  annotate("text", x = 0.8, y = 3.55, hjust = 0,
           label = glue("Countries analysed: {kpi$countries}  |  Districts analysed: {kpi$districts}"),
           size = 4.4, fontface = "bold", color = dark_blue) +
  annotate("text", x = 0.8, y = 3.0, hjust = 0,
           label = glue("Critical events: {kpi$critical_risk_events}  |  High-risk events: {kpi$high_risk_events}  |  Moderate-risk events: {kpi$moderate_risk_events}"),
           size = 3.6, color = dark_grey) +
  annotate("text", x = 0.8, y = 0.65, hjust = 0,
           label = "Source: AFRO Independent Monitoring repository | District uniqueness: Country + Province + District",
           size = 3.1, color = "grey40") +
  xlim(0, 16) +
  ylim(0, 10) +
  theme_void()

ggsave(file.path(plot_dir, "00_AFRO_executive_KPI_card.png"), kpi_card, width = 16, height = 10, dpi = 300)

# ============================================================
# VISUAL 1: ROOT CAUSES
# ============================================================
p1 <- root_cause_regional %>%
  mutate(
    root_cause = fct_reorder(root_cause, missed_children),
    label = paste0(comma(missed_children), " (", percent(share, accuracy = 0.1), ")"),
    fill_group = ifelse(
      root_cause %in% c("Non-compliance", "House not visited", "House not revisited"),
      "Priority operational/behavioral issue",
      "Other missed-child driver"
    )
  ) %>%
  ggplot(aes(x = root_cause, y = missed_children, fill = fill_group)) +
  geom_col(width = 0.72) +
  geom_text(aes(label = label), hjust = -0.08, size = 4.4, fontface = "bold", color = dark_grey) +
  coord_flip() +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.18))) +
  scale_fill_manual(values = c(
    "Priority operational/behavioral issue" = alert_red,
    "Other missed-child driver" = who_blue
  )) +
  labs(
    title = "Why children are missed across AFRO countries",
    subtitle = "Root-cause decomposition from Independent Monitoring",
    x = NULL,
    y = "Missed children",
    caption = "Advocacy use: tailor corrective action by dominant cause"
  ) +
  theme_un_advocacy()

ggsave(file.path(plot_dir, "01_AFRO_root_causes_missed_children_EXECUTIVE.png"), p1, width = 13, height = 8, dpi = 300)

# ============================================================
# VISUAL 2: TOP PRIORITY DISTRICTS
# ============================================================
p2 <- top_30_priority %>%
  mutate(
    label = str_wrap(district_uid, width = 34),
    priority_simple = case_when(
      str_detect(priority_class, "Priority 1") ~ "Priority 1",
      str_detect(priority_class, "Priority 2") ~ "Priority 2",
      TRUE ~ "Priority 3"
    )
  ) %>%
  ggplot(aes(x = reorder(label, mean_risk_score), y = mean_risk_score, fill = priority_simple)) +
  geom_col(width = 0.72) +
  geom_text(aes(label = round(mean_risk_score, 1)), hjust = -0.15,
            size = 3.8, fontface = "bold", color = dark_grey) +
  coord_flip() +
  scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
  scale_fill_manual(values = c(
    "Priority 1" = alert_red,
    "Priority 2" = warning_orange,
    "Priority 3" = who_blue
  )) +
  labs(
    title = "Priority districts requiring regional action",
    subtitle = "Ranked by IM risk score and operational vulnerability",
    x = NULL,
    y = "Mean risk score",
    caption = "Use this list for AFRO prioritization, partner support and accountability tracking"
  ) +
  theme_un_advocacy(base_size = 13)

ggsave(file.path(plot_dir, "02_AFRO_top_priority_districts_EXECUTIVE.png"), p2, width = 14, height = 10, dpi = 300)

# ============================================================
# VISUAL 3: COUNTRY RISK PROFILE
# ============================================================
p3 <- country_summary_regional %>%
  mutate(
    country = fct_reorder(country, mean_risk_score),
    risk_group = case_when(
      mean_risk_score >= 75 ~ "Critical",
      mean_risk_score >= 50 ~ "High",
      mean_risk_score >= 25 ~ "Moderate",
      TRUE ~ "Low"
    )
  ) %>%
  ggplot(aes(x = country, y = mean_risk_score, fill = risk_group)) +
  geom_col(width = 0.72) +
  geom_text(aes(label = paste0("Missed: ", comma(total_missed))),
            hjust = -0.05, size = 4, fontface = "bold", color = dark_grey) +
  coord_flip() +
  scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
  scale_fill_manual(values = c(
    "Critical" = alert_red,
    "High" = warning_orange,
    "Moderate" = who_blue,
    "Low" = green_ok
  )) +
  labs(
    title = "Country-level IM risk profile",
    subtitle = "Risk score with missed-child burden for regional targeting",
    x = NULL,
    y = "Mean risk score",
    caption = "Focus countries with both high risk score and high missed-child burden"
  ) +
  theme_un_advocacy()

ggsave(file.path(plot_dir, "03_AFRO_country_risk_profile_EXECUTIVE.png"), p3, width = 13, height = 8, dpi = 300)

# ============================================================
# VISUAL 4: SM AWARENESS VS COVERAGE
# ============================================================
p4 <- sm_summary_regional %>%
  mutate(
    quadrant = case_when(
      awareness_rate < 0.80 & cv < 0.90 ~ "Low awareness + low coverage",
      awareness_rate < 0.80 & cv >= 0.90 ~ "Low awareness but acceptable coverage",
      awareness_rate >= 0.80 & cv < 0.90 ~ "High awareness but low coverage",
      TRUE ~ "High awareness + good coverage"
    )
  ) %>%
  ggplot(aes(x = awareness_rate, y = cv, size = missed_child, fill = quadrant)) +
  geom_hline(yintercept = 0.90, linetype = "dashed", color = "grey45") +
  geom_vline(xintercept = 0.80, linetype = "dashed", color = "grey45") +
  geom_point(shape = 21, alpha = 0.75, color = "white", stroke = 0.5) +
  scale_x_continuous(labels = percent_format(), limits = c(0, 1)) +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
  scale_size_continuous(range = c(2, 10), labels = comma) +
  scale_fill_manual(values = c(
    "Low awareness + low coverage" = alert_red,
    "Low awareness but acceptable coverage" = warning_orange,
    "High awareness but low coverage" = purple_alert,
    "High awareness + good coverage" = who_blue
  )) +
  labs(
    title = "Social mobilisation awareness vs vaccination coverage",
    subtitle = "Each bubble is a unique district; bubble size reflects missed children",
    x = "Caregiver awareness rate",
    y = "Vaccination coverage",
    caption = "Advocacy message: low-awareness districts require intensified pre-campaign mobilisation"
  ) +
  theme_un_advocacy()

ggsave(file.path(plot_dir, "04_AFRO_SM_awareness_vs_coverage_EXECUTIVE.png"), p4, width = 12, height = 8, dpi = 300)

# ============================================================
# VISUAL 5: OPERATIONAL FAILURE PROFILE
# ============================================================
p5 <- operational_failure_regional %>%
  group_by(operational_failure_type) %>%
  summarise(total_missed = safe_sum(total_missed), .groups = "drop") %>%
  arrange(desc(total_missed)) %>%
  mutate(
    operational_failure_type = str_wrap(operational_failure_type, width = 34),
    operational_failure_type = fct_reorder(operational_failure_type, total_missed)
  ) %>%
  ggplot(aes(x = operational_failure_type, y = total_missed)) +
  geom_col(fill = dark_blue, width = 0.72) +
  geom_text(aes(label = comma(total_missed)), hjust = -0.08,
            size = 4.5, fontface = "bold", color = dark_grey) +
  coord_flip() +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.2))) +
  labs(
    title = "Operational failure profile",
    subtitle = "Missed children linked to supervision, access, timing and refusal patterns",
    x = NULL,
    y = "Missed children",
    caption = "Use for regional discussion on team deployment, revisit tracking and supervision accountability"
  ) +
  theme_un_advocacy()

ggsave(file.path(plot_dir, "05_AFRO_operational_failure_profile_EXECUTIVE.png"), p5, width = 13, height = 8, dpi = 300)

# ============================================================
# VISUAL 6: ADVOCACY RECOMMENDATION CARD
# ============================================================
recommendation_card <- ggplot() +
  annotate("rect", xmin = 0, xmax = 10, ymin = 0, ymax = 7, fill = "white", color = NA) +
  annotate("rect", xmin = 0, xmax = 10, ymin = 6.1, ymax = 7, fill = dark_blue, color = NA) +
  annotate("text", x = 0.4, y = 6.55, hjust = 0,
           label = "Priority regional advocacy actions",
           color = "white", size = 7, fontface = "bold") +
  annotate("text", x = 0.6, y = 5.3, hjust = 0,
           label = "1. Prioritize high-risk countries and districts for immediate corrective action",
           color = dark_blue, size = 4.8, fontface = "bold") +
  annotate("text", x = 0.9, y = 4.8, hjust = 0,
           label = "Use IM risk ranking to focus supervision, partner support and rapid action.",
           color = dark_grey, size = 4.1) +
  annotate("text", x = 0.6, y = 4.0, hjust = 0,
           label = "2. Strengthen revisit tracking and supervisor accountability",
           color = dark_blue, size = 4.8, fontface = "bold") +
  annotate("text", x = 0.9, y = 3.5, hjust = 0,
           label = "House not revisited should become a campaign accountability indicator.",
           color = dark_grey, size = 4.1) +
  annotate("text", x = 0.6, y = 2.7, hjust = 0,
           label = "3. Intensify social mobilisation in low-awareness districts",
           color = dark_blue, size = 4.8, fontface = "bold") +
  annotate("text", x = 0.9, y = 2.2, hjust = 0,
           label = "Scale up community leaders, religious leaders, H2H mobilisation and local channels.",
           color = dark_grey, size = 4.1) +
  annotate("text", x = 0.6, y = 1.4, hjust = 0,
           label = "4. Institutionalize IM intelligence before and during each round",
           color = dark_blue, size = 4.8, fontface = "bold") +
  annotate("text", x = 0.9, y = 0.9, hjust = 0,
           label = "Use district-level risk profiles to guide microplanning and corrective action.",
           color = dark_grey, size = 4.1) +
  xlim(0, 10) +
  ylim(0, 7) +
  theme_void()

ggsave(file.path(plot_dir, "06_AFRO_advocacy_recommendation_card.png"), recommendation_card, width = 14, height = 8, dpi = 300)

# ============================================================
# EXCEL WORKBOOK
# ============================================================
wb <- createWorkbook()

sheet_list <- list(
  "Executive Snapshot" = executive_snapshot,
  "Root Cause Regional" = root_cause_regional,
  "Root Cause District" = root_cause_by_district,
  "Operational Failure" = operational_failure_regional,
  "Top Not Visited" = top_not_visited,
  "Top Not Revisited" = top_not_revisited,
  "SM Summary" = sm_summary_regional,
  "SM Gap Districts" = top_sm_gap_districts,
  "Priority Districts" = priority_districts_regional,
  "Top 30 Priority" = top_30_priority,
  "Country Summary" = country_summary_regional,
  "Province Summary" = province_summary_regional,
  "Recommendations" = advocacy_recommendations
)

for (sheet_name in names(sheet_list)) {
  addWorksheet(wb, sheet_name)
  writeData(wb, sheet_name, sheet_list[[sheet_name]])
  freezePane(wb, sheet_name, firstRow = TRUE)
}

saveWorkbook(
  wb,
  file.path(output_dir, "AFRO_Regional_IM_Intelligence_Report.xlsx"),
  overwrite = TRUE
)

# ============================================================
# WORD EXECUTIVE BRIEF
# ============================================================
brief <- read_docx()

brief <- brief %>%
  body_add_par("AFRO Regional Independent Monitoring Intelligence Brief", style = "heading 1") %>%
  body_add_par(
    glue(
      "Prepared for regional programme intelligence and advocacy. {analysis_period_label}. ",
      "District counts are based on unique Country + Province + District combinations."
    ),
    style = "Normal"
  ) %>%
  body_add_par("1. Executive Snapshot", style = "heading 2") %>%
  body_add_flextable(flextable(executive_snapshot) %>% autofit()) %>%
  body_add_par("2. Top Priority Districts", style = "heading 2") %>%
  body_add_flextable(flextable(top_30_priority) %>% autofit()) %>%
  body_add_par("3. Country Summary", style = "heading 2") %>%
  body_add_flextable(flextable(country_summary_regional) %>% autofit()) %>%
  body_add_par("4. Key Advocacy Recommendations", style = "heading 2") %>%
  body_add_flextable(flextable(advocacy_recommendations) %>% autofit())

print(
  brief,
  target = file.path(output_dir, "AFRO_Regional_IM_Intelligence_Brief.docx")
)

# ============================================================
# FINAL SUMMARY
# ============================================================
message("============================================================")
message("AFRO REGIONAL IM INTELLIGENCE REPORT COMPLETED")
message("Output folder: ", output_dir)
message("Analysis period: ", analysis_period_label)
message("Excel: AFRO_Regional_IM_Intelligence_Report.xlsx")
message("Word brief: AFRO_Regional_IM_Intelligence_Brief.docx")
message("Plots saved in: ", plot_dir)
message("Tables saved in: ", table_dir)
message("============================================================")

message("Countries analysed: ", n_distinct(risk_data$country))
message("Unique districts analysed: ", n_distinct(risk_data$district_uid))
message("Total missed children: ", comma(executive_snapshot$total_missed_children))
message("Regional CV: ", executive_snapshot$regional_cv_pct)
message("Top priority districts exported: ", nrow(top_30_priority))
