generate_afro_im_intelligence_report <- function(
    workflow_dir = "C:/Users/TOURE/Documents/im_workflow",
    last_n_months = NULL,
    afro_block = NULL,
    country = NULL,
    vaccine_type = NULL,
    year = NULL,
    start_date = NULL,
    end_date = NULL,
    output_suffix = NULL
) {
  
  pacman::p_load(
    tidyverse, lubridate, readr, openxlsx, janitor,
    scales, glue, flextable, officer, ggplot2,
    patchwork, cowplot, stringr, forcats, arrow
  )
  
  input_dir <- file.path(workflow_dir, "data/final")
  cleaned_data_file <- file.path(input_dir, "Regional_IM_repository_cleaned.rds")
  cleaned_data_csv  <- file.path(input_dir, "Regional_IM_repository_cleaned.csv")
  
  output_dir <- file.path(workflow_dir, "outputs/reports/IM_Intelligence_Report")
  plot_dir   <- file.path(output_dir, "plots")
  table_dir  <- file.path(output_dir, "tables")
  
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  
  cat("Loading cleaned IM data...\n")
  
  if (file.exists(cleaned_data_file)) {
    im_data <- readRDS(cleaned_data_file)
  } else if (file.exists(cleaned_data_csv)) {
    im_data <- read_csv(cleaned_data_csv, show_col_types = FALSE)
  } else {
    stop("No cleaned IM data found. Please run the IM workflow first.")
  }
  
  names(im_data) <- tolower(names(im_data))
  
  required_cols <- c("country", "province", "district", "u5_present", "u5_fm")
  missing_cols <- setdiff(required_cols, names(im_data))
  
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  
  if (!"vaccine_type" %in% names(im_data)) im_data$vaccine_type <- "Unknown"
  if (!"afro_block" %in% names(im_data)) im_data$afro_block <- "AFRO"
  if (!"response" %in% names(im_data)) im_data$response <- "Unknown"
  if (!"roundnumber" %in% names(im_data)) im_data$roundnumber <- "Unknown"
  if (!"number_of_hh_visited" %in% names(im_data)) im_data$number_of_hh_visited <- NA_real_
  if (!"care_giver_informed_sia" %in% names(im_data)) im_data$care_giver_informed_sia <- NA_real_
  
  date_col <- dplyr::case_when(
    "sia_date" %in% names(im_data) ~ "sia_date",
    "round_start_date" %in% names(im_data) ~ "round_start_date",
    "date" %in% names(im_data) ~ "date",
    "submissiondate" %in% names(im_data) ~ "submissiondate",
    TRUE ~ NA_character_
  )
  
  if (is.na(date_col)) {
    stop("No usable date column found. Expected one of: sia_date, round_start_date, date, submissiondate.")
  }
  
  im_data <- im_data %>%
    mutate(
      campaign_date = suppressWarnings(as.Date(.data[[date_col]])),
      year = lubridate::year(campaign_date),
      month = lubridate::month(campaign_date),
      month_lab = factor(month.abb[month], levels = month.abb, ordered = TRUE),
      district_uid = paste(country, province, district, sep = " | "),
      missed_child = if ("missed_child" %in% names(.)) missed_child else u5_present - u5_fm,
      cv = if_else(u5_present > 0, u5_fm / u5_present, NA_real_),
      missed_rate = if_else(u5_present > 0, missed_child / u5_present, NA_real_),
      awareness_rate = if_else(
        number_of_hh_visited > 0,
        care_giver_informed_sia / number_of_hh_visited,
        NA_real_
      )
    )
  
  risk_data <- im_data %>%
    mutate(
      district_risk_score =
        case_when(
          cv < 0.80 ~ 60,
          cv < 0.90 ~ 40,
          cv >= 0.90 ~ 20,
          TRUE ~ 50
        ) +
        case_when(
          missed_rate > 0.20 ~ 30,
          missed_rate > 0.10 ~ 15,
          TRUE ~ 0
        ) +
        case_when(
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
  
  filtered_risk_data <- risk_data
  
  if (!is.null(last_n_months)) {
    max_date <- max(filtered_risk_data$campaign_date, na.rm = TRUE)
    cutoff_date <- max_date %m-% months(last_n_months)
    filtered_risk_data <- filtered_risk_data %>%
      filter(campaign_date >= cutoff_date)
  }
  
  if (!is.null(afro_block) && afro_block != "") {
    filtered_risk_data <- filtered_risk_data %>%
      filter(.data$afro_block %in% afro_block)
  }
  
  if (!is.null(country)) {
    filtered_risk_data <- filtered_risk_data %>%
      filter(toupper(.data$country) %in% toupper(country))
  }
  
  if (!is.null(vaccine_type)) {
    filtered_risk_data <- filtered_risk_data %>%
      filter(.data$vaccine_type %in% vaccine_type)
  }
  
  if (!is.null(year)) {
    filtered_risk_data <- filtered_risk_data %>%
      filter(.data$year %in% year)
  }
  
  if (!is.null(start_date)) {
    filtered_risk_data <- filtered_risk_data %>%
      filter(campaign_date >= as.Date(start_date))
  }
  
  if (!is.null(end_date)) {
    filtered_risk_data <- filtered_risk_data %>%
      filter(campaign_date <= as.Date(end_date))
  }
  
  if (nrow(filtered_risk_data) == 0) {
    stop("No data available after applying filters.")
  }
  
  # DETERMINE ANALYSIS SCOPE
  is_single_country <- !is.null(country) && length(country) == 1
  analysis_scope <- ifelse(is_single_country, "country", "regional")
  analysis_name <- ifelse(is_single_country, toupper(country[1]), "AFRO Regional")
  
  cat("\n============================================================\n")
  cat("ANALYSIS SCOPE:", analysis_name, "\n")
  cat("Analysis type:", ifelse(is_single_country, "Country-level with province breakdown", "Regional aggregation"), "\n")
  cat("Number of records:", nrow(filtered_risk_data), "\n")
  cat("============================================================\n\n")
  
  who_blue       <- "#0093D5"
  dark_blue      <- "#003A70"
  alert_red      <- "#C00000"
  warning_orange <- "#F4B400"
  green_ok       <- "#8CC63E"
  dark_grey      <- "#3A3A3A"
  soft_grey      <- "#F5F7FA"
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
  
  # DYNAMIC EXECUTIVE SNAPSHOT BASED ON SCOPE
  if (is_single_country) {
    executive_snapshot <- filtered_risk_data %>%
      summarise(
        scope = analysis_name,
        country = first(country),
        provinces = n_distinct(province),
        districts = n_distinct(district_uid),
        campaigns_rounds = n_distinct(paste(response, roundnumber)),
        total_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
        total_u5_present = sum(u5_present, na.rm = TRUE),
        total_u5_fm = sum(u5_fm, na.rm = TRUE),
        total_missed_children = sum(missed_child, na.rm = TRUE),
        national_cv = total_u5_fm / total_u5_present,
        national_missed_rate = total_missed_children / total_u5_present,
        mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
        mean_risk_score = mean(district_risk_score, na.rm = TRUE),
        critical_risk_events = sum(district_risk_class == "Critical risk", na.rm = TRUE),
        high_risk_events = sum(district_risk_class == "High risk", na.rm = TRUE),
        moderate_risk_events = sum(district_risk_class == "Moderate risk", na.rm = TRUE),
        low_risk_events = sum(district_risk_class == "Low risk", na.rm = TRUE)
      ) %>%
      mutate(
        national_cv_pct = percent(national_cv, accuracy = 0.1),
        national_missed_rate_pct = percent(national_missed_rate, accuracy = 0.1),
        mean_awareness_rate_pct = percent(mean_awareness_rate, accuracy = 0.1)
      )
  } else {
    executive_snapshot <- filtered_risk_data %>%
      summarise(
        scope = "AFRO Regional",
        countries = n_distinct(country),
        afro_blocks = n_distinct(afro_block),
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
        regional_cv_pct = percent(regional_cv, accuracy = 0.1),
        regional_missed_rate_pct = percent(regional_missed_rate, accuracy = 0.1),
        mean_awareness_rate_pct = percent(mean_awareness_rate, accuracy = 0.1)
      )
  }
  
  # ROOT CAUSE ANALYSIS
  root_cause_cols <- intersect(
    c(
      "r_non_fm_absent",
      "r_non_fm_nc",
      "r_non_fm_hh_notvisited",
      "r_non_fm_hh_notrevisited",
      "r_non_fm_sleep",
      "r_non_fm_vaccinatedroutine",
      "r_non_fm_other",
      "r_non_fm_vaccinated_but_not_fm",
      "r_non_fm_child_is_a_visitor",
      "r_non_fm_childnotborn",
      "r_non_fm_security"
    ),
    names(filtered_risk_data)
  )
  
  if (length(root_cause_cols) > 0) {
    root_cause_summary <- filtered_risk_data %>%
      summarise(across(all_of(root_cause_cols), ~ sum(.x, na.rm = TRUE))) %>%
      pivot_longer(everything(), names_to = "root_cause", values_to = "missed_children") %>%
      mutate(
        root_cause = recode(
          root_cause,
          r_non_fm_absent = "Absent",
          r_non_fm_nc = "Non-compliance",
          r_non_fm_hh_notvisited = "House not visited",
          r_non_fm_hh_notrevisited = "House not revisited",
          r_non_fm_sleep = "Sleeping child",
          r_non_fm_vaccinatedroutine = "Vaccinated routine",
          r_non_fm_other = "Other",
          r_non_fm_vaccinated_but_not_fm = "Vaccinated but not FM",
          r_non_fm_child_is_a_visitor = "Visitor child",
          r_non_fm_childnotborn = "Child not born",
          r_non_fm_security = "Security"
        ),
        share = missed_children / sum(missed_children, na.rm = TRUE)
      ) %>%
      filter(missed_children > 0) %>%
      arrange(desc(missed_children))
  } else {
    root_cause_summary <- tibble(root_cause = character(), missed_children = numeric(), share = numeric())
  }
  
  # DYNAMIC HIERARCHICAL SUMMARIES
  if (is_single_country) {
    # Country-level: focus on provinces
    country_summary <- filtered_risk_data %>%
      group_by(province) %>%
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
    
    province_summary <- filtered_risk_data %>%
      group_by(province, district) %>%
      summarise(
        total_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
        total_u5_present = sum(u5_present, na.rm = TRUE),
        total_u5_fm = sum(u5_fm, na.rm = TRUE),
        total_missed = sum(missed_child, na.rm = TRUE),
        mean_cv = total_u5_fm / total_u5_present,
        mean_awareness_rate = mean(awareness_rate, na.rm = TRUE),
        mean_risk_score = mean(district_risk_score, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      arrange(desc(mean_risk_score), desc(total_missed))
    
    priority_districts <- filtered_risk_data %>%
      group_by(province, district, district_uid) %>%
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
    
    top_30_priority <- priority_districts %>%
      slice_head(n = 30)
    
    sm_summary <- filtered_risk_data %>%
      group_by(province, district, district_uid) %>%
      summarise(
        number_of_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
        u5_present = sum(u5_present, na.rm = TRUE),
        u5_fm = sum(u5_fm, na.rm = TRUE),
        missed_child = sum(missed_child, na.rm = TRUE),
        informed_hh = sum(care_giver_informed_sia, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        cv = if_else(u5_present > 0, u5_fm / u5_present, NA_real_),
        awareness_rate = if_else(number_of_hh_visited > 0, informed_hh / number_of_hh_visited, NA_real_),
        quadrant = case_when(
          awareness_rate < 0.80 & cv < 0.90 ~ "Low awareness + low coverage",
          awareness_rate < 0.80 & cv >= 0.90 ~ "Low awareness but acceptable coverage",
          awareness_rate >= 0.80 & cv < 0.90 ~ "High awareness but low coverage",
          TRUE ~ "High awareness + good coverage"
        )
      )
    
  } else {
    # Regional analysis
    country_summary <- filtered_risk_data %>%
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
    
    province_summary <- filtered_risk_data %>%
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
    
    priority_districts <- filtered_risk_data %>%
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
    
    top_30_priority <- priority_districts %>%
      slice_head(n = 30)
    
    sm_summary <- filtered_risk_data %>%
      group_by(country, province, district, district_uid) %>%
      summarise(
        number_of_hh_visited = sum(number_of_hh_visited, na.rm = TRUE),
        u5_present = sum(u5_present, na.rm = TRUE),
        u5_fm = sum(u5_fm, na.rm = TRUE),
        missed_child = sum(missed_child, na.rm = TRUE),
        informed_hh = sum(care_giver_informed_sia, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        cv = if_else(u5_present > 0, u5_fm / u5_present, NA_real_),
        awareness_rate = if_else(number_of_hh_visited > 0, informed_hh / number_of_hh_visited, NA_real_),
        quadrant = case_when(
          awareness_rate < 0.80 & cv < 0.90 ~ "Low awareness + low coverage",
          awareness_rate < 0.80 & cv >= 0.90 ~ "Low awareness but acceptable coverage",
          awareness_rate >= 0.80 & cv < 0.90 ~ "High awareness but low coverage",
          TRUE ~ "High awareness + good coverage"
        )
      )
  }
  
  # CV95 ANALYSIS (Dynamic grouping)
  if (is_single_country) {
    cv95_summary <- filtered_risk_data %>%
      filter(!is.na(year), !is.na(month), !is.na(month_lab)) %>%
      group_by(province, vaccine_type, year, month, month_lab, district_uid) %>%
      summarise(
        district_cv = sum(u5_fm, na.rm = TRUE) / sum(u5_present, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(cv95_status = district_cv >= 0.95) %>%
      group_by(province, vaccine_type, year, month, month_lab) %>%
      summarise(
        districts = n_distinct(district_uid),
        districts_cv95 = n_distinct(district_uid[cv95_status]),
        proportion_cv95 = districts_cv95 / districts,
        .groups = "drop"
      ) %>%
      arrange(year, month) %>%
      mutate(
        period = paste0(year, "_", month_lab),
        proportion_label = percent(proportion_cv95, accuracy = 0.1)
      )
    
    cv95_wide <- cv95_summary %>%
      select(province, vaccine_type, period, proportion_label) %>%
      pivot_wider(names_from = period, values_from = proportion_label) %>%
      arrange(province, vaccine_type)
    
    # Rename province column for flextable
    names(cv95_wide)[1] <- "province"
    
  } else {
    cv95_summary <- filtered_risk_data %>%
      filter(!is.na(year), !is.na(month), !is.na(month_lab)) %>%
      group_by(country, vaccine_type, year, month, month_lab, district_uid) %>%
      summarise(
        district_cv = sum(u5_fm, na.rm = TRUE) / sum(u5_present, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(cv95_status = district_cv >= 0.95) %>%
      group_by(country, vaccine_type, year, month, month_lab) %>%
      summarise(
        districts = n_distinct(district_uid),
        districts_cv95 = n_distinct(district_uid[cv95_status]),
        proportion_cv95 = districts_cv95 / districts,
        .groups = "drop"
      ) %>%
      arrange(year, month) %>%
      mutate(
        period = paste0(year, "_", month_lab),
        proportion_label = percent(proportion_cv95, accuracy = 0.1)
      )
    
    cv95_wide <- cv95_summary %>%
      select(country, vaccine_type, period, proportion_label) %>%
      pivot_wider(names_from = period, values_from = proportion_label) %>%
      arrange(country, vaccine_type)
  }
  
  # Create CV95 flextable
  if (nrow(cv95_wide) > 0) {
    ft_cv95 <- flextable(cv95_wide)
    
    if (is_single_country) {
      period_cols <- setdiff(names(cv95_wide), c("province", "vaccine_type"))
      if (length(period_cols) > 0) {
        header_mapping <- tibble(
          col_keys = c("province", "vaccine_type", period_cols),
          Year = c("", "", str_extract(period_cols, "^[0-9]{4}")),
          Month = c("Province", "Vaccine type", str_remove(period_cols, "^[0-9]{4}_"))
        )
        ft_cv95 <- set_header_df(ft_cv95, mapping = header_mapping, key = "col_keys")
      }
    } else {
      period_cols <- setdiff(names(cv95_wide), c("country", "vaccine_type"))
      if (length(period_cols) > 0) {
        header_mapping <- tibble(
          col_keys = c("country", "vaccine_type", period_cols),
          Year = c("", "", str_extract(period_cols, "^[0-9]{4}")),
          Month = c("Country", "Vaccine type", str_remove(period_cols, "^[0-9]{4}_"))
        )
        ft_cv95 <- set_header_df(ft_cv95, mapping = header_mapping, key = "col_keys")
      }
    }
    
    ft_cv95 <- ft_cv95 %>%
      merge_h(part = "header") %>%
      merge_v(part = "header") %>%
      add_header_lines(values = "Proportion of Districts by CV Performance") %>%
      add_footer_lines(values = "Legend: Green = ≥95% | Yellow = [80–95%[ | Red = <80%") %>%
      theme_vanilla() %>%
      bold(part = "header") %>%
      bold(part = "footer") %>%
      bg(bg = dark_blue, part = "header") %>%
      color(color = "white", part = "header") %>%
      align(align = "center", part = "all")
    
    for (col in period_cols) {
      numeric_vals <- suppressWarnings(
        as.numeric(str_remove(cv95_wide[[col]], "%"))
      )
      
      bg_colors <- dplyr::case_when(
        numeric_vals >= 95 ~ green_ok,
        numeric_vals >= 80 & numeric_vals < 95 ~ warning_orange,
        numeric_vals < 80 ~ alert_red,
        TRUE ~ "white"
      )
      
      text_colors <- dplyr::case_when(
        numeric_vals >= 80 & numeric_vals < 95 ~ "black",
        is.na(numeric_vals) ~ "black",
        TRUE ~ "white"
      )
      
      ft_cv95 <- bg(ft_cv95, j = col, bg = bg_colors, part = "body")
      ft_cv95 <- color(ft_cv95, j = col, color = text_colors, part = "body")
    }
    
    ft_cv95 <- autofit(ft_cv95)
    
    # Save CV95 flextable
    cv95_docx_name <- ifelse(is_single_country,
                             paste0("06_", gsub(" ", "_", analysis_name), "_CV95_flextable.docx"),
                             "06_AFRO_CV95_flextable.docx")
    cv95_png_name <- ifelse(is_single_country,
                            paste0("06_", gsub(" ", "_", analysis_name), "_CV95_flextable.png"),
                            "06_AFRO_CV95_flextable.png")
    
    save_as_docx("Proportion of Districts by CV Performance" = ft_cv95,
                 path = file.path(table_dir, cv95_docx_name))
    
    tryCatch({
      save_as_image(ft_cv95, path = file.path(plot_dir, cv95_png_name), zoom = 2)
    }, error = function(e) {
      message("CV95 flextable PNG export skipped: ", e$message)
    })
  }
  
  # DYNAMIC KPI CARD
  if (is_single_country) {
    kpi_card <- ggplot() +
      annotate("rect", xmin = 0, xmax = 10, ymin = 0, ymax = 9, fill = soft_grey, color = NA) +
      annotate("rect", xmin = 0, xmax = 10, ymin = 7.8, ymax = 9, fill = dark_blue, color = NA) +
      annotate("text", x = 0.5, y = 8.45, hjust = 0,
               label = glue("{analysis_name} INDEPENDENT MONITORING INTELLIGENCE"),
               size = 6, fontface = "bold", color = "white") +
      annotate("text", x = 0.5, y = 8.0, hjust = 0,
               label = glue("Generated: {format(Sys.Date(), '%B %d, %Y')}"),
               size = 3.8, color = "white") +
      annotate("rect", xmin = 0.3, xmax = 3.3, ymin = 6.2, ymax = 7.5, fill = "white", color = who_blue, linewidth = 1.3) +
      annotate("text", x = 1.8, y = 7.1, label = comma(executive_snapshot$total_hh_visited), size = 9, fontface = "bold", color = who_blue) +
      annotate("text", x = 1.8, y = 6.65, label = "Households Visited", size = 3.8, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 3.5, xmax = 6.5, ymin = 6.2, ymax = 7.5, fill = "white", color = who_blue, linewidth = 1.3) +
      annotate("text", x = 5, y = 7.1, label = executive_snapshot$national_cv_pct, size = 10, fontface = "bold", color = who_blue) +
      annotate("text", x = 5, y = 6.65, label = "National Coverage", size = 3.8, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 6.7, xmax = 9.7, ymin = 6.2, ymax = 7.5, fill = "white", color = alert_red, linewidth = 1.3) +
      annotate("text", x = 8.2, y = 7.1, label = comma(executive_snapshot$total_missed_children), size = 10, fontface = "bold", color = alert_red) +
      annotate("text", x = 8.2, y = 6.65, label = "Missed Children", size = 3.8, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 0.3, xmax = 3.3, ymin = 4.6, ymax = 5.8, fill = "white", color = warning_orange, linewidth = 1.1) +
      annotate("text", x = 1.8, y = 5.45, label = executive_snapshot$mean_awareness_rate_pct, size = 8.5, fontface = "bold", color = warning_orange) +
      annotate("text", x = 1.8, y = 5.05, label = "Caregiver Awareness", size = 3.5, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 3.5, xmax = 6.5, ymin = 4.6, ymax = 5.8, fill = "white", color = alert_red, linewidth = 1.1) +
      annotate("text", x = 5, y = 5.45, label = round(executive_snapshot$mean_risk_score, 1), size = 8.5, fontface = "bold", color = alert_red) +
      annotate("text", x = 5, y = 5.05, label = "Mean Risk Score", size = 3.5, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 6.7, xmax = 9.7, ymin = 4.6, ymax = 5.8, fill = "white", color = dark_blue, linewidth = 1.1) +
      annotate("text", x = 8.2, y = 5.45, label = executive_snapshot$campaigns_rounds, size = 8.5, fontface = "bold", color = dark_blue) +
      annotate("text", x = 8.2, y = 5.05, label = "Campaign Rounds", size = 3.5, fontface = "bold", color = dark_grey) +
      annotate("text", x = 0.5, y = 3.6, hjust = 0,
               label = glue("Provinces analysed: {executive_snapshot$provinces} | Districts analysed: {executive_snapshot$districts}"),
               size = 4.2, fontface = "bold", color = dark_blue) +
      annotate("text", x = 0.5, y = 3.1, hjust = 0,
               label = glue("Critical events: {executive_snapshot$critical_risk_events} | High-risk events: {executive_snapshot$high_risk_events}"),
               size = 3.6, color = dark_grey) +
      annotate("text", x = 0.5, y = 0.6, hjust = 0,
               label = "Source: AFRO Independent Monitoring Repository",
               size = 2.8, color = "grey40") +
      xlim(0, 10) + ylim(0, 9) + theme_void()
    
    kpi_filename <- paste0("00_", analysis_name, "_executive_KPI_card.png")
  } else {
    kpi_card <- ggplot() +
      annotate("rect", xmin = 0, xmax = 10, ymin = 0, ymax = 9, fill = soft_grey, color = NA) +
      annotate("rect", xmin = 0, xmax = 10, ymin = 7.8, ymax = 9, fill = dark_blue, color = NA) +
      annotate("text", x = 0.5, y = 8.45, hjust = 0,
               label = "AFRO REGIONAL INDEPENDENT MONITORING INTELLIGENCE",
               size = 6.5, fontface = "bold", color = "white") +
      annotate("text", x = 0.5, y = 8.0, hjust = 0,
               label = glue("Generated: {format(Sys.Date(), '%B %d, %Y')}"),
               size = 3.8, color = "white") +
      annotate("rect", xmin = 0.3, xmax = 3.3, ymin = 6.2, ymax = 7.5, fill = "white", color = who_blue, linewidth = 1.3) +
      annotate("text", x = 1.8, y = 7.1, label = comma(executive_snapshot$total_hh_visited), size = 9, fontface = "bold", color = who_blue) +
      annotate("text", x = 1.8, y = 6.65, label = "Households Visited", size = 3.8, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 3.5, xmax = 6.5, ymin = 6.2, ymax = 7.5, fill = "white", color = who_blue, linewidth = 1.3) +
      annotate("text", x = 5, y = 7.1, label = executive_snapshot$regional_cv_pct, size = 10, fontface = "bold", color = who_blue) +
      annotate("text", x = 5, y = 6.65, label = "Regional Coverage", size = 3.8, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 6.7, xmax = 9.7, ymin = 6.2, ymax = 7.5, fill = "white", color = alert_red, linewidth = 1.3) +
      annotate("text", x = 8.2, y = 7.1, label = comma(executive_snapshot$total_missed_children), size = 10, fontface = "bold", color = alert_red) +
      annotate("text", x = 8.2, y = 6.65, label = "Missed Children", size = 3.8, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 0.3, xmax = 3.3, ymin = 4.6, ymax = 5.8, fill = "white", color = warning_orange, linewidth = 1.1) +
      annotate("text", x = 1.8, y = 5.45, label = executive_snapshot$mean_awareness_rate_pct, size = 8.5, fontface = "bold", color = warning_orange) +
      annotate("text", x = 1.8, y = 5.05, label = "Caregiver Awareness", size = 3.5, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 3.5, xmax = 6.5, ymin = 4.6, ymax = 5.8, fill = "white", color = alert_red, linewidth = 1.1) +
      annotate("text", x = 5, y = 5.45, label = round(executive_snapshot$mean_risk_score, 1), size = 8.5, fontface = "bold", color = alert_red) +
      annotate("text", x = 5, y = 5.05, label = "Mean Risk Score", size = 3.5, fontface = "bold", color = dark_grey) +
      annotate("rect", xmin = 6.7, xmax = 9.7, ymin = 4.6, ymax = 5.8, fill = "white", color = dark_blue, linewidth = 1.1) +
      annotate("text", x = 8.2, y = 5.45, label = executive_snapshot$campaigns_rounds, size = 8.5, fontface = "bold", color = dark_blue) +
      annotate("text", x = 8.2, y = 5.05, label = "Campaign Rounds", size = 3.5, fontface = "bold", color = dark_grey) +
      annotate("text", x = 0.5, y = 3.6, hjust = 0,
               label = glue("Countries analysed: {executive_snapshot$countries} | Districts analysed: {executive_snapshot$districts}"),
               size = 4.2, fontface = "bold", color = dark_blue) +
      annotate("text", x = 0.5, y = 3.1, hjust = 0,
               label = glue("Critical events: {executive_snapshot$critical_risk_events} | High-risk events: {executive_snapshot$high_risk_events}"),
               size = 3.6, color = dark_grey) +
      annotate("text", x = 0.5, y = 0.6, hjust = 0,
               label = "Source: AFRO Independent Monitoring Repository",
               size = 2.8, color = "grey40") +
      xlim(0, 10) + ylim(0, 9) + theme_void()
    
    kpi_filename <- "00_AFRO_executive_KPI_card.png"
  }
  
  ggsave(file.path(plot_dir, kpi_filename), kpi_card, width = 16, height = 11, dpi = 300)
  
  # ROOT CAUSE PLOT
  if (nrow(root_cause_summary) > 0) {
    p_root <- root_cause_summary %>%
      mutate(
        root_cause = fct_reorder(root_cause, missed_children),
        label = paste0(comma(missed_children), " (", percent(share, accuracy = 0.1), ")"),
        fill_group = if_else(
          root_cause %in% c("Non-compliance", "House not visited", "House not revisited"),
          "Priority operational/behavioral issue",
          "Other missed-child driver"
        )
      ) %>%
      ggplot(aes(x = root_cause, y = missed_children, fill = fill_group)) +
      geom_col(width = 0.72) +
      geom_text(aes(label = label), hjust = -0.08, size = 4.4, fontface = "bold", color = dark_grey) +
      coord_flip() +
      scale_y_continuous(labels = comma, expand = expansion(mult = c(0, 0.20))) +
      scale_fill_manual(values = c(
        "Priority operational/behavioral issue" = alert_red,
        "Other missed-child driver" = who_blue
      )) +
      labs(
        title = ifelse(is_single_country, 
                       glue("Why children are missed in {analysis_name}"),
                       "Why children are missed across AFRO countries"),
        subtitle = "Root-cause decomposition from Independent Monitoring",
        x = NULL, y = "Missed children",
        caption = "Advocacy use: tailor corrective action by dominant cause"
      ) + theme_un_advocacy()
    
    root_filename <- ifelse(is_single_country,
                            paste0("01_", analysis_name, "_root_causes_missed_children.png"),
                            "01_AFRO_root_causes_missed_children.png")
    ggsave(file.path(plot_dir, root_filename), p_root, width = 13, height = 8, dpi = 300)
  }
  
  # PRIORITY DISTRICTS PLOT
  if (nrow(top_30_priority) > 0) {
    p_priority <- top_30_priority %>%
      mutate(
        label = if(is_single_country) str_wrap(district, width = 34) else str_wrap(district_uid, width = 34),
        priority_simple = case_when(
          str_detect(priority_class, "Priority 1") ~ "Priority 1",
          str_detect(priority_class, "Priority 2") ~ "Priority 2",
          TRUE ~ "Priority 3"
        )
      ) %>%
      ggplot(aes(x = reorder(label, mean_risk_score), y = mean_risk_score, fill = priority_simple)) +
      geom_col(width = 0.72) +
      geom_text(aes(label = round(mean_risk_score, 1)), hjust = -0.15, size = 3.8, fontface = "bold", color = dark_grey) +
      coord_flip() +
      scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
      scale_fill_manual(values = c("Priority 1" = alert_red, "Priority 2" = warning_orange, "Priority 3" = who_blue)) +
      labs(
        title = ifelse(is_single_country,
                       glue("Priority districts in {analysis_name} requiring action"),
                       "Priority districts requiring regional action"),
        subtitle = "Ranked by IM risk score and operational vulnerability",
        x = NULL, y = "Mean risk score",
        caption = ifelse(is_single_country,
                         "Use this list for national prioritization and partner support",
                         "Use this list for AFRO prioritization, partner support and accountability tracking")
      ) + theme_un_advocacy(base_size = 13)
    
    priority_filename <- ifelse(is_single_country,
                                paste0("02_", analysis_name, "_top_priority_districts.png"),
                                "02_AFRO_top_priority_districts.png")
    ggsave(file.path(plot_dir, priority_filename), p_priority, width = 14, height = 10, dpi = 300)
  }
  
  # ADMIN LEVEL SUMMARY PLOT (Provinces for single country, Countries for regional)
  if (is_single_country) {
    if (nrow(country_summary) > 0) {
      p_admin <- country_summary %>%
        mutate(
          province = fct_reorder(province, mean_risk_score),
          risk_group = case_when(
            mean_risk_score >= 75 ~ "Critical",
            mean_risk_score >= 50 ~ "High",
            mean_risk_score >= 25 ~ "Moderate",
            TRUE ~ "Low"
          )
        ) %>%
        ggplot(aes(x = province, y = mean_risk_score, fill = risk_group)) +
        geom_col(width = 0.72) +
        geom_text(aes(label = paste0("Missed: ", comma(total_missed))), hjust = -0.05, size = 4, fontface = "bold", color = dark_grey) +
        coord_flip() +
        scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
        scale_fill_manual(values = c("Critical" = alert_red, "High" = warning_orange, "Moderate" = who_blue, "Low" = green_ok)) +
        labs(
          title = glue("Province-level IM risk profile in {analysis_name}"),
          subtitle = "Risk score with missed-child burden for national targeting",
          x = NULL, y = "Mean risk score",
          caption = "Focus provinces with both high risk score and high missed-child burden"
        ) + theme_un_advocacy()
      
      admin_filename <- paste0("03_", analysis_name, "_province_risk_profile.png")
      ggsave(file.path(plot_dir, admin_filename), p_admin, width = 13, height = 8, dpi = 300)
    }
  } else {
    if (nrow(country_summary) > 0) {
      p_country <- country_summary %>%
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
        geom_text(aes(label = paste0("Missed: ", comma(total_missed))), hjust = -0.05, size = 4, fontface = "bold", color = dark_grey) +
        coord_flip() +
        scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
        scale_fill_manual(values = c("Critical" = alert_red, "High" = warning_orange, "Moderate" = who_blue, "Low" = green_ok)) +
        labs(
          title = "Country-level IM risk profile",
          subtitle = "Risk score with missed-child burden for regional targeting",
          x = NULL, y = "Mean risk score",
          caption = "Focus countries with both high risk score and high missed-child burden"
        ) + theme_un_advocacy()
      
      ggsave(file.path(plot_dir, "03_AFRO_country_risk_profile.png"), p_country, width = 13, height = 8, dpi = 300)
    }
  }
  
  # SOCIAL MOBILIZATION PLOT
  sm_plot_data <- sm_summary %>% filter(!is.na(cv), !is.na(awareness_rate))
  
  if (nrow(sm_plot_data) > 0) {
    p_sm <- sm_plot_data %>%
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
        title = ifelse(is_single_country,
                       glue("Social mobilisation awareness vs vaccination coverage in {analysis_name}"),
                       "Social mobilisation awareness vs vaccination coverage"),
        subtitle = "Each bubble is a unique district; bubble size reflects missed children",
        x = "Caregiver awareness rate", y = "Vaccination coverage",
        caption = "Advocacy message: low-awareness districts require intensified pre-campaign mobilisation"
      ) + theme_un_advocacy(legend_position = "bottom") +
      guides(fill = guide_legend(nrow = 2, byrow = TRUE), size = guide_legend(nrow = 1, title = "Missed children"))
    
    sm_filename <- ifelse(is_single_country,
                          paste0("04_", analysis_name, "_SM_awareness_vs_coverage.png"),
                          "04_AFRO_SM_awareness_vs_coverage.png")
    ggsave(file.path(plot_dir, sm_filename), p_sm, width = 12, height = 10, dpi = 300)
  }

  # ── CV HEATMAP: Area × Campaign Round ────────────────────────────────────────
  cat("Generating CV heatmap...\n")

  # Choose X-axis: round number if meaningful, else quarter
  if ("roundnumber" %in% names(filtered_risk_data) &&
      !all(is.na(filtered_risk_data$roundnumber)) &&
      n_distinct(filtered_risk_data$roundnumber, na.rm = TRUE) > 1) {
    filtered_risk_data <- filtered_risk_data %>%
      mutate(heat_x = as.character(roundnumber))
    x_lab_heat <- "Campaign Round"
  } else {
    filtered_risk_data <- filtered_risk_data %>%
      mutate(heat_x = format(floor_date(campaign_date, "quarter"), "%Y-Q%q"))
    x_lab_heat <- "Quarter"
  }

  # Y-axis: province for single-country, country for regional
  y_var_heat <- if (is_single_country) "province" else "country"
  y_lab_heat <- if (is_single_country) "Province" else "Country"

  heat_data <- filtered_risk_data %>%
    filter(!is.na(.data[[y_var_heat]]), !is.na(heat_x)) %>%
    group_by(y_area = .data[[y_var_heat]], x_round = heat_x) %>%
    summarise(
      cv = sum(as.numeric(u5_fm), na.rm = TRUE) /
           pmax(sum(as.numeric(u5_present), na.rm = TRUE), 1),
      .groups = "drop"
    ) %>%
    mutate(cv = pmin(pmax(cv, 0), 1))

  if (nrow(heat_data) > 0) {
    # Order Y so worst performers sit at the top (lowest mean CV first = bottom in coord_flip reversed)
    y_order <- heat_data %>%
      group_by(y_area) %>%
      summarise(m = mean(cv, na.rm = TRUE), .groups = "drop") %>%
      arrange(m) %>%
      pull(y_area)

    x_order <- sort(unique(heat_data$x_round))

    heat_data <- heat_data %>%
      mutate(
        y_area   = factor(y_area,   levels = y_order),
        x_round  = factor(x_round,  levels = x_order),
        cv_label = paste0(round(cv * 100, 1), "%"),
        txt_col  = if_else(cv < 0.85, "white", "black")
      )

    p_heatmap <- ggplot(heat_data, aes(x = x_round, y = y_area, fill = cv)) +
      geom_tile(color = "white", linewidth = 0.7) +
      geom_text(aes(label = cv_label, color = txt_col), size = 3.1, fontface = "bold") +
      scale_color_identity() +
      scale_fill_gradientn(
        colors = c("#C0392B", "#E8730A", "#F1C40F", "#27AE60", "#1A7A44"),
        values = scales::rescale(c(0, 0.50, 0.80, 0.90, 1)),
        limits = c(0, 1),
        labels = percent_format(accuracy = 1),
        name   = "Coverage (CV)",
        guide  = guide_colorbar(barwidth = 1, barheight = 8)
      ) +
      scale_x_discrete(guide = guide_axis(angle = -35)) +
      labs(
        title    = ifelse(is_single_country,
                          glue("CV heatmap: Province × Campaign Round — {analysis_name}"),
                          "CV heatmap: Country × Campaign Round"),
        subtitle = "Coverage rate (CV) by geographic area and campaign round — red = <80%, green = ≥90%",
        x        = x_lab_heat,
        y        = y_lab_heat,
        caption  = "Source: AFRO Independent Monitoring Repository"
      ) +
      theme_un_advocacy(legend_position = "right") +
      theme(
        panel.grid   = element_blank(),
        axis.text.y  = element_text(size = 10),
        axis.text.x  = element_text(size = 9)
      )

    heat_filename <- ifelse(is_single_country,
                            paste0("05_", analysis_name, "_cv_heatmap.png"),
                            "05_AFRO_cv_heatmap.png")
    ggsave(file.path(plot_dir, heat_filename),
           p_heatmap,
           width  = 14,
           height = max(6, min(14, nlevels(heat_data$y_area) * 0.55 + 3)),
           dpi    = 300)
    cat("  -> Saved:", heat_filename, "\n")
  } else {
    cat("  -> Heatmap skipped: insufficient data\n")
  }

  # RECOMMENDATION CARD
  if (is_single_country) {
    recommendation_card <- ggplot() +
      annotate("rect", xmin = 0, xmax = 10, ymin = 0, ymax = 7, fill = "white", color = NA) +
      annotate("rect", xmin = 0, xmax = 10, ymin = 6.1, ymax = 7, fill = dark_blue, color = NA) +
      annotate("text", x = 0.4, y = 6.55, hjust = 0,
               label = glue("Priority national advocacy actions for {analysis_name}"),
               color = "white", size = 7, fontface = "bold") +
      annotate("text", x = 0.6, y = 5.3, hjust = 0,
               label = "1. Prioritize high-risk provinces and districts for immediate corrective action",
               color = dark_blue, size = 4.8, fontface = "bold") +
      annotate("text", x = 0.9, y = 4.8, hjust = 0,
               label = "Use IM risk ranking to focus supervision, partner support and rapid action.",
               color = dark_grey, size = 4.1) +
      annotate("text", x = 0.6, y = 4.0, hjust = 0,
               label = "2. Strengthen revisit tracking and supervisor accountability",
               color = dark_blue, size = 4.8, fontface = "bold") +
      annotate("text", x = 0.9, y = 3.5, hjust = 0,
               label = "\"House not revisited\" should become a campaign accountability indicator.",
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
      xlim(0, 10) + ylim(0, 7) + theme_void()
    
    rec_filename <- paste0("06_", analysis_name, "_advocacy_recommendation_card.png")
  } else {
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
      xlim(0, 10) + ylim(0, 7) + theme_void()
    
    rec_filename <- "06_AFRO_advocacy_recommendation_card.png"
  }
  
  ggsave(file.path(plot_dir, rec_filename), recommendation_card, width = 14, height = 8, dpi = 300)
  
  # EXPORT ALL CSV FILES
  prefix <- ifelse(is_single_country, analysis_name, "AFRO")
  write_csv(executive_snapshot, file.path(table_dir, paste0("01_", prefix, "_executive_snapshot.csv")))
  write_csv(root_cause_summary, file.path(table_dir, paste0("02_", prefix, "_root_cause.csv")))
  write_csv(sm_summary, file.path(table_dir, paste0("04_", prefix, "_social_mobilisation_summary.csv")))
  write_csv(priority_districts, file.path(table_dir, paste0("06_", prefix, "_priority_districts.csv")))
  write_csv(top_30_priority, file.path(table_dir, paste0("07_", prefix, "_top_30_priority.csv")))
  write_csv(province_summary, file.path(table_dir, paste0("09_", prefix, "_province_summary.csv")))
  write_csv(cv95_summary, file.path(table_dir, paste0("11_", prefix, "_CV95_long.csv")))
  write_csv(cv95_wide, file.path(table_dir, paste0("12_", prefix, "_CV95_wide.csv")))
  
  if (!is_single_country) {
    write_csv(country_summary, file.path(table_dir, "08_AFRO_country_summary.csv"))
  }
  
  # CREATE EXCEL WORKBOOK
  wb <- createWorkbook()
  
  if (is_single_country) {
    sheet_list <- list(
      "Executive Snapshot" = executive_snapshot,
      "Root Cause" = root_cause_summary,
      "Province Summary" = country_summary,
      "District Summary" = province_summary,
      "SM Summary" = sm_summary,
      "Priority Districts" = priority_districts,
      "Top 30 Priority" = top_30_priority,
      "CV95 Long" = cv95_summary,
      "CV95 Wide" = cv95_wide
    )
  } else {
    sheet_list <- list(
      "Executive Snapshot" = executive_snapshot,
      "Root Cause" = root_cause_summary,
      "Country Summary" = country_summary,
      "Province Summary" = province_summary,
      "SM Summary" = sm_summary,
      "Priority Districts" = priority_districts,
      "Top 30 Priority" = top_30_priority,
      "CV95 Long" = cv95_summary,
      "CV95 Wide" = cv95_wide
    )
  }
  
  for (sheet_name in names(sheet_list)) {
    addWorksheet(wb, sheet_name)
    writeData(wb, sheet_name, sheet_list[[sheet_name]])
    freezePane(wb, sheet_name, firstRow = TRUE)
    setColWidths(wb, sheet_name, cols = 1:50, widths = "auto")
  }
  
  excel_file <- file.path(output_dir, paste0(prefix, "_IM_Intelligence_Report", 
                                             ifelse(is.null(output_suffix), "", paste0("_", output_suffix)), ".xlsx"))
  saveWorkbook(wb, excel_file, overwrite = TRUE)
  
  # CREATE WORD BRIEF
  brief <- read_docx()
  
  brief <- brief %>%
    body_add_par(paste(prefix, "Independent Monitoring Intelligence Brief"), style = "heading 1") %>%
    body_add_par(ifelse(is_single_country,
                        paste("Prepared for", analysis_name, "national programme intelligence and advocacy."),
                        "Prepared for regional programme intelligence and advocacy."),
                 style = "Normal") %>%
    body_add_par("1. Executive Snapshot", style = "heading 2") %>%
    body_add_flextable(flextable(executive_snapshot) %>% autofit())
  
  if (exists("ft_cv95") && nrow(cv95_wide) > 0) {
    brief <- brief %>%
      body_add_par("2. Proportion of Districts by CV Performance", style = "heading 2") %>%
      body_add_flextable(ft_cv95)
  }
  
  brief <- brief %>%
    body_add_par("3. Root Causes of Missed Children", style = "heading 2") %>%
    body_add_flextable(flextable(root_cause_summary) %>% autofit()) %>%
    body_add_par("4. Top Priority Districts", style = "heading 2") %>%
    body_add_flextable(flextable(head(top_30_priority, 20)) %>% autofit())
  
  word_file <- file.path(output_dir, paste0(prefix, "_IM_Intelligence_Brief",
                                            ifelse(is.null(output_suffix), "", paste0("_", output_suffix)), ".docx"))
  print(brief, target = word_file)
  
  # FINAL SUMMARY
  cat("\n")
  cat("============================================================\n")
  cat(prefix, "IM INTELLIGENCE REPORT COMPLETED\n")
  cat("============================================================\n")
  cat("Analysis scope:", ifelse(is_single_country, "Single country", "Regional"), "\n")
  cat("Output folder:", output_dir, "\n")
  cat("Excel:", excel_file, "\n")
  cat("Word brief:", word_file, "\n")
  cat("Plots saved in:", plot_dir, "\n")
  cat("Tables saved in:", table_dir, "\n")
  cat("Unique districts analysed:", n_distinct(filtered_risk_data$district_uid), "\n")
  cat("Total missed children:", comma(executive_snapshot$total_missed_children), "\n")
  cat("============================================================\n")
  
  invisible(list(
    data = filtered_risk_data,
    analysis_scope = ifelse(is_single_country, "country", "regional"),
    executive_snapshot = executive_snapshot,
    root_cause = root_cause_summary,
    country_summary = country_summary,
    province_summary = province_summary,
    priority_districts = priority_districts,
    cv95_summary = cv95_summary,
    excel_file = excel_file,
    word_file = word_file,
    output_dir = output_dir
  ))
}

# Run for Malawi
generate_afro_im_intelligence_report(
  last_n_months = 6,
  country = c("MALAWI"),
  output_suffix = "malawi_analysis"
)