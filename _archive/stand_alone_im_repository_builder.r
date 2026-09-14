#!/usr/bin/env Rscript
# ============================================================
# Regional IM Repository Builder - STANDALONE VERSION
# ============================================================
# 
# PURPOSE:
#   Processes raw Independent Monitoring (IM) data files and builds
#   a harmonized regional repository for polio campaign analysis.
#
# INPUT:
#   - Raw IM data files (supports: .parquet, .rds, .qs, .csv, .xlsx, .feather)
#   - Lookup file for date harmonization (optional)
#
# OUTPUT:
#   - Regional_IM_repository.csv / .rds / .parquet (main data)
#   - Regional_IM_repository_QC.csv / .rds / .parquet (quality control)
#   - Regional_IM_repository_METADATA.xlsx (documentation)
#   - IM_processing_summary.csv (summary statistics)
#
# USAGE:
#   Option 1: Source in R/RStudio
#     source("regional_im_repository_builder.R")
#   
#   Option 2: Run from command line
#     Rscript regional_im_repository_builder.R
#
#   Option 3: Run with custom paths
#     Rscript regional_im_repository_builder.R --input "path/to/raw" --output "path/to/final"
#
# ============================================================

# ============================================================
# USER CONFIGURATION - EDIT THESE PATHS AS NEEDED
# ============================================================

# Set your working directory containing the data folders
# Option 1: Set manually
BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"

# Option 2: Auto-detect (uncomment if script is in the workflow folder)
# script_dir <- dirname(sys.frame(1)$ofile)
# if (exists("script_dir") && nchar(script_dir) > 0) {
#   BASE_DIR <- normalizePath(file.path(script_dir, ".."))
# }

# Input/Output folders (relative to BASE_DIR or absolute paths)
INPUT_FOLDER <- file.path(BASE_DIR, "data/raw")      # Where raw data files are
OUTPUT_FOLDER <- file.path(BASE_DIR, "data/final")   # Where outputs will go
QC_FOLDER <- file.path(BASE_DIR, "data/processed/qc") # Where QC files will go
LOOKUP_FOLDER <- file.path(BASE_DIR, "data/lookup")   # Where lookup files are

# Lookup file for date harmonization (optional - set to NULL to skip)
LOOKUP_FILE <- file.path(LOOKUP_FOLDER, "lookup.xlsx")

# ============================================================
# DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# ============================================================

# Load required packages with automatic installation
required_packages <- c(
  "tidyverse", "lubridate", "readxl", "readr", "tools", 
  "tibble", "qs", "stringr", "arrow", "data.table", 
  "openxlsx", "janitor"
)

# Function to install missing packages
install_if_missing <- function(pkg) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat(sprintf("Installing missing package: %s\n", pkg))
    install.packages(pkg, repos = "https://cloud.r-project.org/")
    library(pkg, character.only = TRUE)
  }
}

# Load/install all required packages
cat("Loading required packages...\n")
for (pkg in required_packages) {
  install_if_missing(pkg)
}
cat("All packages loaded successfully!\n")

# Create output directories if they don't exist
dir.create(OUTPUT_FOLDER, showWarnings = FALSE, recursive = TRUE)
dir.create(QC_FOLDER, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(OUTPUT_FOLDER, "country"), showWarnings = FALSE, recursive = TRUE)

# Set output file paths
regional_repository_file <- file.path(OUTPUT_FOLDER, "Regional_IM_repository.csv")
regional_qc_repository_file <- file.path(OUTPUT_FOLDER, "Regional_IM_repository_QC.csv")
summary_file <- file.path(OUTPUT_FOLDER, "IM_processing_summary.csv")

cat("\n============================================================\n")
cat("REGIONAL IM REPOSITORY BUILDER\n")
cat("============================================================\n")
cat(sprintf("Input folder:  %s\n", INPUT_FOLDER))
cat(sprintf("Output folder: %s\n", OUTPUT_FOLDER))
cat(sprintf("QC folder:     %s\n", QC_FOLDER))
cat(sprintf("Lookup file:   %s\n", ifelse(file.exists(LOOKUP_FILE), LOOKUP_FILE, "Not found (will use fallback)")))
cat("============================================================\n\n")

# ============================================================
# CONSTANTS
# ============================================================
ALGERIA_IM_FORM_ID <- "8587"
NIGERIA_IM_FORM_ID <- "7178"

# ============================================================
# HELPER FUNCTIONS
# ============================================================

parse_mixed_dates <- function(x) {
  x <- as.character(x)
  suppressWarnings(
    dplyr::coalesce(
      lubridate::ymd(x),
      lubridate::dmy(x),
      lubridate::mdy(x),
      lubridate::ymd_hms(x),
      lubridate::dmy_hms(x),
      lubridate::mdy_hms(x)
    )
  )
}

clean_numeric <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  x[x %in% c("", " ", "n/a", "NA", "NaN", "null", "NULL")] <- "0"
  suppressWarnings(as.numeric(x))
}

SPECIAL_MISSING_CODES <- c(-999, -998, -997, -996, -995, 999, 998, 997, 996)

clean_special_missing <- function(x, negative_to_na = TRUE) {
  x <- suppressWarnings(as.numeric(as.character(x)))
  x[x %in% SPECIAL_MISSING_CODES] <- NA_real_
  if (negative_to_na) x[x < 0] <- NA_real_
  x
}

safe_numeric_zero <- function(x) {
  x <- clean_special_missing(x, negative_to_na = TRUE)
  x[is.na(x)] <- 0
  x
}

safe_row_sum <- function(df, cols) {
  cols <- intersect(cols, names(df))
  if (length(cols) == 0) return(rep(0, nrow(df)))
  temp <- df[, cols, drop = FALSE]
  temp[] <- lapply(temp, safe_numeric_zero)
  rowSums(temp, na.rm = TRUE)
}

