# ============================================================
# AFRO REGIONAL IM INTELLIGENCE REPORT
# Purpose: Regional Independent Monitoring intelligence analysis
# Input: Regional_IM_repository_cleaned outputs from IM workflow
# Outputs: Excel, Word brief, CSV tables, premium PNG visuals
# District uniqueness: country + province + district
# ============================================================

pacman::p_load(
  tidyverse, lubridate, readr, openxlsx, janitor,
  scales, glue, flextable, officer, ggplot2,
  patchwork, cowplot, stringr, forcats, arrow
)

# ============================================================
# PATHS - CONNECTED TO IM WORKFLOW
# ============================================================

# Main IM workflow directory
workflow_dir <- "C:/Users/TOURE/Documents/im_workflow"

# Input: Cleaned regional repository from IM workflow
input_dir <- file.path(workflow_dir, "data/final")
cleaned_data_file <- file.path(input_dir, "Regional_IM_repository_cleaned.rds")

# Alternative input if RDS not available
cleaned_data_csv <- file.path(input_dir, "Regional_IM_repository_cleaned.csv")

# Output directories for intelligence report
output_dir <- file.path(workflow_dir, "outputs/reports/IM_Intelligence_Report")
plot_dir   <- file.path(output_dir, "plots")
table_dir  <- file.path(output_dir, "tables")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

# ============================================================
# LOAD CLEANED IM DATA FROM WORKFLOW
# ============================================================

cat("Loading cleaned IM data from workflow...\n")

if (file.exists(cleaned_data_file)) {
  im_data <- readRDS(cleaned_data_file)
  cat("Loaded RDS file:", cleaned_data_file, "\n")
} else if (file.exists(cleaned_data_csv)) {
  im_data <- read_csv(cleaned_data_csv, show_col_types = FALSE)
  cat("Loaded CSV file:", cleaned_data_csv, "\n")
} else {
  stop("No cleaned IM data found. Please run the IM workflow first.")
}

cat("Data loaded:", nrow(im_data), "rows,", ncol(im_data), "columns\n")

# ============================================================
# PREPARE REGIONAL DATA FROM CLEANED REPOSITORY
# ============================================================

# Convert column names to lowercase for consistency
names(im_data) <- tolower(names(im_data))

# First, create district_uid and calculate derived columns
risk_data <- im_data %>%
  mutate(
    district_uid = paste(country, province, district, sep = " | "),
    
    # Calculate derived indicators
    missed_child = if ("missed_child" %in% names(.)) missed_child else u5_present - u5_fm,
    missed_rate = missed_child / u5_present,
    cv = u5_fm / u5_present,
    
    # Awareness rate
    awareness_rate = case_when(
      "care_giver_informed_sia" %in% names(.) & "number_of_hh_visited" %in% names(.) ~ 
        care_giver_informed_sia / number_of_hh_visited,
      TRUE ~ NA_real_
    ),
    
    # Risk score calculation
    district_risk_score = case_when(
      cv < 0.80 ~ 60,
      cv < 0.90 ~ 40,
      cv >= 0.90 ~ 20,
      TRUE ~ 50
    ) + case_when(
      missed_rate > 0.20 ~ 30,
      missed_rate > 0.10 ~ 15,
      TRUE ~ 0
    ) + case_when(
      awareness_rate < 0.50 ~ 20,
      awareness_rate < 0.80 ~ 10,
      TRUE ~ 0
    ),
    
    district_risk_class = case_when(
      district_risk_score >= 70 ~ "Critical risk",
      district_risk_score >= 50 ~ "High risk",
      district_risk_score >= 30 ~ "Moderate risk",
      TRUE ~ "Low risk"
    )
  )

# ============================================================
# ROOT CAUSE ANALYSIS FROM AVAILABLE DATA
# ============================================================

# Identify available root cause columns
root_cause_cols <- intersect(
  c("r_non_fm_absent", "r_non_fm_nc", "r_non_fm_hh_notvisited",
    "r_non_fm_hh_notrevisited", "r_non_fm_sleep", "r_non_fm_vaccinatedroutine",
    "r_non_fm_other", "r_non_fm_vaccinated_but_not_fm", 
    "r_non_fm_child_is_a_visitor", "r_non_fm_childnotborn", "r_non_fm_security"),
  names(im_data)
)

