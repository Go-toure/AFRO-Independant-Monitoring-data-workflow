# ============================================================
# PHASE 1 - AFRO IM INTELLIGENCE ANALYSIS ENGINE
# 1. Missed Children Root Cause Intelligence
# 2. Social Mobilisation Effectiveness Analysis
# 3. Operational Failure Analysis
# 4. District Risk Scoring
# ============================================================

pacman::p_load(
  tidyverse, lubridate, readr, openxlsx, scales, janitor
)

# ============================================================
# PATHS Regional_IM_repository_cleaned
# ============================================================
# input_file <- "C:/Users/TOURE/Documents/PADACORD/IM_c/Regional_IM_repository.csv"

# Connected to the im_workflow pipeline: reads the cleaned repository produced
# by clean_geonames.R / regional_im_repository_builder.R (data/final), and
# writes its Phase 1 tables to an intermediate folder that
# AFRO_Advocacy_Intelligence_Report.R reads from next.
# BASE_DIR: when this script runs the normal way -- source_safely()
# from inside run_workflow.R, for Step 4's optional reports --
# run_workflow.R's own BASE_DIR (already resolved via the shared
# find_workflow_home()) is sitting right there in this same R
# session, so just reuse it. Only resolve it fresh (searching upward
# from the working directory, same logic find_workflow_home() itself
# uses) for a standalone run. This replaces a hardcoded Windows-laptop
# fallback path that was silently wrong on Connect Cloud otherwise.
if (!exists("BASE_DIR", inherits = TRUE)) {
  .aiaee_dir <- getwd()
  .aiaee_fwh <- NULL
  for (.aiaee_i in 1:6) {
    .aiaee_candidate <- file.path(.aiaee_dir, "scripts", "find_workflow_home.R")
    if (file.exists(.aiaee_candidate)) { .aiaee_fwh <- .aiaee_candidate; break }
    .aiaee_parent <- dirname(.aiaee_dir)
    if (identical(.aiaee_parent, .aiaee_dir)) break
    .aiaee_dir <- .aiaee_parent
  }
  if (is.null(.aiaee_fwh))
    stop("Could not locate scripts/find_workflow_home.R by searching upward from: ", getwd())
  source(.aiaee_fwh)
  BASE_DIR <- find_workflow_home()
  rm(.aiaee_dir, .aiaee_fwh, .aiaee_i, .aiaee_candidate)
  if (exists(".aiaee_parent")) rm(.aiaee_parent)
}
input_file <- file.path(BASE_DIR, "data/final/Regional_IM_repository_cleaned.csv")

output_dir <- file.path(BASE_DIR, "outputs/phase1_intelligence")
plot_dir   <- file.path(output_dir, "plots")
table_dir  <- file.path(output_dir, "tables")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

# Recover this script's own input (Regional_IM_repository_cleaned.csv,
# Clean Geonames' output) from SharePoint if the Shiny dashboard just
# launched this as its own standalone "Intelligence Engine" step, on a
# fresh container where Clean Geonames didn't just run in this same
# session -- see scripts/sharepoint_recovery.R's own header comment.
source(file.path(BASE_DIR, "scripts", "sharepoint_recovery.R"))
sp_load_secrets_env(BASE_DIR)
sp_recover_file(
  input_file,
  paste0("7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/clean_state/", basename(input_file))
)


# ============================================================
# 1. LOAD DATA
# ============================================================
im <- read_csv(input_file, show_col_types = FALSE) %>%
  clean_names()

message("Data loaded: ", nrow(im), " rows x ", ncol(im), " columns")

# ============================================================
# 2. UNIVERSAL SANITIZATION LAYER
# ============================================================
special_missing_codes <- c(
  -999, -998, -997, -996, -995,
  999,  998,  997,  996
)

sanitize_numeric <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x[x %in% special_missing_codes] <- NA
  x[x < 0] <- NA
  x
}