safe_pick_first <- function(df, candidates, default = 0) {
  candidates <- intersect(candidates, names(df))
  if (length(candidates) == 0) return(rep(default, nrow(df)))
  x <- clean_special_missing(df[[candidates[1]]], negative_to_na = TRUE)
  x[is.na(x)] <- default
  x
}

rename_repetitive_columns <- function(data) {
  pattern <- "^HH\\[\\d+\\]/HH/"
  new_columns <- sapply(colnames(data), function(col) {
    if (grepl(pattern, col)) gsub("HH/", "", col) else col
  })
  colnames(data) <- new_columns
  data
}

bind_rows_fill <- function(df_list) {
  df_list <- Filter(function(x) !is.null(x), df_list)
  if (length(df_list) == 0) return(tibble())
  
  all_cols <- unique(unlist(lapply(df_list, names)))
  
  prototypes <- list()
  for (col in all_cols) {
    for (df in df_list) {
      if (col %in% names(df)) {
        prototypes[[col]] <- df[[col]]
        break
      }
    }
  }
  
  df_list2 <- lapply(df_list, function(x) {
    missing <- setdiff(all_cols, names(x))
    
    if (length(missing) > 0) {
      for (m in missing) {
        proto <- prototypes[[m]]
        
        if (is.character(proto)) {
          x[[m]] <- rep(NA_character_, nrow(x))
        } else if (is.numeric(proto)) {
          x[[m]] <- rep(NA_real_, nrow(x))
        } else if (is.integer(proto)) {
          x[[m]] <- rep(NA_integer_, nrow(x))
        } else if (inherits(proto, "Date")) {
          x[[m]] <- as.Date(rep(NA_character_, nrow(x)))
        } else {
          x[[m]] <- rep(NA_character_, nrow(x))
        }
      }
    }
    
    x[, all_cols, drop = FALSE]
  })
  
  bind_rows(df_list2)
}

find_similar_column <- function(target_name, df, exact_first = TRUE) {
  cols <- names(df)
  
  if (exact_first && target_name %in% cols) {
    return(target_name)
  }
  
  target_norm <- tolower(target_name)
  target_norm <- gsub("[\\[\\]/ _-]", "", target_norm)
  
  cols_norm <- tolower(cols)
  cols_norm <- gsub("[\\[\\]/ _-]", "", cols_norm)
  
  idx <- which(cols_norm == target_norm)
  if (length(idx) > 0) return(cols[idx[1]])
  
  idx2 <- which(grepl(target_norm, cols_norm, fixed = TRUE))
  if (length(idx2) > 0) return(cols[idx2[1]])
  
  NA_character_
}

get_regex_cols <- function(df, pattern) {
  grep(pattern, names(df), value = TRUE)
}

build_hh_candidate_names <- function(hh_num, suffix) {
  c(
    sprintf("HH[%s]/%s", hh_num, suffix),
    sprintf("HH[%s]/group1/%s", hh_num, suffix),
    sprintf("HH[%s]/group2/%s", hh_num, suffix),
    sprintf("HH[%s]/group4/%s", hh_num, suffix),
    sprintf("HH[%s]/HH/%s", hh_num, suffix),
    sprintf("HH_%s_%s", hh_num, suffix),
    sprintf("HH%s_%s", hh_num, suffix)
  )
}

# ============================================================
# SOCIAL MOBILIZATION HELPERS
# ============================================================

normalize_sm_text <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- tolower(x)
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT", sub = "")
  x <- gsub("[,;/|]+", " ", x)
  x <- gsub("[[:space:]]+", " ", x)
  trimws(x)
}