if (length(root_cause_cols) > 0) {
  root_data <- im_data %>%
    group_by(country, province, district, response, roundnumber) %>%
    summarise(
      missed_child = sum(missed_child, na.rm = TRUE),
      across(all_of(root_cause_cols), ~ sum(.x, na.rm = TRUE)),
      .groups = "drop"
    ) %>%
    mutate(
      district_uid = paste(country, province, district, sep = " | "),
      absent = if ("r_non_fm_absent" %in% names(.)) r_non_fm_absent else 0,
      non_compliance = if ("r_non_fm_nc" %in% names(.)) r_non_fm_nc else 0,
      house_not_visited = if ("r_non_fm_hh_notvisited" %in% names(.)) r_non_fm_hh_notvisited else 0,
      house_not_revisited = if ("r_non_fm_hh_notrevisited" %in% names(.)) r_non_fm_hh_notrevisited else 0,
      asleep = if ("r_non_fm_sleep" %in% names(.)) r_non_fm_sleep else 0,
      vaccinated_routine = if ("r_non_fm_vaccinatedroutine" %in% names(.)) r_non_fm_vaccinatedroutine else 0,
      other = if ("r_non_fm_other" %in% names(.)) r_non_fm_other else 0
    )
} else {
  # Create data frame if no root cause columns
  root_data <- im_data %>%
    group_by(country, province, district, response, roundnumber) %>%
    summarise(
      missed_child = sum(missed_child, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      district_uid = paste(country, province, district, sep = " | "),
      absent = 0, non_compliance = 0, house_not_visited = 0,
      house_not_revisited = 0, asleep = 0, vaccinated_routine = 0, other = 0
    )
}

# ============================================================
# SOCIAL MOBILISATION ANALYSIS
# ============================================================

sm_data <- im_data %>%
  group_by(country, province, district, response, roundnumber) %>%
  summarise(
    number_of_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
    u5_present = sum(u5_present, na.rm = TRUE),
    u5_fm = sum(u5_fm, na.rm = TRUE),
    missed_child = sum(missed_child, na.rm = TRUE),
    non_compliance = sum(if("r_non_fm_nc" %in% names(im_data)) r_non_fm_nc else 0, na.rm = TRUE),
    informed_hh = sum(if("care_giver_informed_sia" %in% names(im_data)) care_giver_informed_sia else 0, na.rm = TRUE),
    sm_sources = sum(if("sm_total_sources" %in% names(im_data)) sm_total_sources else 0, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    district_uid = paste(country, province, district, sep = " | "),
    cv = if_else(u5_present > 0, u5_fm / u5_present, NA_real_),
    missed_rate = if_else(u5_present > 0, missed_child / u5_present, NA_real_),
    nc_rate = if_else(u5_present > 0, non_compliance / u5_present, NA_real_),
    awareness_rate = if_else(number_of_hh_visited > 0, informed_hh / number_of_hh_visited, 0),
    sm_density = if_else(number_of_hh_visited > 0, sm_sources / number_of_hh_visited, 0),
    sm_effectiveness_score = awareness_rate * cv * 100,
    sm_gap_class = case_when(
      awareness_rate < 0.50 ~ "Severe SM awareness gap",
      awareness_rate < 0.80 ~ "Moderate SM awareness gap",
      TRUE ~ "Acceptable awareness"
    )
  )

# ============================================================
# EXECUTIVE REGIONAL SNAPSHOT
# ============================================================

executive_snapshot <- risk_data %>%
  summarise(
    scope = "AFRO Regional",
    countries = n_distinct(country),
    provinces = n_distinct(paste(country, province)),
    districts = n_distinct(district_uid),
    campaigns_rounds = n_distinct(paste(country, response, roundnumber)),
    total_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
    total_u5_present = sum(u5_present, na.rm = TRUE),
    total_u5_fm = sum(u5_fm, na.rm = TRUE),
    total_missed_children = sum(missed_child, na.rm = TRUE),
    regional_cv = total_u5_fm / total_u5_present,
    regional_missed_rate = total_missed_children / total_u5_present,
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    critical_risk_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
    moderate_risk_events = sum(district_risk_class == "Moderate risk", na.rm = TRUE),
    low_risk_events = sum(district_risk_class == "Low risk", na.rm = TRUE)
  ) %>%
  mutate(
    regional_cv_pct = scales::percent(regional_cv, accuracy = 0.1),
    regional_missed_rate_pct = scales::percent(regional_missed_rate, accuracy = 0.1),
    mean_awareness_rate_pct = scales::percent(mean_awareness_rate, accuracy = 0.1)
  )

write_csv(executive_snapshot, file.path(table_dir, "01_AFRO_executive_snapshot.csv"))

# ============================================================
# MISSED CHILDREN ROOT CAUSE ANALYSIS
# ============================================================

root_cause_regional <- root_data %>%
  summarise(
    absent = sum(absent, na.rm = TRUE),
    non_compliance = sum(non_compliance, na.rm = TRUE),
    house_not_visited = sum(house_not_visited, na.rm = TRUE),
    house_not_revisited = sum(house_not_revisited, na.rm = TRUE),
    asleep = sum(asleep, na.rm = TRUE),
    vaccinated_routine = sum(vaccinated_routine, na.rm = TRUE),
    other = sum(other, na.rm = TRUE)
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
    share = missed_children / sum(missed_children, na.rm = TRUE)
  ) %>%
  arrange(desc(missed_children))

write_csv(root_cause_regional, file.path(table_dir, "02_AFRO_root_cause_regional.csv"))

root_cause_by_district <- root_data %>%
  group_by(country, province, district, district_uid) %>%
  summarise(
    total_missed = sum(missed_child, na.rm = TRUE),
    absent = sum(absent, na.rm = TRUE),
    non_compliance = sum(non_compliance, na.rm = TRUE),
    house_not_visited = sum(house_not_visited, na.rm = TRUE),
    house_not_revisited = sum(house_not_revisited, na.rm = TRUE),
    asleep = sum(asleep, na.rm = TRUE),
    vaccinated_routine = sum(vaccinated_routine, na.rm = TRUE),
    other = sum(other, na.rm = TRUE),
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
# SOCIAL MOBILISATION EFFECTIVENESS ANALYSIS
# ============================================================

sm_summary_regional <- sm_data %>%
  arrange(awareness_rate)

write_csv(sm_summary_regional, file.path(table_dir, "04_AFRO_social_mobilisation_summary.csv"))

top_sm_gap_districts <- sm_summary_regional %>%
  arrange(awareness_rate, desc(missed_child)) %>%
  slice_head(n = 30)

write_csv(top_sm_gap_districts, file.path(table_dir, "05_AFRO_top_SM_gap_districts.csv"))

# ============================================================
# DISTRICT RISK PRIORITIZATION
# ============================================================

priority_districts_regional <- risk_data %>%
  group_by(country, province, district, district_uid) %>%
  summarise(
    observations = n(),
    total_u5_present = sum(u5_present, na.rm = TRUE),
    total_missed = sum(missed_child, na.rm = TRUE),
    mean_cv = mean(cv, na.rm = TRUE),
    mean_missed_rate = mean(missed_rate, na.rm = TRUE),
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    max_risk_score = max(district_risk_score, na.rm = TRUE),
    critical_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
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
      mean_awareness_rate < 0.80 ~
        "Pre-campaign social mobilisation and household awareness should be intensified.",
      TRUE ~
        "Continue routine monitoring and rapid corrective action."
    )
  ) %>%
  arrange(priority_class, desc(mean_risk_score), desc(total_missed))

write_csv(priority_districts_regional, file.path(table_dir, "06_AFRO_priority_districts_for_advocacy.csv"))

top_30_priority <- priority_districts_regional %>% slice_head(n = 30)
write_csv(top_30_priority, file.path(table_dir, "07_AFRO_top_30_priority_districts.csv"))

# ============================================================
# COUNTRY AND PROVINCE SUMMARIES
# ============================================================

country_summary_regional <- risk_data %>%
  group_by(country) %>%
  summarise(
    provinces = n_distinct(province),
    districts = n_distinct(district_uid),
    total_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
    total_u5_present = sum(u5_present, na.rm = TRUE),
    total_u5_fm = sum(u5_fm, na.rm = TRUE),
    total_missed = sum(missed_child, na.rm = TRUE),
    mean_cv = total_u5_fm / total_u5_present,
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
    total_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
    total_u5_present = sum(u5_present, na.rm = TRUE),
    total_u5_fm = sum(u5_fm, na.rm = TRUE),
    total_missed = sum(missed_child, na.rm = TRUE),
    mean_cv = total_u5_fm / total_u5_present,
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    critical_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_risk_score), desc(total_missed))

write_csv(country_summary_regional, file.path(table_dir, "08_AFRO_country_summary.csv"))
write_csv(province_summary_regional, file.path(table_dir, "09_AFRO_province_summary.csv"))

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

write_csv(advocacy_recommendations, file.path(table_dir, "10_AFRO_advocacy_recommendations.csv"))

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

theme_un_advocacy <- function(base_size = 15, legend_position = "bottom") {
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
      legend.position = legend_position,
      legend.title = element_blank(),
      legend.text = element_text(size = base_size - 4),
      legend.key.size = unit(0.6, "cm"),
      legend.spacing.y = unit(0.1, "cm"),
      legend.box = "vertical",
      plot.margin = margin(10, 15, 10, 10)
    )
}