numeric_candidates <- c(
  "number_of_hh_visited", "u5_present", "u5_fm", "missed_child", "cv",
  "r_non_fm_absent", "r_non_fm_nc", "r_non_fm_hh_notvisited",
  "r_non_fm_hh_notrevisited", "r_non_fm_sleep",
  "r_non_fm_vaccinated_routine", "r_non_fm_other",
  "care_giver_informed_sia", "percent_care_giver_informed_sia",
  "sm_total_sources", "sm_total_awareness_sources", "sm_not_aware",
  "sm_info_tv", "sm_info_radio", "sm_info_others", "sm_info_hworker",
  "sm_info_mob_vanpa", "sm_info_town_crier", "sm_info_volunteers",
  "sm_info_com_infocentre", "sm_info_community_leader",
  "sm_info_religious_leader", "sm_info_mobile_social_media",
  "sm_info_mourchidate", "sm_info_mosque", "sm_info_vaccinators",
  "sm_info_h2h_mobilizer", "sm_info_sticker",
  "reasons_total", "unexplained_missed", "overreported_reasons",
  "abs_detail_total", "nc_detail_total"
)

numeric_existing <- intersect(numeric_candidates, names(im))

im <- im %>%
  mutate(across(all_of(numeric_existing), sanitize_numeric)) %>%
  mutate(
    round_start_date  = suppressWarnings(as.Date(round_start_date)),
    start_date_im_end = suppressWarnings(as.Date(start_date_im_end)),
    end_date_im_end   = suppressWarnings(as.Date(end_date_im_end)),
    
    year = coalesce(year, lubridate::year(round_start_date)),
    
    r_non_compliance = case_when(
      "r_non_compliance" %in% names(.) &
        !is.na(r_non_compliance) &
        r_non_compliance > 0 ~ r_non_compliance,
      TRUE ~ coalesce(r_non_fm_nc, 0)
    ),
    
    missed_child = pmax(coalesce(u5_present, 0) - coalesce(u5_fm, 0), 0),
    
    cv = case_when(
      u5_present > 0 ~ round(u5_fm / u5_present, 4),
      TRUE ~ NA_real_
    ),
    
    cv = pmin(cv, 1),
    
    reasons_total =
      coalesce(r_non_fm_absent, 0) +
      coalesce(r_non_fm_nc, 0) +
      coalesce(r_non_fm_hh_notvisited, 0) +
      coalesce(r_non_fm_hh_notrevisited, 0) +
      coalesce(r_non_fm_sleep, 0) +
      coalesce(r_non_fm_vaccinated_routine, 0) +
      coalesce(r_non_fm_other, 0),
    
    unexplained_missed = pmax(missed_child - reasons_total, 0),
    overreported_reasons = pmax(reasons_total - missed_child, 0),
    
    missed_rate = if_else(u5_present > 0, missed_child / u5_present, NA_real_),
    absent_rate = if_else(missed_child > 0, r_non_fm_absent / missed_child, NA_real_),
    nc_rate = if_else(missed_child > 0, r_non_fm_nc / missed_child, NA_real_),
    notvisited_rate = if_else(missed_child > 0, r_non_fm_hh_notvisited / missed_child, NA_real_),
    notrevisited_rate = if_else(missed_child > 0, r_non_fm_hh_notrevisited / missed_child, NA_real_),
    
    awareness_rate = if_else(
      number_of_hh_visited > 0,
      care_giver_informed_sia / number_of_hh_visited,
      NA_real_
    ),
    
    sm_source_density = if_else(
      number_of_hh_visited > 0,
      sm_total_sources / number_of_hh_visited,
      NA_real_
    )
  )

# ============================================================
# 3. MODULE 1 - MISSED CHILDREN ROOT CAUSE INTELLIGENCE
# ============================================================
root_cause <- im %>%
  group_by(country, province, district, response, round_number, vaccine_type) %>%
  summarise(
    number_of_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
    u5_present = sum(u5_present, na.rm = TRUE),
    u5_fm = sum(u5_fm, na.rm = TRUE),
    missed_child = sum(missed_child, na.rm = TRUE),
    
    absent = sum(r_non_fm_absent, na.rm = TRUE),
    non_compliance = sum(r_non_fm_nc, na.rm = TRUE),
    house_not_visited = sum(r_non_fm_hh_notvisited, na.rm = TRUE),
    house_not_revisited = sum(r_non_fm_hh_notrevisited, na.rm = TRUE),
    asleep = sum(r_non_fm_sleep, na.rm = TRUE),
    vaccinated_routine = sum(r_non_fm_vaccinated_routine, na.rm = TRUE),
    other = sum(r_non_fm_other, na.rm = TRUE),
    
    .groups = "drop"
  ) %>%
  mutate(
    cv = if_else(u5_present > 0, u5_fm / u5_present, NA_real_),
    missed_rate = if_else(u5_present > 0, missed_child / u5_present, NA_real_),
    
    main_root_cause = pmap_chr(
      list(
        absent, non_compliance, house_not_visited,
        house_not_revisited, asleep, vaccinated_routine, other
      ),
      function(absent, non_compliance, house_not_visited,
               house_not_revisited, asleep, vaccinated_routine, other) {
        
        vals <- c(
          "Absent" = absent,
          "Non-compliance" = non_compliance,
          "House not visited" = house_not_visited,
          "House not revisited" = house_not_revisited,
          "Sleeping child" = asleep,
          "Vaccinated routine" = vaccinated_routine,
          "Other" = other
        )
        
        if (sum(vals, na.rm = TRUE) == 0) return("No missed / no reason")
        names(vals)[which.max(vals)]
      }
    )
  )