extract_sm_from_text <- function(df, cols) {
  cols <- intersect(cols, names(df))
  n <- nrow(df)
  
  result <- matrix(0L, nrow = n, ncol = 19)
  colnames(result) <- c(
    "tv", "radio", "others", "hworker", "mob_vanpa", "town_crier",
    "volunteers", "com_infocentre", "community_leader", "religious_leader",
    "mobile_social_media", "h2h_mobilizer", "mourchidate", "mosque",
    "vaccinators", "sticker", "newspaper", "teachers_student", "iec_materials"
  )
  
  if (length(cols) == 0) {
    return(as_tibble(as.data.frame(result)))
  }
  
  txt <- apply(df[, cols, drop = FALSE], 1, function(x) {
    paste(normalize_sm_text(x), collapse = " ")
  })
  
  txt <- gsub("[[:space:]]+", " ", txt)
  txt <- trimws(txt)
  
  txt <- gsub(
    regex("\\b(oui|yes|non|no|0|1|00|nn|na|n/a|ras|personal|people|sociaux|other people|la sh|pas de probleme|bien passe|non informe)\\b", 
          ignore_case = TRUE),
    " ",
    txt
  )
  txt <- gsub("[[:space:]]+", " ", txt)
  txt <- trimws(txt)
  
  is_space_sep <- grepl("^[a-z_]+( [a-z_]+)*$", txt) & !grepl(" ", txt) & nchar(txt) < 500
  space_sep_idx <- which(is_space_sep)
  free_text_idx <- which(!is_space_sep)
  
  if (length(space_sep_idx) > 0) {
    for (idx in space_sep_idx) {
      tokens <- strsplit(txt[idx], " ")[[1]]
      for (token in tokens) {
        if (token %in% c("tv", "television", "télévision", "تلفاز", "التلفاز", "التلفزة")) {
          result[idx, "tv"] <- 1
        } else if (token %in% c("radio", "مذياع", "المذياع")) {
          result[idx, "radio"] <- 1
        } else if (token %in% c("others", "other", "autres", "autre", "اخر", "اخرون")) {
          result[idx, "others"] <- 1
        } else if (token %in% c("health_worker", "hworker", "agent de sante", "hopital", "hospital")) {
          result[idx, "hworker"] <- 1
        } else if (token %in% c("mob_vanpa", "van pa", "megaphone car", "haut parleur")) {
          result[idx, "mob_vanpa"] <- 1
        } else if (token %in% c("town_crier", "gong_gong", "crieur public")) {
          result[idx, "town_crier"] <- 1
        } else if (token %in% c("volunteers", "volunteer", "benevole")) {
          result[idx, "volunteers"] <- 1
        } else if (token %in% c("com_info_centre", "community information centre")) {
          result[idx, "com_infocentre"] <- 1
        } else if (token %in% c("community_leader", "community leader", "chef de quartier", "voisin")) {
          result[idx, "community_leader"] <- 1
        } else if (token %in% c("religious_leader", "religious leader", "imam")) {
          result[idx, "religious_leader"] <- 1
        } else if (token %in% c("mobilemessaging_socialmedia", "social media", "facebook", "whatsapp")) {
          result[idx, "mobile_social_media"] <- 1
        } else if (token %in% c("h2h_mobilizer", "house to house", "door to door")) {
          result[idx, "h2h_mobilizer"] <- 1
        } else if (token %in% c("mourchidate")) {
          result[idx, "mourchidate"] <- 1
        } else if (token %in% c("mosque", "mosquee", "masjid")) {
          result[idx, "mosque"] <- 1
        } else if (token %in% c("vaccinators", "vaccinator", "vaccinateurs")) {
          result[idx, "vaccinators"] <- 1
        } else if (token %in% c("sticker", "poster", "affiche")) {
          result[idx, "sticker"] <- 1
        } else if (token %in% c("newspaper")) {
          result[idx, "newspaper"] <- 1
        } else if (token %in% c("teachers_student", "school", "ecole", "école")) {
          result[idx, "teachers_student"] <- 1
        } else if (token %in% c("iec_materials")) {
          result[idx, "iec_materials"] <- 1
        }
      }
    }
  }
  
  if (length(free_text_idx) > 0) {
    txt_free <- txt[free_text_idx]
    
    result[free_text_idx, "tv"] <- as.integer(str_detect(txt_free, regex("\\btv\\b|television|télévision", ignore_case = TRUE)))
    result[free_text_idx, "radio"] <- as.integer(str_detect(txt_free, regex("\\bradio\\b", ignore_case = TRUE)))
    result[free_text_idx, "others"] <- as.integer(str_detect(txt_free, regex("\\bothers\\b|\\bother\\b|\\bautres\\b", ignore_case = TRUE)))
    result[free_text_idx, "hworker"] <- as.integer(str_detect(txt_free, regex("\\bhealth_worker\\b|\\bhworker\\b|health worker|agent de sante|hopital|hospital", ignore_case = TRUE)))
    result[free_text_idx, "mob_vanpa"] <- as.integer(str_detect(txt_free, regex("\\bmob_vanpa\\b|van pa|megaphone|haut parleur", ignore_case = TRUE)))
    result[free_text_idx, "town_crier"] <- as.integer(str_detect(txt_free, regex("\\btown_crier\\b|town crier|gong_gong|crieur public", ignore_case = TRUE)))
    result[free_text_idx, "volunteers"] <- as.integer(str_detect(txt_free, regex("\\bvolunteers\\b|volunteer|benevole", ignore_case = TRUE)))
    result[free_text_idx, "com_infocentre"] <- as.integer(str_detect(txt_free, regex("\\bcom_info_centre\\b|information centre", ignore_case = TRUE)))
    result[free_text_idx, "community_leader"] <- as.integer(str_detect(txt_free, regex("\\bcommunity_leader\\b|community leader|chef de quartier", ignore_case = TRUE)))
    result[free_text_idx, "religious_leader"] <- as.integer(str_detect(txt_free, regex("\\breligious_leader\\b|religious leader|imam|mosque", ignore_case = TRUE)))
    result[free_text_idx, "mobile_social_media"] <- as.integer(str_detect(txt_free, regex("\\bmobilemessaging_socialmedia\\b|social media|facebook|whatsapp", ignore_case = TRUE)))
    result[free_text_idx, "h2h_mobilizer"] <- as.integer(str_detect(txt_free, regex("\\bh2h_mobilizer\\b|house to house|door to door", ignore_case = TRUE)))
    result[free_text_idx, "mourchidate"] <- as.integer(str_detect(txt_free, regex("\\bmourchidate\\b", ignore_case = TRUE)))
    result[free_text_idx, "mosque"] <- as.integer(str_detect(txt_free, regex("\\bmosque\\b|mosquee|masjid", ignore_case = TRUE)))
    result[free_text_idx, "vaccinators"] <- as.integer(str_detect(txt_free, regex("\\bvaccinators\\b|vaccinator|vaccinateurs", ignore_case = TRUE)))
    result[free_text_idx, "sticker"] <- as.integer(str_detect(txt_free, regex("\\bsticker\\b|poster|affiche", ignore_case = TRUE)))
    result[free_text_idx, "newspaper"] <- as.integer(str_detect(txt_free, regex("\\bnewspaper\\b", ignore_case = TRUE)))
    result[free_text_idx, "teachers_student"] <- as.integer(str_detect(txt_free, regex("\\bteachers_student\\b|school|ecole|école", ignore_case = TRUE)))
    result[free_text_idx, "iec_materials"] <- as.integer(str_detect(txt_free, regex("\\biec_materials\\b|iec materials", ignore_case = TRUE)))
  }
  
  tibble(
    sm_info_tv_text = result[, "tv"],
    sm_info_radio_text = result[, "radio"],
    sm_info_others_text = result[, "others"],
    sm_info_hworker_text = result[, "hworker"],
    sm_info_mob_vanpa_text = result[, "mob_vanpa"],
    sm_info_town_crier_text = result[, "town_crier"],
    sm_info_volunteers_text = result[, "volunteers"],
    sm_info_com_infocentre_text = result[, "com_infocentre"],
    sm_info_community_leader_text = result[, "community_leader"],
    sm_info_religious_leader_text = result[, "religious_leader"],
    sm_info_mobile_social_media_text = result[, "mobile_social_media"],
    sm_info_h2h_mobilizer_text = result[, "h2h_mobilizer"],
    sm_info_mourchidate_text = result[, "mourchidate"],
    sm_info_mosque_text = result[, "mosque"],
    sm_info_vaccinators_text = result[, "vaccinators"],
    sm_info_sticker_text = result[, "sticker"],
    sm_info_newspaper_text = result[, "newspaper"],
    sm_info_teachers_student_text = result[, "teachers_student"],
    sm_info_iec_materials_text = result[, "iec_materials"]
  )
}