# ============================================================
# VISUAL 0: EXECUTIVE KPI CARD (ENHANCED VERSION)
# ============================================================

kpi <- executive_snapshot

# Calculate additional metrics for the KPI card (using risk_data only)
additional_metrics <- risk_data %>%
  summarise(
    # Coverage trends
    districts_below_80 = sum(cv < 0.80, na.rm = TRUE),
    districts_above_90 = sum(cv >= 0.90, na.rm = TRUE),
    
    # Non-compliance burden (if available)
    total_non_compliance = if("r_non_fm_nc" %in% names(.)) sum(r_non_fm_nc, na.rm = TRUE) else 0,
    non_compliance_rate = if(sum(u5_present, na.rm = TRUE) > 0) total_non_compliance / sum(u5_present, na.rm = TRUE) else 0,
    
    # Absent children (if available)
    total_absent = if("r_non_fm_absent" %in% names(.)) sum(r_non_fm_absent, na.rm = TRUE) else 0,
    absent_rate = if(sum(u5_present, na.rm = TRUE) > 0) total_absent / sum(u5_present, na.rm = TRUE) else 0,
    
    # Fix for awareness rate - ensure no division by zero
    valid_awareness = if("awareness_rate" %in% names(.)) {
      rates <- awareness_rate[is.finite(awareness_rate) & !is.na(awareness_rate)]
      mean(rates, na.rm = TRUE)
    } else {
      NA_real_
    }
  )