write_csv(root_cause, file.path(table_dir, "01_missed_children_root_cause.csv"))

# ============================================================
# 4. MODULE 2 - SOCIAL MOBILISATION EFFECTIVENESS
# ============================================================
sm_effectiveness <- im %>%
  group_by(country, province, district, response, round_number) %>%
  summarise(
    number_of_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
    u5_present = sum(u5_present, na.rm = TRUE),
    u5_fm = sum(u5_fm, na.rm = TRUE),
    missed_child = sum(missed_child, na.rm = TRUE),
    non_compliance = sum(r_non_fm_nc, na.rm = TRUE),
    care_giver_informed_sia = sum(care_giver_informed_sia, na.rm = TRUE),
    sm_total_sources = sum(sm_total_sources, na.rm = TRUE),
    
    tv = sum(sm_info_tv, na.rm = TRUE),
    radio = sum(sm_info_radio, na.rm = TRUE),
    health_worker = sum(sm_info_hworker, na.rm = TRUE),
    town_crier = sum(sm_info_town_crier, na.rm = TRUE),
    volunteers = sum(sm_info_volunteers, na.rm = TRUE),
    community_leader = sum(sm_info_community_leader, na.rm = TRUE),
    religious_leader = sum(sm_info_religious_leader, na.rm = TRUE),
    social_media = sum(sm_info_mobile_social_media, na.rm = TRUE),
    mosque = sum(sm_info_mosque, na.rm = TRUE),
    vaccinators = sum(sm_info_vaccinators, na.rm = TRUE),
    h2h_mobilizer = sum(sm_info_h2h_mobilizer, na.rm = TRUE),
    
    .groups = "drop"
  ) %>%
  mutate(
    cv = if_else(u5_present > 0, u5_fm / u5_present, NA_real_),
    missed_rate = if_else(u5_present > 0, missed_child / u5_present, NA_real_),
    nc_rate = if_else(u5_present > 0, non_compliance / u5_present, NA_real_),
    awareness_rate = if_else(number_of_hh_visited > 0, care_giver_informed_sia / number_of_hh_visited, NA_real_),
    sm_density = if_else(number_of_hh_visited > 0, sm_total_sources / number_of_hh_visited, NA_real_),
    
    sm_intensity_group = case_when(
      sm_density == 0 | is.na(sm_density) ~ "No SM source",
      sm_density < 0.25 ~ "Low SM intensity",
      sm_density < 0.75 ~ "Moderate SM intensity",
      TRUE ~ "High SM intensity"
    ),
    
    sm_effectiveness_score = round(
      (coalesce(cv, 0) * coalesce(awareness_rate, 0)) /
        (coalesce(missed_rate, 0) + coalesce(nc_rate, 0) + 0.001),
      3
    ),
    
    sm_effectiveness_class = case_when(
      sm_effectiveness_score >= 20 ~ "Very strong SM performance",
      sm_effectiveness_score >= 10 ~ "Good SM performance",
      sm_effectiveness_score >= 5  ~ "Moderate SM performance",
      TRUE ~ "Weak SM performance"
    )
  )

write_csv(sm_effectiveness, file.path(table_dir, "02_sm_effectiveness_analysis.csv"))