coalesce_max <- function(...) {
  vals <- list(...)
  vals <- vals[!vapply(vals, is.null, logical(1))]
  if (length(vals) == 0) return(NULL)
  do.call(pmax, c(vals, na.rm = TRUE))
}

# ============================================================
# INPUT READER - MULTI-FORMAT
# ============================================================

SUPPORTED_INPUT_EXTENSIONS <- c("rds", "qs", "csv", "txt", "tsv", "xlsx", "xls", "parquet", "feather", "arrow", "ipc")

read_csv_flexible <- function(input_file) {
  out <- tryCatch(
    readr::read_csv(input_file, show_col_types = FALSE, progress = FALSE) %>% as_tibble(),
    error = function(e) NULL
  )
  
  if (!is.null(out) && ncol(out) > 1) return(out)
  
  out2 <- tryCatch(
    readr::read_delim(input_file, delim = ";", show_col_types = FALSE, progress = FALSE) %>% as_tibble(),
    error = function(e) NULL
  )
  
  if (!is.null(out2)) return(out2)
  if (!is.null(out)) return(out)
  
  stop("Cannot read delimited file: ", basename(input_file))
}

read_input_data <- function(input_file) {
  ext <- tolower(tools::file_ext(input_file))
  
  if (is.na(ext) || ext == "") {
    stop("Input file has no extension: ", basename(input_file))
  }
  
  message("Reading file: ", basename(input_file), " [.", ext, "]")
  
  if (!ext %in% SUPPORTED_INPUT_EXTENSIONS) {
    stop("Unsupported file extension: .", ext, " for file: ", basename(input_file))
  }
  
  if (ext %in% c("csv", "txt")) {
    return(read_csv_flexible(input_file))
  }
  
  if (ext == "tsv") {
    return(readr::read_tsv(input_file, show_col_types = FALSE, progress = FALSE) %>% as_tibble())
  }
  
  if (ext %in% c("xlsx", "xls")) {
    return(readxl::read_excel(input_file) %>% as_tibble())
  }
  
  if (ext == "parquet") {
    return(arrow::read_parquet(input_file) %>% as_tibble())
  }
  
  if (ext %in% c("feather", "arrow", "ipc")) {
    return(arrow::read_feather(input_file) %>% as_tibble())
  }
  
  if (ext == "qs") {
    return(qs::qread(input_file) %>% as_tibble())
  }
  
  if (ext == "rds") {
    obj <- tryCatch(qs::qread(input_file), error = function(e) NULL)
    if (is.null(obj)) {
      obj <- tryCatch(readRDS(input_file), error = function(e) {
        stop("Cannot read file: ", basename(input_file), " - not valid QS or RDS format")
      })
    }
    return(as_tibble(obj))
  }
  
  stop("Unsupported file extension: .", ext, " for file: ", basename(input_file))
}

# ============================================================
# STANDARD COLUMN DEFINITIONS
# ============================================================

required_columns <- c(
  "Country", "Region", "District", "Response", "roundNumber",
  "Type_Monitoring", "date_monitored", "HH_count", "Total_U5_Present",
  "TotalFM", "sum_missed_children", "Total_Absent", "Total_refusal"
)

hh_patterns_standard <- c(
  "Total_U5_Present_HH", "U5_Vac_FM_HH", "Tot_child_Absent_HH",
  "Tot_child_NC_HH", "Tot_child_NotVisited_HH", "Tot_child_NotRevisited",
  "Tot_child_Asleep_HH", "Tot_child_VaccinatedRoutine", "Tot_child_Others_HH",
  "Parent_Caregive_Inform_HH"
)

hh_patterns_algeria <- c(
  "Total_U6_Present_HH", "U6_Vac_FM_HH", "Tot_child_Absent_HH",
  "Tot_child_NC_HH", "Tot_child_NotVisited_HH", "Tot_child_NotRevisited",
  "Tot_child_Asleep_HH", "Tot_child_VaccinatedRoutine", "Tot_child_Others_HH",
  "Parent_Caregive_Inform_HH"
)

absence_total_candidates <- list(
  r_abs_play_areas    = c("Tot_child_Abs_Play_areas_T"),
  r_abs_market        = c("Tot_child_Abs_Market_T"),
  r_abs_school        = c("Tot_child_Abs_School_T"),
  r_abs_farm          = c("Tot_child_Abs_Farm_T"),
  r_abs_social_event  = c("Tot_child_Abs_SocialEvent"),
  r_abs_travelling    = c("Sum_child_Abs_Travelling"),
  r_abs_parent_absent = c("Sum_child_Abs_Parent_Absent"),
  r_abs_other_detail  = c("Tot_child_Abs_Other_T")
)

nc_total_candidates <- list(
  r_nc_religious_beliefs = c("Tot_child_NC_Religious_beliefs_T"),
  r_nc_side_effects      = c("Tot_child_NC_sideEffects"),
  r_nc_too_many_doses    = c("Sum_Too_many_doses"),
  r_nc_child_sick        = c("Sum_Child_sick", "Tot_child_NC_ChildSick_T"),
  r_nc_covid             = c("Sum_NC_COVID"),
  r_nc_other_detail      = c("Sum_NC_Others", "Tot_child_NC_Others_T")
)