# Use the calculated valid awareness rate or fallback to kpi value
awareness_value <- if(is.finite(additional_metrics$valid_awareness) & !is.na(additional_metrics$valid_awareness)) {
  scales::percent(additional_metrics$valid_awareness, accuracy = 0.1)
} else if(is.finite(kpi$mean_awareness_rate) & !is.na(kpi$mean_awareness_rate)) {
  kpi$mean_awareness_rate_pct
} else {
  "N/A"
}

# Build the KPI card step by step
kpi_card <- ggplot()

# Background
kpi_card <- kpi_card + annotate("rect", xmin = 0, xmax = 10, ymin = 0, ymax = 9, fill = soft_grey, color = NA)

# Header bar
kpi_card <- kpi_card + annotate("rect", xmin = 0, xmax = 10, ymin = 7.8, ymax = 9, fill = dark_blue, color = NA)

# Title
kpi_card <- kpi_card + annotate("text", x = 0.5, y = 8.4, hjust = 0,
                                label = "AFRO REGIONAL INDEPENDENT MONITORING INTELLIGENCE",
                                size = 6.5, fontface = "bold", color = "white")

# Subtitle
kpi_card <- kpi_card + annotate("text", x = 0.5, y = 7.95, hjust = 0,
                                label = glue("Data as of: {format(Sys.Date(), '%B %d, %Y')}"),
                                size = 3.8, color = "white", alpha = 0.8)