# ============================================================
# 5. MODULE 3 - OPERATIONAL FAILURE ANALYSIS
# ============================================================
operational_failure <- im %>%
  group_by(country, province, district, response, round_number) %>%
  summarise(
    u5_present = sum(u5_present, na.rm = TRUE),
    u5_fm = sum(u5_fm, na.rm = TRUE),
    missed_child = sum(missed_child, na.rm = TRUE),
    absent = sum(r_non_fm_absent, na.rm = TRUE),
    non_compliance = sum(r_non_fm_nc, na.rm = TRUE),
    house_not_visited = sum(r_non_fm_hh_notvisited, na.rm = TRUE),
    house_not_revisited = sum(r_non_fm_hh_notrevisited, na.rm = TRUE),
    asleep = sum(r_non_fm_sleep, na.rm = TRUE),
    vaccinated_routine = sum(r_non_fm_vaccinated_routine, na.rm = TRUE),
    other = sum(r_non_fm_other, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    missed_rate = if_else(u5_present > 0, missed_child / u5_present, NA_real_),
    notvisited_share = if_else(missed_child > 0, house_not_visited / missed_child, NA_real_),
    notrevisited_share = if_else(missed_child > 0, house_not_revisited / missed_child, NA_real_),
    absent_share = if_else(missed_child > 0, absent / missed_child, NA_real_),
    nc_share = if_else(missed_child > 0, non_compliance / missed_child, NA_real_),
    
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

write_csv(operational_failure, file.path(table_dir, "03_operational_failure_analysis.csv"))

# ============================================================
# 6. MODULE 4 - DISTRICT RISK SCORING
# ============================================================
district_risk <- root_cause %>%
  left_join(
    sm_effectiveness %>%
      select(
        country, province, district, response, round_number,
        awareness_rate, sm_density, nc_rate, sm_effectiveness_score
      ),
    by = c("country", "province", "district", "response", "round_number")
  ) %>%
  left_join(
    operational_failure %>%
      select(
        country, province, district, response, round_number,
        notvisited_share, notrevisited_share, operational_failure_type
      ),
    by = c("country", "province", "district", "response", "round_number")
  ) %>%
  mutate(
    missed_rate_score = rescale(coalesce(missed_rate, 0), to = c(0, 100)),
    nc_score = rescale(coalesce(nc_rate, 0), to = c(0, 100)),
    no_awareness_score = rescale(1 - coalesce(awareness_rate, 0), to = c(0, 100)),
    notvisited_score = rescale(coalesce(notvisited_share, 0), to = c(0, 100)),
    notrevisited_score = rescale(coalesce(notrevisited_share, 0), to = c(0, 100)),
    
    district_risk_score = round(
      0.30 * missed_rate_score +
        0.25 * nc_score +
        0.20 * no_awareness_score +
        0.15 * notvisited_score +
        0.10 * notrevisited_score,
      1
    ),
    
    district_risk_class = case_when(
      district_risk_score >= 75 ~ "Critical risk",
      district_risk_score >= 50 ~ "High risk",
      district_risk_score >= 25 ~ "Moderate risk",
      TRUE ~ "Low risk"
    ),
    
    recommended_action = case_when(
      district_risk_class == "Critical risk" &
        main_root_cause == "Non-compliance" ~ "Urgent community engagement and refusal management",
      
      district_risk_class == "Critical risk" &
        main_root_cause == "House not visited" ~ "Immediate team deployment review",
      
      district_risk_class == "Critical risk" &
        main_root_cause == "House not revisited" ~ "Strengthen revisit tracking and supervision",
      
      district_risk_class %in% c("Critical risk", "High risk") &
        awareness_rate < 0.8 ~ "Intensify social mobilisation",
      
      district_risk_class %in% c("Critical risk", "High risk") ~ "Prioritize for next campaign microplanning",
      
      TRUE ~ "Routine monitoring"
    )
  ) %>%
  arrange(desc(district_risk_score))

write_csv(district_risk, file.path(table_dir, "04_district_risk_scoring.csv"))

# ============================================================
# 7. EXECUTIVE SUMMARY TABLES
# ============================================================
country_summary <- district_risk %>%
  group_by(country) %>%
  summarise(
    districts = n_distinct(district),
    total_u5_present = sum(u5_present, na.rm = TRUE),
    total_missed = sum(missed_child, na.rm = TRUE),
    mean_cv = mean(cv, na.rm = TRUE),
    mean_missed_rate = mean(missed_rate, na.rm = TRUE),
    mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
    critical_districts = sum(district_risk_class == "Critical risk", na.rm = TRUE),
    high_risk_districts = sum(district_risk_class == "High risk", na.rm = TRUE),
    mean_risk_score = mean(district_risk_score, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(mean_risk_score))

top_risk_districts <- district_risk %>%
  select(
    country, province, district, response, round_number,
    missed_child, missed_rate, cv,
    main_root_cause, operational_failure_type,
    awareness_rate, district_risk_score,
    district_risk_class, recommended_action
  ) %>%
  arrange(desc(district_risk_score)) %>%
  slice_head(n = 100)

write_csv(country_summary, file.path(table_dir, "05_country_summary.csv"))
write_csv(top_risk_districts, file.path(table_dir, "06_top_100_risk_districts.csv"))

# ============================================================
# 8. EXPORT EXCEL WORKBOOK
# ============================================================
wb <- createWorkbook()

addWorksheet(wb, "Root Cause")
writeData(wb, "Root Cause", root_cause)

addWorksheet(wb, "SM Effectiveness")
writeData(wb, "SM Effectiveness", sm_effectiveness)

addWorksheet(wb, "Operational Failure")
writeData(wb, "Operational Failure", operational_failure)

addWorksheet(wb, "District Risk")
writeData(wb, "District Risk", district_risk)

addWorksheet(wb, "Country Summary")
writeData(wb, "Country Summary", country_summary)

addWorksheet(wb, "Top Risk Districts")
writeData(wb, "Top Risk Districts", top_risk_districts)

saveWorkbook(
  wb,
  file.path(output_dir, "AFRO_IM_Phase1_Intelligence_Analysis.xlsx"),
  overwrite = TRUE
)

# ============================================================
# 9. BASIC PLOTS
# ============================================================

p1 <- top_risk_districts %>%
  slice_head(n = 25) %>%
  mutate(district_label = paste(country, province, district, sep = " | ")) %>%
  ggplot(aes(x = reorder(district_label, district_risk_score), y = district_risk_score)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Top 25 Highest Risk Districts",
    x = NULL,
    y = "District Risk Score"
  ) +
  theme_minimal(base_size = 13)

ggsave(
  file.path(plot_dir, "top_25_highest_risk_districts.png"),
  p1,
  width = 12,
  height = 8,
  dpi = 300
)

p2 <- root_cause %>%
  filter(missed_child > 0) %>%
  count(main_root_cause, wt = missed_child, name = "missed_children") %>%
  ggplot(aes(x = reorder(main_root_cause, missed_children), y = missed_children)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Main Root Causes of Missed Children",
    x = NULL,
    y = "Missed Children"
  ) +
  theme_minimal(base_size = 13)

ggsave(
  file.path(plot_dir, "main_root_causes_missed_children.png"),
  p2,
  width = 10,
  height = 7,
  dpi = 300
)

p3 <- sm_effectiveness %>%
  group_by(sm_intensity_group) %>%
  summarise(
    mean_cv = mean(cv, na.rm = TRUE),
    mean_nc_rate = mean(nc_rate, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  ggplot(aes(x = sm_intensity_group, y = mean_cv)) +
  geom_col() +
  labs(
    title = "Coverage by Social Mobilisation Intensity",
    x = NULL,
    y = "Mean Coverage"
  ) +
  scale_y_continuous(labels = percent_format()) +
  theme_minimal(base_size = 13)

ggsave(
  file.path(plot_dir, "coverage_by_sm_intensity.png"),
  p3,
  width = 10,
  height = 6,
  dpi = 300
)

# ============================================================
# 10. FINAL MESSAGE
# ============================================================
message("============================================================")
message("PHASE 1 IM INTELLIGENCE ANALYSIS COMPLETED SUCCESSFULLY")
message("Outputs saved in: ", output_dir)
message("============================================================")


# ============================================================
# 11. BACK UP PHASE 1 TABLES TO SHAREPOINT
# ============================================================
# AFRO_Advocacy_Intelligence_Report.R (via generate_reports_and_deck.R)
# reads these 4 tables directly, but the Shiny dashboard launches it as
# its own standalone "Generate Report + Deck" step, bypassing this script
# and run_workflow.R entirely -- see that script's own recovery call and
# scripts/sharepoint_recovery.R's header comment for the full picture.
for (phase1_table in c(
  "01_missed_children_root_cause.csv",
  "02_sm_effectiveness_analysis.csv",
  "03_operational_failure_analysis.csv",
  "04_district_risk_scoring.csv"
)) {
  sp_backup_file(
    file.path(table_dir, phase1_table),
    paste0("7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/phase1_state/", phase1_table)
  )
}