algeria_abs_hh_patterns <- list(
  r_abs_sick_hh       = "^HH\\[[0-9]+\\]/group2/Tot_child_Abs_Sick$",
  r_abs_school_hh     = "^HH\\[[0-9]+\\]/group2/Tot_child_Abs_School$",
  r_abs_play_hh       = "^HH\\[[0-9]+\\]/group2/Tot_child_Abs_Play_areas$",
  r_abs_social_hh     = "^HH\\[[0-9]+\\]/group2/Tot_child_Abs_Social_event$",
  r_abs_travel_hh     = "^HH\\[[0-9]+\\]/group2/Tot_child_Abs_Travelling$",
  r_abs_other_hh      = "^HH\\[[0-9]+\\]/group2/Other_Reason_Absent$"
)

algeria_nc_hh_patterns <- list(
  r_nc_child_sick_hh  = "^HH\\[[0-9]+\\]/group4/Tot_child_NC_Child_was_sick$",
  r_nc_not_decided_hh = "^HH\\[[0-9]+\\]/group4/Tot_child_NC_pas_decide$",
  r_nc_polio_free_hh  = "^HH\\[[0-9]+\\]/group4/Tot_child_NC_PolioFree$",
  r_nc_nopv_hh        = "^HH\\[[0-9]+\\]/group4/Tot_child_NC_nOPV$",
  r_nc_other_hh       = "^HH\\[[0-9]+\\]/group4/Tot_child_NC_Other$"
)

sm_count_candidates <- list(
  sm_info_tv                    = c("SourceInfo_TV_count"),
  sm_info_radio                 = c("SourceInfo_Radio_count"),
  sm_info_others                = c("SourceInfo_Others_count"),
  sm_info_hworker               = c("SourceInfo_Hworker_count"),
  sm_info_mob_vanpa             = c("SourceInfo_Mob_VanPA_count"),
  sm_info_town_crier            = c("SourceInfo_Town_Crier_count"),
  sm_info_volunteers            = c("SourceInfo_Volunteers_count"),
  sm_info_com_infocentre        = c("SourceInfo_Com_Infocentre_count"),
  sm_info_community_leader      = c("SourceInfo_Community_leader_count"),
  sm_info_religious_leader      = c("SourceInfo_Religious_leader_count"),
  sm_info_mobile_social_media   = c("SourceInfo_MobileMessaging_SocialMedia_count")
)

standard_sm_hh_patterns <- list(
  sm_info_tv_hh                  = "^HH\\[[0-9]+\\]/HH/SourceInfo_TV$",
  sm_info_radio_hh               = "^HH\\[[0-9]+\\]/HH/SourceInfo_Radio$",
  sm_info_others_hh              = "^HH\\[[0-9]+\\]/HH/SourceInfo_Others$",
  sm_info_hworker_hh             = "^HH\\[[0-9]+\\]/HH/SourceInfo_Hworker$",
  sm_info_mob_vanpa_hh           = "^HH\\[[0-9]+\\]/HH/SourceInfo_Mob_VanPA$",
  sm_info_town_crier_hh          = "^HH\\[[0-9]+\\]/HH/SourceInfo_Town_Crier$",
  sm_info_volunteers_hh          = "^HH\\[[0-9]+\\]/HH/SourceInfo_Volunteers$",
  sm_info_com_infocentre_hh      = "^HH\\[[0-9]+\\]/HH/SourceInfo_Com_Infocentre$",
  sm_info_community_leader_hh    = "^HH\\[[0-9]+\\]/HH/SourceInfo_Community_leader$",
  sm_info_religious_leader_hh    = "^HH\\[[0-9]+\\]/HH/SourceInfo_Religious_leader$",
  sm_info_mobile_social_media_hh = "^HH\\[[0-9]+\\]/HH/SourceInfo_MobileMessaging_SocialMedia$",
  sm_info_other_text_hh          = "^HH\\[[0-9]+\\]/HH/Other_Source_Info$"
)

algeria_sm_hh_patterns <- list(
  sm_info_radio_hh         = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH/Radio$",
  sm_info_mourchidate_hh   = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH/Mourchidate$",
  sm_info_mosque_hh        = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH/Mosque$",
  sm_info_vaccinators_hh   = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH/Vaccinators$",
  sm_info_h2h_mobilizer_hh = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH/H2H_Mobilizer$",
  sm_info_sticker_hh       = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH/Sticker$",
  sm_info_others_hh        = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH/Others$",
  sm_info_other_text_hh    = "^HH\\[[0-9]+\\]/Other_Source_Info$"
)

sm_text_patterns <- list(
  sm_source_text_hh  = "^HH\\[[0-9]+\\]/HH/Source_Info_SIA_HH$",
  sm_other_text_hh   = "^HH\\[[0-9]+\\]/HH/Other_Source_Info$",
  sm_source_text_alg = "^HH\\[[0-9]+\\]/Source_Info_SIA_HH$",
  sm_other_text_alg  = "^HH\\[[0-9]+\\]/Other_Source_Info$"
)

# ============================================================
# PREPAREDNESS LOOKUP (OPTIONAL)
# ============================================================

load_preparedness_lookup <- function(preparedness_file) {
  if (!file.exists(preparedness_file)) {
    message("Lookup file not found: ", preparedness_file)
    message("Continuing without date harmonization.")
    return(NULL)
  }
  
  date <- read_excel(preparedness_file)
  
  date <- date %>%
    mutate(`Round Number` = case_when(
      `Round Number` == "Round 0" ~ "Rnd0",
      `Round Number` == "Round 1" ~ "Rnd1",
      `Round Number` == "Round 2" ~ "Rnd2",
      `Round Number` == "Round 3" ~ "Rnd3",
      `Round Number` == "Round 4" ~ "Rnd4",
      `Round Number` == "Round 5" ~ "Rnd5",
      `Round Number` == "Round 6" ~ "Rnd6",
      TRUE ~ `Round Number`
    ))
  
  prep_data <- date %>%
    rename(
      Response = `OBR Name`,
      Vaccine.type = Vaccines,
      roundNumber = `Round Number`
    ) %>%
    mutate(
      round_start_date = as_date(`Round Start Date`),
      round_start_date = case_when(
        Country == "ALGERIA" & Response == "ALG-2024-01-01_nOPV" & roundNumber == "Rnd1" ~ as_date("2024-02-18"),
        TRUE ~ round_start_date
      ),
      start_date = round_start_date + 4,
      end_date = as_date(start_date) + 1
    ) %>%
    select(Response, Vaccine.type, roundNumber, round_start_date, start_date, end_date)
  
  as_tibble(prep_data) %>%
    mutate(
      start_date = as_date(start_date),
      end_date = as_date(end_date),
      round_start_date = as_date(round_start_date)
    )
}