# ============================================================
# MAIN KPI ROW 1: COVERAGE & IMPACT
# ============================================================

# HH Visited (Left)
kpi_card <- kpi_card + annotate("rect", xmin = 0.3, xmax = 3.3, ymin = 6.2, ymax = 7.6, fill = "white", color = who_blue, size = 1.5, alpha = 0.9)
kpi_card <- kpi_card + annotate("text", x = 1.8, y = 7.25, label = comma(kpi$total_hh_visited),
                                size = 10, fontface = "bold", color = who_blue)
kpi_card <- kpi_card + annotate("text", x = 1.8, y = 6.8, label = "Households Visited",
                                size = 4, fontface = "bold", color = dark_grey)

# Regional CV (Center)
kpi_card <- kpi_card + annotate("rect", xmin = 3.5, xmax = 6.5, ymin = 6.2, ymax = 7.6, fill = "white", color = who_blue, size = 1.5, alpha = 0.9)
kpi_card <- kpi_card + annotate("text", x = 5, y = 7.25, label = kpi$regional_cv_pct,
                                size = 11, fontface = "bold", color = who_blue)
kpi_card <- kpi_card + annotate("text", x = 5, y = 6.8, label = "Regional Coverage (CV)",
                                size = 4, fontface = "bold", color = dark_grey)
kpi_card <- kpi_card + annotate("text", x = 5, y = 6.45, label = glue("{comma(kpi$total_u5_fm)} / {comma(kpi$total_u5_present)} children"),
                                size = 3.2, color = dark_grey)

# Missed Children (Right)
kpi_card <- kpi_card + annotate("rect", xmin = 6.7, xmax = 9.7, ymin = 6.2, ymax = 7.6, fill = "white", color = alert_red, size = 1.5, alpha = 0.9)
kpi_card <- kpi_card + annotate("text", x = 8.2, y = 7.25, label = comma(kpi$total_missed_children),
                                size = 11, fontface = "bold", color = alert_red)
kpi_card <- kpi_card + annotate("text", x = 8.2, y = 6.8, label = "Missed Children",
                                size = 4, fontface = "bold", color = dark_grey)
kpi_card <- kpi_card + annotate("text", x = 8.2, y = 6.45, label = glue("{percent(kpi$regional_missed_rate, accuracy = 0.1)} of eligible"),
                                size = 3.2, color = dark_grey)

# ============================================================
# ROW 2: AWARENESS & RISK
# ============================================================

# Awareness Rate (with safe value)
kpi_card <- kpi_card + annotate("rect", xmin = 0.3, xmax = 3.3, ymin = 4.8, ymax = 6.0, fill = "white", color = warning_orange, size = 1.2)
kpi_card <- kpi_card + annotate("text", x = 1.8, y = 5.65, label = awareness_value,
                                size = 9, fontface = "bold", color = warning_orange)
kpi_card <- kpi_card + annotate("text", x = 1.8, y = 5.25, label = "Caregiver Awareness",
                                size = 3.8, fontface = "bold", color = dark_grey)
kpi_card <- kpi_card + annotate("text", x = 1.8, y = 4.95, label = glue("{comma(kpi$total_hh_visited)} households"),
                                size = 2.8, color = dark_grey)

# Risk Score
kpi_card <- kpi_card + annotate("rect", xmin = 3.5, xmax = 6.5, ymin = 4.8, ymax = 6.0, fill = "white", color = alert_red, size = 1.2)
kpi_card <- kpi_card + annotate("text", x = 5, y = 5.65, label = round(kpi$mean_risk_score, 1),
                                size = 9, fontface = "bold", color = alert_red)
kpi_card <- kpi_card + annotate("text", x = 5, y = 5.25, label = "Mean Risk Score",
                                size = 3.8, fontface = "bold", color = dark_grey)
kpi_card <- kpi_card + annotate("text", x = 5, y = 4.95, label = glue("{kpi$critical_risk_events} Critical | {kpi$high_risk_events} High"),
                                size = 2.8, color = dark_grey)

# Campaign Rounds
kpi_card <- kpi_card + annotate("rect", xmin = 6.7, xmax = 9.7, ymin = 4.8, ymax = 6.0, fill = "white", color = purple_alert, size = 1.2)
kpi_card <- kpi_card + annotate("text", x = 8.2, y = 5.65, label = kpi$campaigns_rounds,
                                size = 9, fontface = "bold", color = purple_alert)
kpi_card <- kpi_card + annotate("text", x = 8.2, y = 5.25, label = "Campaign Rounds",
                                size = 3.8, fontface = "bold", color = dark_grey)
kpi_card <- kpi_card + annotate("text", x = 8.2, y = 4.95, label = glue("{kpi$countries} countries | {kpi$districts} districts"),
                                size = 2.8, color = dark_grey)

# ============================================================
# ROW 3: ADDITIONAL INSIGHTS
# ============================================================

# Coverage Distribution
kpi_card <- kpi_card + annotate("rect", xmin = 0.3, xmax = 4.8, ymin = 3.4, ymax = 4.6, fill = "white", color = dark_blue, size = 1, alpha = 0.9)
kpi_card <- kpi_card + annotate("text", x = 2.55, y = 4.35, label = "Coverage Distribution",
                                size = 3.5, fontface = "bold", color = dark_blue, hjust = 0.5)
kpi_card <- kpi_card + annotate("text", x = 1.3, y = 4.0, label = glue("≥90%: {additional_metrics$districts_above_90} districts"),
                                size = 2.8, color = dark_grey, hjust = 0)
kpi_card <- kpi_card + annotate("text", x = 1.3, y = 3.7, label = glue("<80%: {additional_metrics$districts_below_80} districts"),
                                size = 2.8, color = alert_red, hjust = 0)

# Calculate middle range
middle_districts <- kpi$districts - additional_metrics$districts_above_90 - additional_metrics$districts_below_80
kpi_card <- kpi_card + annotate("text", x = 3.8, y = 4.0, label = glue("80-90%: {middle_districts} districts"),
                                size = 2.8, color = warning_orange, hjust = 0)

# Root Cause Snapshot
kpi_card <- kpi_card + annotate("rect", xmin = 5.0, xmax = 9.7, ymin = 3.4, ymax = 4.6, fill = "white", color = dark_blue, size = 1, alpha = 0.9)
kpi_card <- kpi_card + annotate("text", x = 7.35, y = 4.35, label = "Top Missed Children Causes",
                                size = 3.5, fontface = "bold", color = dark_blue, hjust = 0.5)
kpi_card <- kpi_card + annotate("text", x = 5.4, y = 4.0, label = glue("• Non-compliance: {percent(additional_metrics$non_compliance_rate, accuracy = 0.1)}"),
                                size = 2.8, color = alert_red, hjust = 0)
kpi_card <- kpi_card + annotate("text", x = 5.4, y = 3.7, label = glue("• Absent: {percent(additional_metrics$absent_rate, accuracy = 0.1)}"),
                                size = 2.8, color = warning_orange, hjust = 0)

# ============================================================
# RISK CLASSIFICATION BREAKDOWN
# ============================================================

y_start <- 2.0
bar_height <- 0.35

# Calculate percentages for risk classes
total_events <- kpi$critical_risk_events + kpi$high_risk_events + kpi$moderate_risk_events + kpi$low_risk_events