lookup_table <- load_preparedness_lookup(LOOKUP_FILE)
if (is.null(lookup_table)) {
  lookup_table <- tibble(
    Response = character(),
    Vaccine.type = character(),
    roundNumber = character(),
    round_start_date = as.Date(character()),
    start_date = as.Date(character()),
    end_date = as.Date(character())
  )
}

# ============================================================
# TRANSFORMATION FUNCTIONS
# ============================================================

apply_country_specific_transformations <- function(data, file_name) {
  if (startsWith(file_name, "3550") || startsWith(file_name, "3583")) {
    data <- data %>% mutate(Country = "GHA")
  }
  
  if (startsWith(file_name, "8834")) {
    data <- data %>% mutate(Region = District)
  }
  
  if (startsWith(file_name, "4351")) {
    if ("district" %in% names(data)) {
      data <- data %>% mutate(District = district)
    }
  }
  
  data
}

select_columns_dynamically <- function(df, required_cols, hh_patterns, hh_count = 10) {
  selected_cols <- c()
  
  for (col in required_cols) {
    matched_col <- find_similar_column(col, df)
    if (!is.na(matched_col)) selected_cols <- c(selected_cols, matched_col)
  }
  
  for (hh_num in 1:hh_count) {
    for (pattern in hh_patterns) {
      candidates <- build_hh_candidate_names(hh_num, pattern)
      for (cand in candidates) {
        matched_col <- find_similar_column(cand, df, exact_first = TRUE)
        if (!is.na(matched_col)) {
          selected_cols <- c(selected_cols, matched_col)
          break
        }
      }
    }
  }
  
  detailed_cols <- unique(c(
    unlist(absence_total_candidates),
    unlist(nc_total_candidates),
    unlist(sm_count_candidates),
    "Tot_child_NC_NotDecide_T",
    "Tot_child_NC_PolioFREE_T",
    "Tot_child_NC_nOPV_T",
    "Tot_child_NC_ChildSick_T",
    "Tot_child_NC_Others_T",
    "Tot_child_Abs_Sick_T"
  ))
  
  selected_cols <- unique(c(selected_cols, intersect(detailed_cols, names(df))))
  
  for (p in c(
    unlist(algeria_abs_hh_patterns),
    unlist(algeria_nc_hh_patterns),
    unlist(algeria_sm_hh_patterns),
    unlist(standard_sm_hh_patterns),
    unlist(sm_text_patterns)
  )) {
    selected_cols <- unique(c(selected_cols, grep(p, names(df), value = TRUE)))
  }
  
  unique(selected_cols)
}

safe_filter_data <- function(df) {
  result <- df
  
  if ("Type_Monitoring" %in% names(result)) {
    result <- result %>% filter(Type_Monitoring == "EndProcess")
  }
  
  if ("Response" %in% names(result)) {
    result <- result %>% filter(!is.na(Response), Response != "", Response != "n/a", Response != "NA")
  }
  
  if ("roundNumber" %in% names(result)) {
    result <- result %>% filter(!is.na(roundNumber), roundNumber != "", roundNumber != "n/a", roundNumber != "NA")
  }
  
  if ("Total_U5_Present" %in% names(result)) {
    result <- result %>% filter(is.na(Total_U5_Present) | Total_U5_Present != "n/a")
  }
  
  if ("TotalFM" %in% names(result)) {
    result <- result %>% filter(!is.na(TotalFM))
  }
  
  result
}

# ============================================================
# CORE PROCESSING FUNCTION
# ============================================================