if(total_events > 0) {
  critical_pct <- kpi$critical_risk_events / total_events * 100
  high_pct <- kpi$high_risk_events / total_events * 100
  moderate_pct <- kpi$moderate_risk_events / total_events * 100
  
  # Critical risk bar
  kpi_card <- kpi_card + annotate("rect", xmin = 0.3, xmax = 0.3 + (critical_pct / 100) * 9.4, 
                                  ymin = y_start, ymax = y_start + bar_height, fill = alert_red, color = NA, alpha = 0.9)
  
  # High risk bar
  kpi_card <- kpi_card + annotate("rect", xmin = 0.3, xmax = 0.3 + ((critical_pct + high_pct) / 100) * 9.4, 
                                  ymin = y_start, ymax = y_start + bar_height, fill = warning_orange, color = NA, alpha = 0.9)
  
  # Moderate risk bar
  kpi_card <- kpi_card + annotate("rect", xmin = 0.3, xmax = 0.3 + ((critical_pct + high_pct + moderate_pct) / 100) * 9.4, 
                                  ymin = y_start, ymax = y_start + bar_height, fill = who_blue, color = NA, alpha = 0.9)
}

# Risk labels
kpi_card <- kpi_card + annotate("text", x = 0.5, y = y_start + bar_height + 0.12, 
                                label = glue("Critical: {kpi$critical_risk_events} ({if(total_events>0) round(critical_pct) else 0}%)"),
                                size = 3, fontface = "bold", color = alert_red, hjust = 0)

kpi_card <- kpi_card + annotate("text", x = 2.5, y = y_start + bar_height + 0.12, 
                                label = glue("High: {kpi$high_risk_events} ({if(total_events>0) round(high_pct) else 0}%)"),
                                size = 3, fontface = "bold", color = warning_orange, hjust = 0)

kpi_card <- kpi_card + annotate("text", x = 4.5, y = y_start + bar_height + 0.12, 
                                label = glue("Moderate: {kpi$moderate_risk_events} ({if(total_events>0) round(moderate_pct) else 0}%)"),
                                size = 3, fontface = "bold", color = who_blue, hjust = 0)

kpi_card <- kpi_card + annotate("text", x = 7.0, y = y_start + bar_height + 0.12, 
                                label = glue("Low: {kpi$low_risk_events} ({if(total_events>0) round(100 - critical_pct - high_pct - moderate_pct) else 0}%)"),
                                size = 3, fontface = "bold", color = green_ok, hjust = 0)

# Title for risk breakdown
kpi_card <- kpi_card + annotate("text", x = 0.3, y = y_start + bar_height + 0.28, 
                                label = "DISTRICT RISK CLASSIFICATION BREAKDOWN",
                                size = 3.2, fontface = "bold", color = dark_blue, hjust = 0)

# ============================================================
# FOOTER / SOURCE
# ============================================================

kpi_card <- kpi_card + annotate("text", x = 0.3, y = 0.5, hjust = 0,
                                label = "Source: AFRO Independent Monitoring Repository | Data: Country + Province + District uniqueness",
                                size = 2.8, color = "grey40")

kpi_card <- kpi_card + annotate("text", x = 9.7, y = 0.5, hjust = 1,
                                label = glue("AFRO IM Intelligence • {format(Sys.Date(), '%Y-%m-%d')}"),
                                size = 2.8, color = "grey40")

# Set limits
kpi_card <- kpi_card + xlim(0, 10) + ylim(0, 9) + theme_void()

# Save with appropriate dimensions
ggsave(file.path(plot_dir, "00_AFRO_executive_KPI_card.png"), 
       kpi_card, width = 16, height = 11, dpi = 300)

# Also save a compact version for PowerPoint
ggsave(file.path(plot_dir, "00_AFRO_executive_KPI_card_compact.png"), 
       kpi_card, width = 14, height = 10, dpi = 300)

cat("Enhanced KPI card saved with additional metrics\n")

# ============================================================
# VISUAL 1: ROOT CAUSES
# ============================================================
if (nrow(root_cause_regional) > 0 && sum(root_cause_regional$missed_children, na.rm = TRUE) > 0) {
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
  
  ggsave(file.path(plot_dir, "01_AFRO_root_causes_missed_children.png"), p1, width = 13, height = 8, dpi = 300)
}