process_im_file <- function(input_file, output_folder, qc_output_folder, lookup_table) {
  file_name <- tools::file_path_sans_ext(basename(input_file))
  output_file <- file.path(output_folder, paste0(file_name, ".csv"))
  qc_output_file <- file.path(qc_output_folder, paste0(file_name, "_QC.csv"))
  
  message("\n============================================================")
  message("Processing file: ", basename(input_file))
  message("============================================================")
  
  # Special handling for Nigeria form 7178
  if (file_name == NIGERIA_IM_FORM_ID) {
    message("Processing Nigeria special form 7178...")
    # For Nigeria, use simplified processing
    data <- read_input_data(input_file)
    
    # Basic processing for Nigeria
    result <- data %>%
      mutate(
        Country = "NIE",
        Region = as.character(states),
        District = as.character(lgas),
        date = as.Date(today),
        u5_present = rowSums(select(., starts_with("Imm_Seen_house")), na.rm = TRUE) +
                      rowSums(select(., starts_with("unimm_h")), na.rm = TRUE),
        u5_FM = rowSums(select(., starts_with("Imm_Seen_house")), na.rm = TRUE),
        missed_child = rowSums(select(., starts_with("unimm_h")), na.rm = TRUE)
      ) %>%
      filter(!is.na(Region), !is.na(District)) %>%
      group_by(Country, Region, District, Response = siatype, roundNumber = paste0("Rnd", month(date))) %>%
      summarise(
        start_date = min(date, na.rm = TRUE),
        end_date = max(date, na.rm = TRUE),
        u5_present = sum(u5_present, na.rm = TRUE),
        u5_FM = sum(u5_FM, na.rm = TRUE),
        missed_child = sum(missed_child, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(cv = ifelse(u5_present > 0, u5_FM / u5_present, NA))
    
    write_csv(result, output_file)
    write_csv(result %>% filter(cv < 0.5 | is.na(cv)), qc_output_file)
    
    message("Done: Nigeria special form 7178")
    message("  Output: ", output_file)
    
    return(list(
      data = result,
      qc = result %>% filter(cv < 0.5 | is.na(cv)),
      summary = tibble(
        file = basename(input_file),
        rows_output = nrow(result),
        rows_qc = nrow(result %>% filter(cv < 0.5 | is.na(cv))),
        countries = "NIE",
        min_date = min(result$start_date, na.rm = TRUE),
        max_date = max(result$end_date, na.rm = TRUE)
      )
    ))
  }
  
  # Standard processing for all other files
  data <- read_input_data(input_file)
  
  # Check if this looks like an IM dataset
  minimum_im_markers <- c("Response", "roundNumber", "Type_Monitoring")
  if (!any(minimum_im_markers %in% names(data))) {
    stop("File does not look like an IM dataset.")
  }
  
  if (!"Country" %in% names(data)) {
    data$Country <- NA_character_
  }
  
  data <- apply_country_specific_transformations(data, file_name)
  data <- rename_repetitive_columns(data)
  
  active_hh_patterns <- if (file_name == ALGERIA_IM_FORM_ID) {
    hh_patterns_algeria
  } else {
    hh_patterns_standard
  }
  
  columns_to_select <- select_columns_dynamically(data, required_columns, active_hh_patterns)
  
  GF <- data %>%
    safe_filter_data() %>%
    select(any_of(columns_to_select))
  
  if (nrow(GF) == 0) {
    message("Warning: No data after filtering. Using original data with selected columns.")
    GF <- data %>% select(any_of(columns_to_select))
  }
  
  # Convert HH numeric columns
  hh_cols <- names(GF)[str_detect(names(GF), "^HH\\[")]
  sm_text_keep_cols <- hh_cols[str_detect(hh_cols, regex("Source_Info_SIA_HH$|Other_Source_Info$", ignore_case = TRUE))]
  hh_numeric_cols <- setdiff(hh_cols, sm_text_keep_cols)
  
  for (col in hh_numeric_cols) {
    GF[[col]] <- suppressWarnings(as.numeric(as.character(GF[[col]])))
    GF[[col]][is.na(GF[[col]])] <- 0
  }
  
  for (col in sm_text_keep_cols) {
    GF[[col]] <- as.character(GF[[col]])
  }
  
  if ("date_monitored" %in% names(GF)) {
    GF <- GF %>% mutate(date_monitored = parse_mixed_dates(date_monitored))
  }
  
  # Create summary columns
  is_algeria <- (file_name == ALGERIA_IM_FORM_ID)
  
  if (is_algeria) {
    present_cols <- names(GF)[names(GF) %in% sprintf("HH[%s]/Total_U6_Present_HH", 1:10)]
    fm_cols <- names(GF)[names(GF) %in% sprintf("HH[%s]/U6_Vac_FM_HH", 1:10)]
  } else {
    present_cols <- names(GF)[names(GF) %in% sprintf("HH[%s]/Total_U5_Present_HH", 1:10)]
    fm_cols <- names(GF)[names(GF) %in% sprintf("HH[%s]/U5_Vac_FM_HH", 1:10)]
  }
  
  GF <- GF %>%
    mutate(
      u5_present = safe_row_sum(., present_cols),
      u5_FM = safe_row_sum(., fm_cols),
      missed_child = pmax(0, u5_present - u5_FM),
      Number_of_HH_visited = if ("HH_count" %in% names(.)) as.numeric(HH_count) else NA_real_
    )
  
  # Aggregate by district
  result <- GF %>%
    group_by(Country, Region, District, Response, roundNumber) %>%
    summarise(
      start_date = min(date_monitored, na.rm = TRUE),
      end_date = max(date_monitored, na.rm = TRUE),
      Number_of_HH_visited = sum(Number_of_HH_visited, na.rm = TRUE),
      u5_present = sum(u5_present, na.rm = TRUE),
      u5_FM = sum(u5_FM, na.rm = TRUE),
      missed_child = sum(missed_child, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      cv = ifelse(u5_present > 0, round(u5_FM / u5_present, 4), NA_real_),
      year = year(start_date)
    ) %>%
    filter(!is.na(District), District != "NA")
  
  # Join with lookup table if available
  if (!is.null(lookup_table) && nrow(lookup_table) > 0) {
    result <- result %>%
      left_join(lookup_table, by = c("Response", "roundNumber")) %>%
      mutate(
        start_date = coalesce(start_date.y, start_date.x),
        end_date = coalesce(end_date.y, end_date.x),
        round_start_date = coalesce(round_start_date, start_date - 4)
      ) %>%
      select(-start_date.x, -start_date.y, -end_date.x, -end_date.y)
  } else {
    result <- result %>% mutate(round_start_date = start_date - 4)
  }
  
  # Final clean up
  result <- result %>%
    mutate(
      country = Country,
      province = Region,
      district = District,
      response = Response,
      vaccine.type = NA_character_,
      .keep = "none",
      country = Country,
      province = Region,
      district = District,
      response = Response,
      roundNumber = roundNumber,
      round_start_date = round_start_date,
      start_date_IM_end = start_date,
      end_date_IM_end = end_date,
      year = year,
      Number_of_HH_visited = Number_of_HH_visited,
      u5_present = u5_present,
      u5_FM = u5_FM,
      missed_child = missed_child,
      cv = cv,
      r_non_FM_Absent = NA_real_,
      r_non_FM_NC = NA_real_,
      r_non_FM_hh_notvisited = NA_real_,
      r_non_FM_sleep = NA_real_,
      r_non_FM_other = NA_real_,
      care_Giver_Informed_SIA = NA_real_,
      sm_total_sources = NA_real_,
      reasons_total = NA_real_,
      check_missed = NA_real_,
      reconciliation_flag = NA_character_,
      qc_flag = ifelse(is.na(cv) | cv < 0.5, "Needs review", "OK")
    )
  
  # Save outputs
  write_csv(result, output_file)
  
  qc_result <- result %>% filter(qc_flag == "Needs review" | is.na(cv) | cv < 0.7)
  write_csv(qc_result, qc_output_file)
  
  message("Done: ", basename(input_file))
  message("  Output: ", output_file)
  message("  QC: ", qc_output_file)
  
  list(
    data = result,
    qc = qc_result,
    summary = tibble(
      file = basename(input_file),
      rows_output = nrow(result),
      rows_qc = nrow(qc_result),
      countries = paste(unique(result$country), collapse = ", "),
      min_date = min(result$start_date_IM_end, na.rm = TRUE),
      max_date = max(result$start_date_IM_end, na.rm = TRUE)
    )
  )
}

# ============================================================
# MULTI-FORMAT EXPORT FUNCTIONS
# ============================================================

export_multi_format <- function(data, base_path) {
  if (is.null(data) || nrow(data) == 0) {
    message("  Warning: No data to export for ", basename(base_path))
    return(NULL)
  }
  
  dir_path <- dirname(base_path)
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE)
  }
  
  exported_files <- list()
  
  # CSV
  csv_path <- paste0(base_path, ".csv")
  tryCatch({
    write_csv(data, csv_path)
    csv_size <- round(file.size(csv_path) / 1024 / 1024, 2)
    message(sprintf("  ✓ CSV: %s (%.2f MB)", basename(csv_path), csv_size))
    exported_files$csv <- csv_path
  }, error = function(e) {
    message(sprintf("  ✗ CSV export failed: %s", e$message))
  })
  
  # RDS
  rds_path <- paste0(base_path, ".rds")
  tryCatch({
    saveRDS(data, rds_path, compress = TRUE)
    rds_size <- round(file.size(rds_path) / 1024 / 1024, 2)
    message(sprintf("  ✓ RDS: %s (%.2f MB)", basename(rds_path), rds_size))
    exported_files$rds <- rds_path
  }, error = function(e) {
    message(sprintf("  ✗ RDS export failed: %s", e$message))
  })
  
  # Parquet
  parquet_path <- paste0(base_path, ".parquet")
  tryCatch({
    arrow::write_parquet(data, parquet_path, compression = "snappy")
    parquet_size <- round(file.size(parquet_path) / 1024 / 1024, 2)
    message(sprintf("  ✓ Parquet: %s (%.2f MB)", basename(parquet_path), parquet_size))
    exported_files$parquet <- parquet_path
  }, error = function(e) {
    message(sprintf("  ✗ Parquet export failed: %s", e$message))
  })
  
  return(exported_files)
}

# ============================================================
# MAIN EXECUTION
# ============================================================

# Find all input files
input_pattern <- paste0("\\.(", paste(SUPPORTED_INPUT_EXTENSIONS, collapse = "|"), ")$")
files <- list.files(INPUT_FOLDER, pattern = input_pattern, full.names = TRUE, ignore.case = TRUE)

# Exclude log and repository files
bad_patterns <- c("fetch_log", "processing_summary", "regional_im_repository", "_qc", "^qc$", "repository")
keep_file <- function(f) {
  b <- tolower(basename(f))
  !any(stringr::str_detect(b, regex(paste(bad_patterns, collapse = "|"), ignore_case = TRUE)))
}
files <- files[vapply(files, keep_file, logical(1))]

if (length(files) == 0) {
  stop("No valid IM input files found in: ", INPUT_FOLDER)
}

cat("\nFound", length(files), "files to process.\n")

# Process each file
processed_results <- list()
summary_results <- list()

for (f in files) {
  res <- tryCatch(
    process_im_file(f, OUTPUT_FOLDER, QC_FOLDER, lookup_table),
    error = function(e) {
      message("ERROR in file ", basename(f), ": ", e$message)
      list(
        data = NULL,
        qc = NULL,
        summary = tibble(
          file = basename(f),
          rows_output = NA_integer_,
          rows_qc = NA_integer_,
          countries = NA_character_,
          min_date = as.Date(NA),
          max_date = as.Date(NA)
        )
      )
    }
  )
  
  processed_results[[basename(f)]] <- res
  summary_results[[basename(f)]] <- res$summary
}

# Combine results
summary_table <- bind_rows(summary_results)
write_csv(summary_table, summary_file)

# Build regional repository
clean_list <- lapply(processed_results, function(x) x$data)
qc_list <- lapply(processed_results, function(x) x$qc)

regional_im <- bind_rows_fill(clean_list)
regional_im_qc <- bind_rows_fill(qc_list)

# Export main repository
cat("\n📦 Exporting Regional IM Repository in multiple formats...\n")
cat("============================================================\n")

cat("\n📊 MAIN REPOSITORY:\n")
main_base <- sub("\\.csv$", "", regional_repository_file)
export_multi_format(regional_im, main_base)

cat("\n🔍 QC REPOSITORY:\n")
qc_base <- sub("\\.csv$", "", regional_qc_repository_file)
export_multi_format(regional_im_qc, qc_base)

# Create metadata file (simple version)
metadata <- data.frame(
  Item = c("Repository name", "Generated on", "Rows", "Columns", "Countries"),
  Value = c(
    "Regional IM Repository",
    as.character(Sys.Date()),
    nrow(regional_im),
    ncol(regional_im),
    paste(unique(regional_im$country), collapse = ", ")
  )
)
write.xlsx(metadata, file.path(OUTPUT_FOLDER, "Regional_IM_repository_METADATA.xlsx"))

cat("\n✅ Batch processing completed!\n")
cat("============================================================\n")
cat("Summary file:", summary_file, "\n")
cat("Regional repository rows:", nrow(regional_im), "\n")
cat("Regional QC rows:", nrow(regional_im_qc), "\n")
cat("============================================================\n")