# ============================================================
# VISUAL 2: TOP PRIORITY DISTRICTS
# ============================================================
if (nrow(top_30_priority) > 0) {
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
  
  ggsave(file.path(plot_dir, "02_AFRO_top_priority_districts.png"), p2, width = 14, height = 10, dpi = 300)
}

# ============================================================
# VISUAL 3: COUNTRY RISK PROFILE
# ============================================================
if (nrow(country_summary_regional) > 0) {
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
  
  ggsave(file.path(plot_dir, "03_AFRO_country_risk_profile.png"), p3, width = 13, height = 8, dpi = 300)
}

# ============================================================
# VISUAL 4: SM AWARENESS VS COVERAGE (WITH WRAPPED LEGEND)
# ============================================================
if (nrow(sm_summary_regional) > 0) {
  
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
    scale_fill_manual(
      values = c(
        "Low awareness + low coverage" = alert_red,
        "Low awareness but acceptable coverage" = warning_orange,
        "High awareness but low coverage" = purple_alert,
        "High awareness + good coverage" = who_blue
      ),
      labels = function(x) str_wrap(x, width = 22)
    ) +
    labs(
      title = "Social mobilisation awareness vs vaccination coverage",
      subtitle = "Each bubble is a unique district; bubble size reflects missed children",
      x = "Caregiver awareness rate",
      y = "Vaccination coverage (CV)",
      caption = "Advocacy message: low-awareness districts require intensified pre-campaign mobilisation"
    ) +
    theme_un_advocacy(legend_position = "bottom") +
    guides(
      fill = guide_legend(nrow = 2, byrow = TRUE),
      size = guide_legend(nrow = 1, title = "Missed children")
    )
  
  # Save with extra height for legend
  ggsave(file.path(plot_dir, "04_AFRO_SM_awareness_vs_coverage.png"), 
         p4, width = 12, height = 10, dpi = 300)
}

# ============================================================
# VISUAL 5: ADVOCACY RECOMMENDATION CARD
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

ggsave(file.path(plot_dir, "05_AFRO_advocacy_recommendation_card.png"), recommendation_card, width = 14, height = 8, dpi = 300)

# ============================================================
# EXCEL WORKBOOK
# ============================================================
wb <- createWorkbook()

sheet_list <- list(
  "Executive Snapshot" = executive_snapshot,
  "Root Cause Regional" = root_cause_regional,
  "Root Cause District" = root_cause_by_district,
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
  setColWidths(wb, sheet_name, cols = 1:20, widths = "auto")
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
    "Prepared for regional programme intelligence and advocacy. District counts are based on unique Country + Province + District combinations.",
    style = "Normal"
  ) %>%
  body_add_par("1. Executive Snapshot", style = "heading 2") %>%
  body_add_flextable(flextable(executive_snapshot) %>% autofit()) %>%
  body_add_par("2. Top Priority Districts", style = "heading 2") %>%
  body_add_flextable(flextable(top_30_priority %>% select(-district_uid, -advocacy_message, -observations, -max_risk_score)) %>% autofit()) %>%
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
cat("\n")
cat("============================================================\n")
cat("AFRO REGIONAL IM INTELLIGENCE REPORT COMPLETED\n")
cat("============================================================\n")
cat("Output folder:", output_dir, "\n")
cat("Excel:", file.path(output_dir, "AFRO_Regional_IM_Intelligence_Report.xlsx"), "\n")
cat("Word brief:", file.path(output_dir, "AFRO_Regional_IM_Intelligence_Brief.docx"), "\n")
cat("Plots saved in:", plot_dir, "\n")
cat("Tables saved in:", table_dir, "\n")
cat("============================================================\n")
cat("\n")
cat("Countries analysed:", n_distinct(risk_data$country), "\n")
cat("Unique districts analysed:", n_distinct(risk_data$district_uid), "\n")
cat("Total missed children:", comma(executive_snapshot$total_missed_children), "\n")
cat("Regional CV:", executive_snapshot$regional_cv_pct, "\n")
cat("Top priority districts exported:", nrow(top_30_priority), "\n")
cat("============================================================\n")