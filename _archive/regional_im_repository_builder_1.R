# ============================================================
# Batch regional IM cleaning + Regional IM repository builder
# Full updated version with:
# - multi-format input reading
# - Algeria U6 logic for form 8587
# - generic regional U5 logic
# - missed/reasons QC
# - SM integrated from:
#     1) form-level counts
#     2) one-hot HH columns
#     3) combined text fields Source_Info_SIA_HH / Other_Source_Info
#     4) space-separated value format (Mauritania, etc.)
# - expanded SM parser for coded + localized free-text values
# - SM reconciliation QC
# - safe regional repository builder
# - OPTIMIZED: vectorized SM text processing for speed
# - FIXED: special missing codes (-999/-998/etc.) removed before row sums/QC
# - FIXED: date columns converted before export
# - FIXED: r_non_compliance populated from r_non_FM_NC when needed
# - ADDED: external-user metadata workbook export
# - ADDED: Multi-format export (CSV, RDS, Parquet)
# ============================================================

pacman::p_load(
  tidyverse, lubridate, readxl, readr, tools, tibble, qs, stringr, arrow, data.table, openxlsx
)

# ============================================================
# USER PATHS
# ============================================================

base_dir <- "C:/Users/TOURE/Documents/im_workflow"

input_folder <- file.path(base_dir, "data/raw")

output_folder <- file.path(base_dir, "data/final")

qc_output_folder <- file.path(
  base_dir,
  "data/processed/qc"
)

preparedness_file <- file.path(
  base_dir,
  "data/lookup/lookup.xlsx"
)

regional_repository_file <- file.path(
  output_folder,
  "Regional_IM_repository.csv"
)

regional_qc_repository_file <- file.path(
  output_folder,
  "Regional_IM_repository_QC.csv"
)

summary_file <- file.path(
  output_folder,
  "IM_processing_summary.csv"
)

# ============================================================
# CREATE FOLDERS IF MISSING
# ============================================================

required_dirs <- c(
  base_dir,
  file.path(base_dir, "config"),
  file.path(base_dir, "data"),
  file.path(base_dir, "data/raw"),
  file.path(base_dir, "data/final"),
  file.path(base_dir, "data/lookup"),
  file.path(base_dir, "data/processed"),
  file.path(base_dir, "data/processed/qc"),
  file.path(base_dir, "logs"),
  file.path(base_dir, "outputs"),
  file.path(base_dir, "scripts")
)

for (d in required_dirs) {
  if (!dir.exists(d)) {
    dir.create(d, recursive = TRUE)
  }
}

# ============================================================
# CONSTANTS
# ============================================================
ALGERIA_IM_FORM_ID <- "8587"
NIGERIA_IM_FORM_ID <- "7178"

# ============================================================
# INLINE NIGERIA IM PROCESSOR SCRIPT FOR FORM 7178
# No external source() dependency.
# Generated from finalized nigeria_im_data_cleaning_and_aggregation.R
# ============================================================
NIGERIA_IM_SCRIPT_INLINE <- c(
  "# ============================================================",
  "# NIGERIA IM REPOSITORY BUILDER - OPTIMIZED FAST VERSION - FINAL SANITIZED",
  "# Harmonized with Regional IM Repository Builder",
  "# Includes:",
  "# - Missed child reason classification",
  "# - Absence / non-compliance detail QC",
  "# - Correct Nigeria SourceInfo codebook",
  "# - SM analytics indicators",
  "# - Regional-compatible QC columns",
  "# - Source-level sanitization for Nigeria numeric fields",
  "# - Final denominator/numerator consistency repair before export",
  "# ============================================================",
  "",
  "suppressPackageStartupMessages({",
  "  library(tidyverse)",
  "  library(data.table)",
  "  library(stringr)",
  "  library(lubridate)",
  "  library(qs)",
  "})",
  "",
  "# ============================================================",
  "# 0) INPUT / OUTPUT",
  "# ============================================================",
  "",
  "# rds_file <- \"C:/Users/TOURE/Documents/PADACORD/IM/7178.rds\"",
  "if (!exists(\"rds_file\")) {",
  "  rds_file <- \"C:/Users/TOURE/Documents/PADACORD/IM/7178.rds\"",
  "}",
  "if (!exists(\"out_file\", inherits = FALSE)) out_file <- \"C:/Users/TOURE/Documents/REPOSITORIES/IM_raw_data/IM_level/Nigeria_IM_repository.csv\"",
  "",
  "# ============================================================",
  "# 1) READ RAW DATA",
  "# ============================================================",
  "",
  "cat(\"\\nReading raw data...\\n\")",
  "t0 <- Sys.time()",
  "",
  "AB <- read_input_data(rds_file)",
  "setDT(AB)",
  "",
  "AB[, Country := \"NIE\"]",
  "AB[, states := trimws(as.character(states))]",
  "AB[states %in% c(\"\", \"NA\", \"null\", \"nan\"), states := NA_character_]",
  "AB <- AB[!is.na(states)]",
  "",
  "cat(\"Read completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 2) HELPERS",
  "# ============================================================",
  "",
  "normalize_reason_text <- function(x) {",
  "  x <- tolower(trimws(as.character(x)))",
  "  x[x %in% c(\"\", \"na\", \"nan\", \"null\")] <- NA_character_",
  "  x <- iconv(x, from = \"\", to = \"ASCII//TRANSLIT\", sub = \"\")",
  "  x <- gsub(\"[\\r\\n\\t]+\", \" \", x)",
  "  x <- gsub(\"[[:punct:]]+\", \" \", x)",
  "  x <- gsub(\"\\\\s+\", \" \", x)",
  "  trimws(x)",
  "}",
  "",
  "detect_main_reason <- function(x) {",
  "  x0 <- normalize_reason_text(x)",
  "  ",
  "  dplyr::case_when(",
  "    is.na(x0) | x0 == \"\" ~ NA_character_,",
  "    ",
  "    str_detect(x0, \"\\\\bnew born\\\\b|\\\\bnewborn\\\\b|\\\\bnew birth\\\\b|\\\\bnewly born\\\\b|\\\\ba day child\\\\b|\\\\ba day old\\\\b|\\\\bthree days old\\\\b|\\\\bjust gave birth\\\\b|\\\\bgiven birth\\\\b|\\\\bwas born yesterday\\\\b|\\\\bchild was born yesterday\\\\b|\\\\bdelivered on\\\\b|\\\\bbaby has four days\\\\b|\\\\bbaby was just born\\\\b|\\\\bzero dose\\\\b|\\\\bnew born baby\\\\b|\\\\bnew born babies\\\\b|\\\\bnew born child\\\\b|\\\\bnew born bby\\\\b\") ~ \"r_non_FM_childnotborn\",",
  "    ",
  "    str_detect(x0, \"\\\\bsecurity\\\\b|security related issues\") ~ \"r_non_FM_security\",",
  "    ",
  "    str_detect(x0, \"finger mark|finger marked|finger marking|not finger marked|no mark on left finger|fingers not mark|mark was seen|mark was not seen|cleaned off|wrongly finger marked|vaccinated but was not marked|immunized but no mark|vaccinated but no mark|finger marking erased|finger marking has cleaned off|child was immunized|the child was immunized|immunized at different occasions|passed the immunization|received routine opv|received vaccine last month\") ~ \"r_non_FM_vaccinated_but_not_FM\",",
  "    ",
  "    str_detect(x0, \"team not visited|team not visit|team did not visit|team didn t visit|household not visited|household not visit|house was not visit|house not visited|not revisited|never revisited|no revisit|revisit household|team omitted|did not make effort|didn t make effort|team failed to check|questions were not asked|didn t ask|did not ask|team didn t see the children|team didn t immunise|team didn t immunize|team visited but.*not.*effort|team got to the house but.*not.*effort|missed by the team|team do not ask five key question|teams unable to ask questions|team wrote revisit but never revisited|team wrote revisited but never revisited|team didn t reached out|team failed to check for children|house was not visit by the team\") ~ \"r_non_FM_hh_notvisited\",",
  "    ",
  "    str_detect(x0, \"\\\\basleep\\\\b|\\\\bsleeping\\\\b|\\\\bwas sleeping\\\\b|\\\\bchild sleeping\\\\b|\\\\bchild was sleep\\\\b|\\\\bchild was asleep\\\\b|\\\\bwas slept\\\\b|\\\\bat sleep\\\\b|\\\\bchild was sleeping\\\\b|\\\\bchild is sleeping\\\\b|\\\\bshe was sleeping\\\\b|\\\\bmother was sleeping\\\\b\") ~ \"r_non_FM_sleep\",",
  "    ",
  "    str_detect(x0, \"\\\\bvisitor\\\\b|\\\\bvisitors\\\\b|came for visiting|came for a visit|came visiting|came on visit|visiting child|visiting parent|just arrived|just came|just came back|moved in|from outside the settlement|from another state|from other state|not from the settlement|came for holiday|just came for holiday|holiday|sallah festival|omugwo|from village|from ibadan|from kano|from lagos|visit child from other lga|newly located|packed in|visitor from village|came from ibadan|came from kano|came from lagos|from nassarawa state|child just came visiting|child was visiting from another state|he is a visitor|the child is a visitor|he s on a visit to the house\") ~ \"r_non_FM_child_is_a_visitor\",",
  "    ",
  "    str_detect(x0, \"non compliance|noncompliance|refusal|refused|rejection|does not want|do not allow|did not allow|father refused|father did not allow|father do not allow|mother requested not to give|not intrested|not interested|religious|traditional|cultural|no felt need|polio can be cured|polio has been eradicated|too many rounds|too many round|too many rnd|no caregiver consent|no care giver consent|no parental consent|caregiver refusal|scared|afraid|vaccine.*safe|vaccines.*safe|negative way|not been educated|ignorance|the say no|religious beliefs|announcement from mosque\") ~ \"r_non_FM_NC\",",
  "    ",
  "    str_detect(x0, \"absent|abcent|absant|absend|abcend|abset|absence|absences|not around|not arround|not arrnd|not a round|not arond|not sround|not araun|not home|not at home|not as home|note at home|no at home|not present|not found at home|not in the house|not in house|not in area|not available|not seen|not met|wasn t present|wasnt present|wasn t around|wasnt around|wasn t home|wasnt home|away during|away with|went out|out of house|market|farm|school|shool|sch|islamiya|modiraza|qur an school|play ground|playground|playing ground|play graunt|play grouwn|play groud|play grand|social event|social events|socialevert|socialevent|social evert|social getthering|event center|church|travel|travelled|travelling|traveling|journey|transit|errand|river|work|office|wedding|ceremony|burial|meeting\") ~ \"r_non_FM_Absent\",",
  "    ",
  "    TRUE ~ \"r_non_FM_other\"",
  "  )",
  "}",
  "",
  "detect_abs_reason <- function(x) {",
  "  x0 <- normalize_reason_text(x)",
  "  ",
  "  dplyr::case_when(",
  "    is.na(x0) | x0 == \"\" ~ NA_character_,",
  "    str_detect(x0, \"travel|travelled|travelling|traveling|journey|transit|out of town|other state|outside the lga|trip|travel back|returned from journey\") ~ \"abs_reason_travelled\",",
  "    str_detect(x0, \"farm|farming|bush|firewood\") ~ \"abs_reason_farm\",",
  "    str_detect(x0, \"market|shop\") ~ \"abs_reason_market\",",
  "    str_detect(x0, \"school|schools|shool|sch|islamiya|modiraza|qur an school\") ~ \"abs_reason_school\",",
  "    str_detect(x0, \"play ground|playground|playing ground|play graunt|play grouwn|play grand|play groud|went to play|he was playing|play away\") ~ \"abs_reason_in_playground\",",
  "    TRUE ~ \"abs_reason_other\"",
  "  )",
  "}",
  "",
  "detect_nc_reason <- function(x) {",
  "  x0 <- normalize_reason_text(x)",
  "  ",
  "  dplyr::case_when(",
  "    is.na(x0) | x0 == \"\" ~ NA_character_,",
  "    str_detect(x0, \"religious|cultural|traditional|announcement from mosque|religious beliefs\") ~ \"nc_reason_religious_cultural\",",
  "    str_detect(x0, \"polio can be cured|polio free|polio has been eradicated|poliofree\") ~ \"nc_reason_poliofree\",",
  "    str_detect(x0, \"vaccine.*safe|vaccines.*safe|afraid|scared|negative way|reacted on child|interaction|safety\") ~ \"nc_reason_vaccines_safety\",",
  "    str_detect(x0, \"no felt need|no need|no perceived need\") ~ \"nc_reason_no_felt_need\",",
  "    str_detect(x0, \"too many rounds|too many round|too many rnd\") ~ \"nc_reason_too_many_rnd\",",
  "    str_detect(x0, \"father refused|father did not allow|father do not allow|does not want|do not allow|did not allow|no caregiver consent|no care giver consent|no parental consent|caregiver refusal|mother requested not to give|refusal|refused|rejection|the say no\") ~ \"nc_reason_no_care_giver_consent\",",
  "    str_detect(x0, \"child is sick|child was sick|child sick|child seek|child was ill|not healthy|unwell|hospital|admitted|not well|no medicine|physically fit|seriously sick|child are sick\") ~ \"nc_reason_child_sick\",",
  "    str_detect(x0, \"covid\") ~ \"nc_reason_covid_19\",",
  "    str_detect(x0, \"nopv|n opv\") ~ \"nc_reason_nopvconcern\",",
  "    TRUE ~ \"nc_reason_others\"",
  "  )",
  "}",
  "",
  "",
  "# ============================================================",
  "# 2B) NUMERIC SANITIZATION HELPERS",
  "# ============================================================",
  "# These are applied at the raw-field level before aggregation.",
  "# Positive 996/997/998/999 can be impossible at household level but may be",
  "# legitimate after district aggregation; therefore positive special codes are",
  "# removed only from raw numeric fields, not from final aggregated totals.",
  "",
  "RAW_SPECIAL_MISSING_CODES <- c(",
  "  -999, -998, -997, -996, -995,",
  "   999,  998,  997,  996",
  ")",
  "",
  "clean_raw_numeric <- function(x, negative_to_na = TRUE) {",
  "  x <- suppressWarnings(as.numeric(as.character(x)))",
  "  x[x %in% RAW_SPECIAL_MISSING_CODES] <- NA_real_",
  "  if (negative_to_na) x[x < 0] <- NA_real_",
  "  x",
  "}",
  "",
  "safe_raw_numeric_zero <- function(x) {",
  "  x <- clean_raw_numeric(x, negative_to_na = TRUE)",
  "  x[is.na(x)] <- 0",
  "  x",
  "}",
  "",
  "safe_final_count_zero <- function(x) {",
  "  # Final aggregated counts: keep legitimate values like 998/999,",
  "  # but remove negatives and non-numeric contamination.",
  "  x <- suppressWarnings(as.numeric(as.character(x)))",
  "  x[is.na(x)] <- 0",
  "  x[x < 0] <- 0",
  "  x",
  "}",
  "",
  "sanitize_nigeria_im_output <- function(AK) {",
  "  setDT(AK)",
  "  ",
  "  # Non-negative count variables only. Diagnostic balance columns such as",
  "  # check_missed, check_abs_detail and check_nc_detail are recalculated later",
  "  # and may legitimately be negative when reasons are overreported.",
  "  count_cols <- intersect(",
  "    c(",
  "      \"u5_present\", \"u5_FM\", \"missed_child\",",
  "      main_reason_vars, abs_reason_vars, nc_reason_vars,",
  "      sm_vars,",
  "      \"sm_total_sources\", \"sm_total_awareness_sources\",",
  "      \"total_main_reasons\", \"abs_detail_total\", \"nc_detail_total\",",
  "      \"unexplained_missed\", \"overreported_reasons\"",
  "    ),",
  "    names(AK)",
  "  )",
  "  ",
  "  for (cc in count_cols) {",
  "    set(AK, j = cc, value = safe_final_count_zero(AK[[cc]]))",
  "  }",
  "  ",
  "  # Denominator / numerator consistency.",
  "  if (all(c(\"u5_present\", \"u5_FM\", \"missed_child\") %in% names(AK))) {",
  "    AK[, u5_present_original := u5_present]",
  "    AK[, u5_FM_original := u5_FM]",
  "    AK[, missed_child_original := missed_child]",
  "    ",
  "    AK[, denominator_reconstructed := fifelse(",
  "      u5_present <= 0 & u5_FM > 0 & missed_child > 0,",
  "      1L, 0L",
  "    )]",
  "    ",
  "    AK[denominator_reconstructed == 1L, u5_present := u5_FM + missed_child]",
  "    ",
  "    AK[, numerator_reconstructed := fifelse(",
  "      u5_FM <= 0 & u5_present > 0 & missed_child >= 0,",
  "      1L, 0L",
  "    )]",
  "    ",
  "    AK[numerator_reconstructed == 1L, u5_FM := pmax(0, u5_present - missed_child)]",
  "    ",
  "    AK[, numerator_capped := fifelse(",
  "      u5_FM > u5_present & u5_present > 0,",
  "      1L, 0L",
  "    )]",
  "    ",
  "    AK[numerator_capped == 1L, u5_FM := u5_present]",
  "    AK[, missed_child := pmax(0, u5_present - u5_FM)]",
  "    AK[, cv := fifelse(u5_present > 0, round(u5_FM / u5_present, 4), NA_real_)]",
  "    AK[is.infinite(cv) | is.nan(cv) | cv < 0, cv := NA_real_]",
  "    AK[cv > 1, cv := 1]",
  "    ",
  "    AK[, denominator_qc_flag := fifelse(",
  "      denominator_reconstructed == 1L,",
  "      \"Denominator reconstructed\",",
  "      fifelse(",
  "        numerator_reconstructed == 1L,",
  "        \"Numerator reconstructed\",",
  "        fifelse(",
  "          numerator_capped == 1L,",
  "          \"Numerator capped to denominator\",",
  "          fifelse(",
  "            u5_present <= 0 & (u5_FM > 0 | missed_child > 0),",
  "            \"Denominator inconsistency\",",
  "            \"Denominator OK\"",
  "          )",
  "        )",
  "      )",
  "    )]",
  "  }",
  "  ",
  "  # Recalculate totals after sanitation.",
  "  if (all(main_reason_vars %in% names(AK))) {",
  "    AK[, total_main_reasons := rowSums(.SD, na.rm = TRUE), .SDcols = main_reason_vars]",
  "  }",
  "  ",
  "  if (all(abs_reason_vars %in% names(AK))) {",
  "    AK[, abs_detail_total := rowSums(.SD, na.rm = TRUE), .SDcols = abs_reason_vars]",
  "  }",
  "  ",
  "  if (all(nc_reason_vars %in% names(AK))) {",
  "    AK[, nc_detail_total := rowSums(.SD, na.rm = TRUE), .SDcols = nc_reason_vars]",
  "  }",
  "  ",
  "  if (all(sm_vars %in% names(AK))) {",
  "    AK[, sm_total_sources := rowSums(.SD, na.rm = TRUE), .SDcols = sm_vars]",
  "    AK[, sm_total_awareness_sources := rowSums(.SD, na.rm = TRUE), .SDcols = sm_aware_vars]",
  "  }",
  "  ",
  "  # Recalculate reconciliation fields.",
  "  if (all(c(\"missed_child\", \"total_main_reasons\") %in% names(AK))) {",
  "    AK[, check_missed := missed_child - total_main_reasons]",
  "    AK[, unexplained_missed := pmax(check_missed, 0)]",
  "    AK[, overreported_reasons := pmax(-check_missed, 0)]",
  "    AK[, explained_ratio := fifelse(missed_child > 0, round(total_main_reasons / missed_child, 3), NA_real_)]",
  "    AK[, unexplained_ratio := fifelse(missed_child > 0, round(unexplained_missed / missed_child, 3), NA_real_)]",
  "  }",
  "  ",
  "  if (all(c(\"r_non_FM_Absent\", \"abs_detail_total\") %in% names(AK))) {",
  "    AK[, check_abs_detail := r_non_FM_Absent - abs_detail_total]",
  "  }",
  "  ",
  "  if (all(c(\"r_non_FM_NC\", \"nc_detail_total\") %in% names(AK))) {",
  "    AK[, check_nc_detail := r_non_FM_NC - nc_detail_total]",
  "  }",
  "  ",
  "  if (all(c(\"sm_total_awareness_sources\", \"sm_not_aware\") %in% names(AK))) {",
  "    AK[, sm_reconciliation_flag := fifelse(",
  "      sm_total_awareness_sources == 0 & sm_not_aware > 0,",
  "      \"Not aware reported\",",
  "      fifelse(sm_total_awareness_sources == 0, \"No source recorded\", \"SM source recorded\")",
  "    )]",
  "  }",
  "  ",
  "  if (all(c(\"check_missed\", \"total_main_reasons\") %in% names(AK))) {",
  "    AK[, reconciliation_flag := fifelse(",
  "      check_missed == 0,",
  "      \"Consistent\",",
  "      fifelse(",
  "        check_missed > 0 & total_main_reasons == 0,",
  "        \"No reasons recorded\",",
  "        fifelse(",
  "          check_missed > 0,",
  "          \"Partial reasons recorded\",",
  "          fifelse(check_missed < 0, \"Overlapping reasons\", \"Unknown\")",
  "        )",
  "      )",
  "    )]",
  "  }",
  "  ",
  "  if (\"check_abs_detail\" %in% names(AK)) {",
  "    AK[, abs_detail_flag := fifelse(",
  "      check_abs_detail == 0,",
  "      \"Abs detail consistent\",",
  "      fifelse(check_abs_detail > 0, \"Abs detail incomplete\", \"Abs detail overlapping\")",
  "    )]",
  "  }",
  "  ",
  "  if (\"check_nc_detail\" %in% names(AK)) {",
  "    AK[, nc_detail_flag := fifelse(",
  "      check_nc_detail == 0,",
  "      \"NC detail consistent\",",
  "      fifelse(check_nc_detail > 0, \"NC detail incomplete\", \"NC detail overlapping\")",
  "    )]",
  "  }",
  "  ",
  "  if (all(c(\"reconciliation_flag\", \"abs_detail_flag\", \"nc_detail_flag\") %in% names(AK))) {",
  "    AK[, qc_flag := fifelse(",
  "      reconciliation_flag == \"Consistent\" &",
  "        abs_detail_flag == \"Abs detail consistent\" &",
  "        nc_detail_flag == \"NC detail consistent\" &",
  "        denominator_qc_flag != \"Denominator inconsistency\",",
  "      \"OK\",",
  "      \"Needs review\"",
  "    )]",
  "  }",
  "  ",
  "  AK",
  "}",
  "",
  "",
  "# ============================================================",
  "# 2C) FINAL ENTERPRISE EXPORT CLEANING",
  "# ============================================================",
  "# Purpose:",
  "# - remove all special missing codes from exported numeric fields;",
  "# - remove raw *_original fields that may preserve source contamination;",
  "# - recompute SM totals, coverage, missed-child logic and QC after cleanup.",
  "",
  "enterprise_clean_nigeria_export <- function(AK) {",
  "  setDT(AK)",
  "  ",
  "  # Drop raw trace columns that may preserve original special missing codes.",
  "  raw_trace_cols <- intersect(",
  "    c(\"u5_present_original\", \"u5_FM_original\", \"missed_child_original\"),",
  "    names(AK)",
  "  )",
  "  if (length(raw_trace_cols) > 0) {",
  "    AK[, (raw_trace_cols) := NULL]",
  "  }",
  "  ",
  "  numeric_cols <- names(AK)[vapply(AK, is.numeric, logical(1))]",
  "  ",
  "  # Remove special missing codes from every numeric output field.",
  "  if (length(numeric_cols) > 0) {",
  "    for (cc in numeric_cols) {",
  "      vals <- AK[[cc]]",
  "      vals[vals %in% RAW_SPECIAL_MISSING_CODES] <- NA_real_",
  "      set(AK, j = cc, value = vals)",
  "    }",
  "  }",
  "  ",
  "  # Non-negative count fields: special codes become 0 after removal.",
  "  non_negative_cols <- intersect(",
  "    c(",
  "      \"u5_present\", \"u5_FM\", \"missed_child\",",
  "      main_reason_vars, abs_reason_vars, nc_reason_vars,",
  "      sm_vars,",
  "      \"sm_total_sources\", \"sm_total_awareness_sources\",",
  "      \"total_main_reasons\", \"abs_detail_total\", \"nc_detail_total\",",
  "      \"unexplained_missed\", \"overreported_reasons\",",
  "      \"denominator_reconstructed\", \"numerator_reconstructed\", \"numerator_capped\"",
  "    ),",
  "    names(AK)",
  "  )",
  "  ",
  "  for (cc in non_negative_cols) {",
  "    vals <- suppressWarnings(as.numeric(AK[[cc]]))",
  "    vals[is.na(vals)] <- 0",
  "    vals[vals < 0] <- 0",
  "    set(AK, j = cc, value = vals)",
  "  }",
  "  ",
  "  # Recompute social mobilisation totals after cleaning.",
  "  sm_existing <- intersect(sm_vars, names(AK))",
  "  if (length(sm_existing) > 0) {",
  "    AK[, sm_total_sources := rowSums(.SD, na.rm = TRUE), .SDcols = sm_existing]",
  "  }",
  "  ",
  "  sm_aware_existing <- intersect(sm_aware_vars, names(AK))",
  "  if (length(sm_aware_existing) > 0) {",
  "    AK[, sm_total_awareness_sources := rowSums(.SD, na.rm = TRUE), .SDcols = sm_aware_existing]",
  "  }",
  "  ",
  "  # Recompute denominator/numerator consistency and CV.",
  "  if (all(c(\"u5_present\", \"u5_FM\", \"missed_child\") %in% names(AK))) {",
  "    AK[, numerator_capped := fifelse(u5_FM > u5_present & u5_present > 0, 1L, coalesce(as.integer(numerator_capped), 0L))]",
  "    AK[u5_FM > u5_present & u5_present > 0, u5_FM := u5_present]",
  "    AK[, missed_child := pmax(0, u5_present - u5_FM)]",
  "    AK[, cv := fifelse(u5_present > 0, round(u5_FM / u5_present, 4), NA_real_)]",
  "    AK[is.infinite(cv) | is.nan(cv) | cv < 0, cv := NA_real_]",
  "    AK[cv > 1, cv := 1]",
  "    ",
  "    AK[, denominator_qc_flag := fifelse(",
  "      coalesce(as.integer(denominator_reconstructed), 0L) == 1L,",
  "      \"Denominator reconstructed\",",
  "      fifelse(",
  "        coalesce(as.integer(numerator_reconstructed), 0L) == 1L,",
  "        \"Numerator reconstructed\",",
  "        fifelse(",
  "          coalesce(as.integer(numerator_capped), 0L) == 1L,",
  "          \"Numerator capped to denominator\",",
  "          fifelse(",
  "            u5_present <= 0 & (u5_FM > 0 | missed_child > 0),",
  "            \"Denominator inconsistency\",",
  "            \"Denominator OK\"",
  "          )",
  "        )",
  "      )",
  "    )]",
  "  }",
  "  ",
  "  # Recompute reason/detail totals and reconciliation fields.",
  "  if (all(main_reason_vars %in% names(AK))) {",
  "    AK[, total_main_reasons := rowSums(.SD, na.rm = TRUE), .SDcols = main_reason_vars]",
  "  }",
  "  if (all(abs_reason_vars %in% names(AK))) {",
  "    AK[, abs_detail_total := rowSums(.SD, na.rm = TRUE), .SDcols = abs_reason_vars]",
  "  }",
  "  if (all(nc_reason_vars %in% names(AK))) {",
  "    AK[, nc_detail_total := rowSums(.SD, na.rm = TRUE), .SDcols = nc_reason_vars]",
  "  }",
  "  ",
  "  if (all(c(\"missed_child\", \"total_main_reasons\") %in% names(AK))) {",
  "    AK[, check_missed := missed_child - total_main_reasons]",
  "    AK[, unexplained_missed := pmax(check_missed, 0)]",
  "    AK[, overreported_reasons := pmax(-check_missed, 0)]",
  "    AK[, explained_ratio := fifelse(missed_child > 0, round(total_main_reasons / missed_child, 3), NA_real_)]",
  "    AK[, unexplained_ratio := fifelse(missed_child > 0, round(unexplained_missed / missed_child, 3), NA_real_)]",
  "  }",
  "  ",
  "  if (all(c(\"r_non_FM_Absent\", \"abs_detail_total\") %in% names(AK))) {",
  "    AK[, check_abs_detail := r_non_FM_Absent - abs_detail_total]",
  "  }",
  "  if (all(c(\"r_non_FM_NC\", \"nc_detail_total\") %in% names(AK))) {",
  "    AK[, check_nc_detail := r_non_FM_NC - nc_detail_total]",
  "  }",
  "  ",
  "  if (all(c(\"sm_total_awareness_sources\", \"sm_not_aware\") %in% names(AK))) {",
  "    AK[, sm_reconciliation_flag := fifelse(",
  "      sm_total_awareness_sources == 0 & sm_not_aware > 0,",
  "      \"Not aware reported\",",
  "      fifelse(sm_total_awareness_sources == 0, \"No source recorded\", \"SM source recorded\")",
  "    )]",
  "  }",
  "  ",
  "  if (all(c(\"check_missed\", \"total_main_reasons\") %in% names(AK))) {",
  "    AK[, reconciliation_flag := fifelse(",
  "      check_missed == 0,",
  "      \"Consistent\",",
  "      fifelse(",
  "        check_missed > 0 & total_main_reasons == 0,",
  "        \"No reasons recorded\",",
  "        fifelse(",
  "          check_missed > 0,",
  "          \"Partial reasons recorded\",",
  "          fifelse(check_missed < 0, \"Overlapping reasons\", \"Unknown\")",
  "        )",
  "      )",
  "    )]",
  "  }",
  "  ",
  "  if (\"check_abs_detail\" %in% names(AK)) {",
  "    AK[, abs_detail_flag := fifelse(",
  "      check_abs_detail == 0,",
  "      \"Abs detail consistent\",",
  "      fifelse(check_abs_detail > 0, \"Abs detail incomplete\", \"Abs detail overlapping\")",
  "    )]",
  "  }",
  "  ",
  "  if (\"check_nc_detail\" %in% names(AK)) {",
  "    AK[, nc_detail_flag := fifelse(",
  "      check_nc_detail == 0,",
  "      \"NC detail consistent\",",
  "      fifelse(check_nc_detail > 0, \"NC detail incomplete\", \"NC detail overlapping\")",
  "    )]",
  "  }",
  "  ",
  "  if (all(c(\"reconciliation_flag\", \"abs_detail_flag\", \"nc_detail_flag\", \"denominator_qc_flag\") %in% names(AK))) {",
  "    AK[, qc_flag := fifelse(",
  "      reconciliation_flag == \"Consistent\" &",
  "        abs_detail_flag == \"Abs detail consistent\" &",
  "        nc_detail_flag == \"NC detail consistent\" &",
  "        denominator_qc_flag != \"Denominator inconsistency\",",
  "      \"OK\",",
  "      \"Needs review\"",
  "    )]",
  "  }",
  "  ",
  "  # ------------------------------------------------------------------",
  "  # Absolute final scrub: remove values that exactly match special-code",
  "  # sentinels after all recomputations. This is applied after check/QC",
  "  # recalculation because some diagnostic totals can become 999/-999.",
  "  # Diagnostic balance fields are kept as NA when they equal a sentinel;",
  "  # non-negative count fields are reset to 0.",
  "  # ------------------------------------------------------------------",
  "  numeric_cols_final <- names(AK)[vapply(AK, is.numeric, logical(1))]",
  "  if (length(numeric_cols_final) > 0) {",
  "    for (cc in numeric_cols_final) {",
  "      vals <- AK[[cc]]",
  "      vals[vals %in% RAW_SPECIAL_MISSING_CODES] <- NA_real_",
  "      set(AK, j = cc, value = vals)",
  "    }",
  "  }",
  "",
  "  # Keep true QC balance fields allowed to be negative, but not as sentinel values.",
  "  final_non_negative_cols <- setdiff(",
  "    intersect(",
  "      c(",
  "        \"u5_present\", \"u5_FM\", \"missed_child\", \"cv\",",
  "        main_reason_vars, abs_reason_vars, nc_reason_vars,",
  "        sm_vars,",
  "        \"sm_total_sources\", \"sm_total_awareness_sources\",",
  "        \"total_main_reasons\", \"abs_detail_total\", \"nc_detail_total\",",
  "        \"unexplained_missed\", \"overreported_reasons\",",
  "        \"denominator_reconstructed\", \"numerator_reconstructed\", \"numerator_capped\"",
  "      ),",
  "      names(AK)",
  "    ),",
  "    c(\"check_missed\", \"check_abs_detail\", \"check_nc_detail\")",
  "  )",
  "",
  "  for (cc in final_non_negative_cols) {",
  "    vals <- suppressWarnings(as.numeric(AK[[cc]]))",
  "    vals[is.na(vals)] <- 0",
  "    vals[vals < 0] <- 0",
  "    set(AK, j = cc, value = vals)",
  "  }",
  "",
  "  # Refresh only flags that depend on diagnostic fields after sentinel removal.",
  "  if (all(c(\"check_missed\", \"total_main_reasons\") %in% names(AK))) {",
  "    AK[, reconciliation_flag := fifelse(",
  "      is.na(check_missed),",
  "      \"Unknown\",",
  "      fifelse(",
  "        check_missed == 0,",
  "        \"Consistent\",",
  "        fifelse(",
  "          check_missed > 0 & total_main_reasons == 0,",
  "          \"No reasons recorded\",",
  "          fifelse(",
  "            check_missed > 0,",
  "            \"Partial reasons recorded\",",
  "            fifelse(check_missed < 0, \"Overlapping reasons\", \"Unknown\")",
  "          )",
  "        )",
  "      )",
  "    )]",
  "  }",
  "",
  "  if (all(c(\"reconciliation_flag\", \"abs_detail_flag\", \"nc_detail_flag\", \"denominator_qc_flag\") %in% names(AK))) {",
  "    AK[, qc_flag := fifelse(",
  "      reconciliation_flag == \"Consistent\" &",
  "        abs_detail_flag == \"Abs detail consistent\" &",
  "        nc_detail_flag == \"NC detail consistent\" &",
  "        denominator_qc_flag != \"Denominator inconsistency\",",
  "      \"OK\",",
  "      \"Needs review\"",
  "    )]",
  "  }",
  "",
  "  # Final assertion report for special codes.",
  "  numeric_cols_final <- names(AK)[vapply(AK, is.numeric, logical(1))]",
  "  special_remaining <- 0L",
  "  if (length(numeric_cols_final) > 0) {",
  "    special_remaining <- sum(vapply(",
  "      numeric_cols_final,",
  "      function(cc) sum(AK[[cc]] %in% RAW_SPECIAL_MISSING_CODES, na.rm = TRUE),",
  "      integer(1)",
  "    ))",
  "  }",
  "  message(\"Final enterprise cleanup - remaining special numeric codes: \", special_remaining)",
  "  ",
  "  AK",
  "}",
  "",
  "# ============================================================",
  "# 3) EXPECTED OUTPUT VARIABLES",
  "# ============================================================",
  "",
  "main_reason_vars <- c(",
  "  \"r_non_FM_Absent\",",
  "  \"r_non_FM_hh_notvisited\",",
  "  \"r_non_FM_vaccinated_but_not_FM\",",
  "  \"r_non_FM_sleep\",",
  "  \"r_non_FM_child_is_a_visitor\",",
  "  \"r_non_FM_NC\",",
  "  \"r_non_FM_childnotborn\",",
  "  \"r_non_FM_security\",",
  "  \"r_non_FM_other\"",
  ")",
  "",
  "abs_reason_vars <- c(",
  "  \"abs_reason_other\",",
  "  \"abs_reason_travelled\",",
  "  \"abs_reason_farm\",",
  "  \"abs_reason_market\",",
  "  \"abs_reason_school\",",
  "  \"abs_reason_in_playground\"",
  ")",
  "",
  "nc_reason_vars <- c(",
  "  \"nc_reason_no_felt_need\",",
  "  \"nc_reason_child_sick\",",
  "  \"nc_reason_vaccines_safety\",",
  "  \"nc_reason_religious_cultural\",",
  "  \"nc_reason_no_care_giver_consent\",",
  "  \"nc_reason_poliofree\",",
  "  \"nc_reason_too_many_rnd\",",
  "  \"nc_reason_others\",",
  "  \"nc_reason_covid_19\",",
  "  \"nc_reason_nopvconcern\"",
  ")",
  "",
  "# Correct Nigeria SourceInfo codebook",
  "sm_map_dt <- data.table(",
  "  sm_code = as.character(1:13),",
  "  sm_type = c(",
  "    \"sm_traditional_leader\",",
  "    \"sm_town_announcer\",",
  "    \"sm_mosque_announcement\",",
  "    \"sm_radio\",",
  "    \"sm_newspaper\",",
  "    \"sm_poster_leaflets\",",
  "    \"sm_banner_hoarding\",",
  "    \"sm_relative_neighbour_friend\",",
  "    \"sm_health_worker\",",
  "    \"sm_vcm_unicef\",",
  "    \"sm_school_children_rally_visit\",",
  "    \"sm_not_aware\",",
  "    \"sm_other\"",
  "  )",
  ")",
  "",
  "sm_vars <- sm_map_dt$sm_type",
  "sm_aware_vars <- setdiff(sm_vars, \"sm_not_aware\")",
  "",
  "sm_indicator_vars <- c(",
  "  \"sm_intensity_group\",",
  "  \"sm_non_compliance_pressure\",",
  "  \"sm_gap_flag\",",
  "  \"sm_priority_flag\"",
  ")",
  "",
  "qc_vars <- c(",
  "  \"reconciliation_flag\",",
  "  \"abs_detail_flag\",",
  "  \"nc_detail_flag\",",
  "  \"sm_reconciliation_flag\",",
  "  \"denominator_qc_flag\",",
  "  \"qc_flag\"",
  ")",
  "",
  "# ============================================================",
  "# 4) BASE REPOSITORY PREP",
  "# ============================================================",
  "",
  "cat(\"\\nPreparing base data...\\n\")",
  "t0 <- Sys.time()",
  "",
  "AC <- copy(AB)",
  "AC <- AC[!is.na(today) & !is.na(states)]",
  "",
  "AC[, today := as.Date(today)]",
  "AC[, DateMonitor := as.Date(DateMonitor)]",
  "AC[, year := as.numeric(lubridate::year(today))]",
  "",
  "imm_cols <- grep(\"^Imm_Seen_house\", names(AC), value = TRUE)",
  "unimm_cols <- grep(\"^unimm_h\", names(AC), value = TRUE)",
  "",
  "for (cc in c(imm_cols, unimm_cols)) {",
  "  set(AC, j = cc, value = safe_raw_numeric_zero(AC[[cc]]))",
  "}",
  "",
  "AC <- AC[year > 2019]",
  "",
  "setnames(",
  "  AC,",
  "  old = c(\"states\", \"lgas\", \"today\"),",
  "  new = c(\"Region\", \"District\", \"date\"),",
  "  skip_absent = TRUE",
  ")",
  "",
  "AC[, u5_FM := rowSums(.SD, na.rm = TRUE), .SDcols = imm_cols]",
  "AC[, missed_child := rowSums(.SD, na.rm = TRUE), .SDcols = unimm_cols]",
  "AC[, u5_present := u5_FM + missed_child]",
  "AC[, month := lubridate::month(date)]",
  "",
  "AC[vactype_other == \"b0pv\", vactype_other := \"bOPV\"]",
  "AC[vactype_other == \"cmopv2\", vactype_other := \"mOPV\"]",
  "AC[vactype_other %in% c(\"fiPv\", \"fipv plus\", \"fIPV plus\", \"Fipv plus nopv2\", \"Fipv+nopv2\"), vactype_other := \"FIPV+nOPV2\"]",
  "AC[vactype_other == \"FIPV+NOPV2\", vactype_other := \"bOPV\"]",
  "AC[vactype_other == \"Hpv\", vactype_other := \"HPV\"]",
  "AC[vactype_other %in% c(\"N opv\", \"N opv3\"), vactype_other := \"nOPV2\"]",
  "",
  "AC[, roundNumber := paste0(\"Rnd\", month)]",
  "",
  "AC[year == 2025 & month == 1, roundNumber := \"Rnd1\"]",
  "AC[year == 2024 & month == 12, roundNumber := \"Rnd5\"]",
  "AC[year == 2024 & month == 11, roundNumber := \"Rnd4\"]",
  "AC[year == 2024 & month %in% c(9, 10), roundNumber := \"Rnd3\"]",
  "AC[year == 2024 & month %in% c(2, 3), roundNumber := \"Rnd1\"]",
  "AC[year == 2024 & month %in% c(4, 5, 6), roundNumber := \"Rnd2\"]",
  "AC[year == 2023 & month %in% c(1, 5), roundNumber := \"Rnd1\"]",
  "AC[year == 2023 & month %in% c(6, 7, 8), roundNumber := \"Rnd2\"]",
  "AC[year == 2023 & month %in% c(9, 10), roundNumber := \"Rnd3\"]",
  "AC[year == 2023 & month == 11, roundNumber := \"Rnd4\"]",
  "AC[year == 2023 & month == 12, roundNumber := \"Rnd5\"]",
  "",
  "AC[, Vaccine.type := \"\"]",
  "",
  "AC[year == 2025 & month == 1, Vaccine.type := \"nOPV2\"]",
  "AC[year == 2024 & month %in% c(2, 3, 4, 9, 10, 11, 12), Vaccine.type := \"nOPV2\"]",
  "AC[year == 2023 & month == 1, Vaccine.type := \"nOPV2\"]",
  "AC[year == 2023 & month %in% c(5, 7, 9), Vaccine.type := \"fIPV+nOPV2\"]",
  "AC[year == 2023 & month %in% c(8, 10, 11, 12), Vaccine.type := \"nOPV2\"]",
  "AC[year == 2022 & month == 7, Vaccine.type := \"nOPV2\"]",
  "AC[year == 2021 & month %in% 3:10, Vaccine.type := \"nOPV2\"]",
  "AC[year == 2020 & month %in% c(1, 3), Vaccine.type := \"nOPV2\"]",
  "AC[year == 2021 & month %in% c(11, 12), Vaccine.type := \"bOPV\"]",
  "AC[year == 2022 & month %in% c(1, 2, 3, 4, 5, 8, 9, 10, 11, 12), Vaccine.type := \"bOPV\"]",
  "",
  "AC[Vaccine.type == \"other\", Vaccine.type := vactype_other]",
  "",
  "AC[, Response := siatype]",
  "",
  "AC[year == 2025 & month == 1, Response := \"OBR1\"]",
  "AC[year == 2024 & month %in% c(2, 3, 4, 8, 9, 10, 11, 12), Response := \"NIE-2024-nOPV2\"]",
  "AC[year == 2020 & month %in% c(1, 2, 3), Response := \"NGA-20DS-01-2020\"]",
  "AC[year == 2020 & month == 12, Response := \"NGA-5DS-10-2020\"]",
  "AC[year == 2021 & month == 1, Response := \"NGA-5DS-10-2020\"]",
  "AC[year == 2021 & month == 3, Response := \"NGA-2021-013-1\"]",
  "AC[year == 2021 & month %in% c(4, 5), Response := \"NGA-2021-011-1\"]",
  "AC[year == 2021 & month %in% c(6, 7), Response := \"NGA-2021-016-1\"]",
  "AC[year == 2021 & month == 8, Response := \"NGA-2021-019\"]",
  "AC[year == 2021 & month == 9, Response := \"NGA-2021-020-4\"]",
  "AC[year == 2021 & month == 10, Response := \"NGA-2021-020-2\"]",
  "AC[year == 2021 & month == 11, Response := \"NGA-2021-020-3\"]",
  "AC[year == 2022 & month %in% c(7, 8), Response := \"Kwara Response\"]",
  "AC[year == 2023 & month %in% c(5, 6), Response := \"NIE-2023-04-02_nOPV\"]",
  "AC[year == 2023 & month %in% c(7, 10, 11), Response := \"NIE-2023-07-03_nOPV\"]",
  "AC[year == 2023 & month == 12, Response := \"NIE-2023-07-03_nOPV2\"]",
  "",
  "AC[str_detect(Response, \"nOPV\"), Vaccine.type := \"nOPV2\"]",
  "AC[str_detect(Response, \"bOPV\"), Vaccine.type := \"bOPV\"]",
  "AC[!(str_detect(Response, \"nOPV\") | str_detect(Response, \"bOPV\")), Vaccine.type := vactype]",
  "",
  "AE <- AC",
  "AE[, row_id___ := .I]",
  "",
  "cat(\"Base prep completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 5) OPTIMIZED REASON LONG TABLE",
  "# ============================================================",
  "",
  "cat(\"\\nProcessing missed-child reasons...\\n\")",
  "t0 <- Sys.time()",
  "",
  "reason_cols_main <- grep(\"^NOimmReas_Child.*(?<!_other)$\", names(AE), value = TRUE, perl = TRUE)",
  "reason_cols_other <- grep(\"^NOimmReas_Child.*_other$\", names(AE), value = TRUE)",
  "",
  "id_cols_reason <- c(",
  "  \"row_id___\",",
  "  \"Country\",",
  "  \"Region\",",
  "  \"District\",",
  "  \"Response\",",
  "  \"roundNumber\",",
  "  \"Vaccine.type\"",
  ")",
  "",
  "reason_long_main <- melt(",
  "  AE,",
  "  id.vars = id_cols_reason,",
  "  measure.vars = reason_cols_main,",
  "  variable.name = \"reason_source_col\",",
  "  value.name = \"reason_raw\",",
  "  variable.factor = FALSE",
  ")",
  "",
  "reason_long_main[, reason_raw := normalize_reason_text(reason_raw)]",
  "reason_long_main <- reason_long_main[!is.na(reason_raw) & reason_raw != \"\"]",
  "",
  "reason_long_other <- melt(",
  "  AE,",
  "  id.vars = \"row_id___\",",
  "  measure.vars = reason_cols_other,",
  "  variable.name = \"reason_other_source_col\",",
  "  value.name = \"reason_r_non_FM_otheraw\",",
  "  variable.factor = FALSE",
  ")",
  "",
  "reason_long_other[, reason_r_non_FM_otheraw := normalize_reason_text(reason_r_non_FM_otheraw)]",
  "reason_long_other <- reason_long_other[!is.na(reason_r_non_FM_otheraw) & reason_r_non_FM_otheraw != \"\"]",
  "reason_long_other[, reason_source_col := str_remove(reason_other_source_col, \"_other$\")]",
  "",
  "reason_long <- merge(",
  "  reason_long_main,",
  "  reason_long_other[, .(row_id___, reason_source_col, reason_r_non_FM_otheraw)],",
  "  by = c(\"row_id___\", \"reason_source_col\"),",
  "  all.x = TRUE",
  ")",
  "",
  "reason_long[, reason_final := fifelse(",
  "  !is.na(reason_r_non_FM_otheraw) & reason_r_non_FM_otheraw != \"\",",
  "  reason_r_non_FM_otheraw,",
  "  reason_raw",
  ")]",
  "",
  "reason_long <- reason_long[!is.na(reason_final) & reason_final != \"\"]",
  "",
  "cat(\"Reason long table rows:\", nrow(reason_long), \"\\n\")",
  "cat(\"Reason long processing completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 6) CLASSIFY REASONS",
  "# ============================================================",
  "",
  "cat(\"\\nClassifying reasons...\\n\")",
  "t0 <- Sys.time()",
  "",
  "reason_long[, main_reason := detect_main_reason(reason_final)]",
  "reason_long[, abs_reason := NA_character_]",
  "reason_long[, nc_reason := NA_character_]",
  "",
  "reason_long[main_reason == \"r_non_FM_Absent\", abs_reason := detect_abs_reason(reason_final)]",
  "reason_long[main_reason == \"r_non_FM_NC\", nc_reason := detect_nc_reason(reason_final)]",
  "",
  "cat(\"Reason classification completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 7) WIDE REASON TABLES",
  "# ============================================================",
  "",
  "cat(\"\\nBuilding reason wide tables...\\n\")",
  "t0 <- Sys.time()",
  "",
  "reason_group_cols <- c(",
  "  \"Country\",",
  "  \"Region\",",
  "  \"District\",",
  "  \"Response\",",
  "  \"roundNumber\",",
  "  \"Vaccine.type\"",
  ")",
  "",
  "main_reason_wide <- dcast(",
  "  reason_long[!is.na(main_reason) & main_reason != \"\"],",
  "  Country + Region + District + Response + roundNumber + Vaccine.type ~ main_reason,",
  "  fun.aggregate = length,",
  "  value.var = \"main_reason\"",
  ")",
  "",
  "abs_reason_wide <- dcast(",
  "  reason_long[!is.na(abs_reason) & abs_reason != \"\"],",
  "  Country + Region + District + Response + roundNumber + Vaccine.type ~ abs_reason,",
  "  fun.aggregate = length,",
  "  value.var = \"abs_reason\"",
  ")",
  "",
  "nc_reason_wide <- dcast(",
  "  reason_long[!is.na(nc_reason) & nc_reason != \"\"],",
  "  Country + Region + District + Response + roundNumber + Vaccine.type ~ nc_reason,",
  "  fun.aggregate = length,",
  "  value.var = \"nc_reason\"",
  ")",
  "",
  "for (v in setdiff(main_reason_vars, names(main_reason_wide))) main_reason_wide[, (v) := 0L]",
  "for (v in setdiff(abs_reason_vars, names(abs_reason_wide))) abs_reason_wide[, (v) := 0L]",
  "for (v in setdiff(nc_reason_vars, names(nc_reason_wide))) nc_reason_wide[, (v) := 0L]",
  "",
  "cat(\"Reason wide tables completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 8) SOCIAL MOBILIZATION - CORRECT NIGERIA CODEBOOK",
  "# ============================================================",
  "",
  "cat(\"\\nProcessing social mobilization...\\n\")",
  "t0 <- Sys.time()",
  "",
  "sm_cols <- grep(\"^SourceInfo_house\", names(AE), value = TRUE, ignore.case = TRUE)",
  "",
  "if (length(sm_cols) > 0) {",
  "  ",
  "  sm_long <- melt(",
  "    AE,",
  "    id.vars = c(",
  "      \"row_id___\",",
  "      \"Country\",",
  "      \"Region\",",
  "      \"District\",",
  "      \"Response\",",
  "      \"roundNumber\",",
  "      \"Vaccine.type\"",
  "    ),",
  "    measure.vars = sm_cols,",
  "    variable.name = \"sm_col\",",
  "    value.name = \"sm_raw\",",
  "    variable.factor = FALSE",
  "  )",
  "  ",
  "  sm_long[, sm_raw := trimws(tolower(as.character(sm_raw)))]",
  "  sm_long[sm_raw %in% c(\"\", \"na\", \"nan\", \"null\"), sm_raw := NA_character_]",
  "  sm_long <- sm_long[!is.na(sm_raw)]",
  "  ",
  "  sm_long <- sm_long[",
  "    ,",
  "    .(sm_code = unlist(strsplit(sm_raw, \"\\\\s+\"))),",
  "    by = .(",
  "      row_id___,",
  "      Country,",
  "      Region,",
  "      District,",
  "      Response,",
  "      roundNumber,",
  "      Vaccine.type,",
  "      sm_col",
  "    )",
  "  ]",
  "  ",
  "  sm_long[, sm_code := trimws(sm_code)]",
  "  sm_long <- sm_long[sm_code != \"\"]",
  "  ",
  "  sm_unknown_codes <- setdiff(unique(sm_long$sm_code), sm_map_dt$sm_code)",
  "  ",
  "  if (length(sm_unknown_codes) > 0) {",
  "    cat(\"\\nWARNING: Unknown SourceInfo codes detected:\\n\")",
  "    print(sm_unknown_codes)",
  "  }",
  "  ",
  "  sm_long <- merge(",
  "    sm_long,",
  "    sm_map_dt,",
  "    by = \"sm_code\",",
  "    all.x = FALSE,",
  "    all.y = FALSE",
  "  )",
  "  ",
  "  sm_wide <- dcast(",
  "    sm_long,",
  "    Country + Region + District + Response + roundNumber + Vaccine.type ~ sm_type,",
  "    fun.aggregate = length,",
  "    value.var = \"sm_type\"",
  "  )",
  "  ",
  "  for (v in setdiff(sm_vars, names(sm_wide))) sm_wide[, (v) := 0L]",
  "  ",
  "  sm_wide[, sm_total_sources := rowSums(.SD, na.rm = TRUE), .SDcols = sm_vars]",
  "  sm_wide[, sm_total_awareness_sources := rowSums(.SD, na.rm = TRUE), .SDcols = sm_aware_vars]",
  "  ",
  "} else {",
  "  ",
  "  sm_wide <- unique(AE[, .(",
  "    Country,",
  "    Region,",
  "    District,",
  "    Response,",
  "    roundNumber,",
  "    Vaccine.type",
  "  )])",
  "  ",
  "  for (v in sm_vars) sm_wide[, (v) := 0L]",
  "  ",
  "  sm_wide[, sm_total_sources := 0L]",
  "  sm_wide[, sm_total_awareness_sources := 0L]",
  "}",
  "",
  "cat(\"SM processing completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 9) BASE REPOSITORY AGGREGATION",
  "# ============================================================",
  "",
  "cat(\"\\nAggregating base repository...\\n\")",
  "t0 <- Sys.time()",
  "",
  "AK_base <- AE[",
  "  ,",
  "  .(",
  "    start_date = min(date, na.rm = TRUE),",
  "    end_date = max(date, na.rm = TRUE),",
  "    u5_present = sum(u5_present, na.rm = TRUE),",
  "    u5_FM = sum(u5_FM, na.rm = TRUE),",
  "    missed_child = sum(missed_child, na.rm = TRUE)",
  "  ),",
  "  by = .(",
  "    Country,",
  "    Region,",
  "    District,",
  "    Response,",
  "    Vaccine.type,",
  "    roundNumber",
  "  )",
  "]",
  "",
  "AK_base[, round_start_date := start_date]",
  "AK_base[, year := lubridate::year(start_date)]",
  "AK_base[, cv := round(u5_FM / u5_present, 2)]",
  "AK_base[is.nan(cv) | is.infinite(cv), cv := NA_real_]",
  "",
  "cat(\"Base aggregation completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 10) MERGE FINAL REPOSITORY",
  "# ============================================================",
  "",
  "cat(\"\\nMerging final repository...\\n\")",
  "t0 <- Sys.time()",
  "",
  "setkeyv(AK_base, reason_group_cols)",
  "setkeyv(main_reason_wide, reason_group_cols)",
  "setkeyv(abs_reason_wide, reason_group_cols)",
  "setkeyv(nc_reason_wide, reason_group_cols)",
  "setkeyv(sm_wide, reason_group_cols)",
  "",
  "AK <- merge(",
  "  AK_base,",
  "  main_reason_wide[, c(reason_group_cols, main_reason_vars), with = FALSE],",
  "  by = reason_group_cols,",
  "  all.x = TRUE",
  ")",
  "",
  "AK <- merge(",
  "  AK,",
  "  abs_reason_wide[, c(reason_group_cols, abs_reason_vars), with = FALSE],",
  "  by = reason_group_cols,",
  "  all.x = TRUE",
  ")",
  "",
  "AK <- merge(",
  "  AK,",
  "  nc_reason_wide[, c(reason_group_cols, nc_reason_vars), with = FALSE],",
  "  by = reason_group_cols,",
  "  all.x = TRUE",
  ")",
  "",
  "AK <- merge(",
  "  AK,",
  "  sm_wide[, c(",
  "    reason_group_cols,",
  "    sm_vars,",
  "    \"sm_total_sources\",",
  "    \"sm_total_awareness_sources\"",
  "  ), with = FALSE],",
  "  by = reason_group_cols,",
  "  all.x = TRUE",
  ")",
  "",
  "count_cols <- c(",
  "  main_reason_vars,",
  "  abs_reason_vars,",
  "  nc_reason_vars,",
  "  sm_vars,",
  "  \"sm_total_sources\",",
  "  \"sm_total_awareness_sources\"",
  ")",
  "",
  "for (cc in count_cols) {",
  "  set(AK, i = which(is.na(AK[[cc]])), j = cc, value = 0L)",
  "}",
  "",
  "AK[",
  "  ,",
  "  total_main_reasons :=",
  "    r_non_FM_Absent +",
  "    r_non_FM_hh_notvisited +",
  "    r_non_FM_vaccinated_but_not_FM +",
  "    r_non_FM_sleep +",
  "    r_non_FM_child_is_a_visitor +",
  "    r_non_FM_NC +",
  "    r_non_FM_childnotborn +",
  "    r_non_FM_security +",
  "    r_non_FM_other",
  "]",
  "",
  "AK[",
  "  ,",
  "  abs_detail_total :=",
  "    abs_reason_other +",
  "    abs_reason_travelled +",
  "    abs_reason_farm +",
  "    abs_reason_market +",
  "    abs_reason_school +",
  "    abs_reason_in_playground",
  "]",
  "",
  "AK[",
  "  ,",
  "  nc_detail_total :=",
  "    nc_reason_no_felt_need +",
  "    nc_reason_child_sick +",
  "    nc_reason_vaccines_safety +",
  "    nc_reason_religious_cultural +",
  "    nc_reason_no_care_giver_consent +",
  "    nc_reason_poliofree +",
  "    nc_reason_too_many_rnd +",
  "    nc_reason_others +",
  "    nc_reason_covid_19 +",
  "    nc_reason_nopvconcern",
  "]",
  "",
  "AK[, check_missed := missed_child - total_main_reasons]",
  "AK[, unexplained_missed := pmax(check_missed, 0)]",
  "AK[, overreported_reasons := pmax(-check_missed, 0)]",
  "AK[, explained_ratio := fifelse(missed_child > 0, round(total_main_reasons / missed_child, 3), NA_real_)]",
  "AK[, unexplained_ratio := fifelse(missed_child > 0, round(unexplained_missed / missed_child, 3), NA_real_)]",
  "",
  "AK[, check_abs_detail := r_non_FM_Absent - abs_detail_total]",
  "AK[, check_nc_detail := r_non_FM_NC - nc_detail_total]",
  "",
  "# Nigeria has coded SourceInfo but not a reliable caregiver-informed denominator in this builder.",
  "# Therefore SM reconciliation is based on awareness source presence and Not Aware reporting.",
  "AK[",
  "  ,",
  "  sm_reconciliation_flag := fifelse(",
  "    sm_total_awareness_sources == 0 & sm_not_aware > 0,",
  "    \"Not aware reported\",",
  "    fifelse(",
  "      sm_total_awareness_sources == 0,",
  "      \"No source recorded\",",
  "      \"SM source recorded\"",
  "    )",
  "  )",
  "]",
  "",
  "AK[",
  "  ,",
  "  reconciliation_flag := fifelse(",
  "    check_missed == 0,",
  "    \"Consistent\",",
  "    fifelse(",
  "      check_missed > 0 & total_main_reasons == 0,",
  "      \"No reasons recorded\",",
  "      fifelse(",
  "        check_missed > 0,",
  "        \"Partial reasons recorded\",",
  "        fifelse(",
  "          check_missed < 0,",
  "          \"Overlapping reasons\",",
  "          \"Unknown\"",
  "        )",
  "      )",
  "    )",
  "  )",
  "]",
  "",
  "AK[",
  "  ,",
  "  abs_detail_flag := fifelse(",
  "    check_abs_detail == 0,",
  "    \"Abs detail consistent\",",
  "    fifelse(",
  "      check_abs_detail > 0,",
  "      \"Abs detail incomplete\",",
  "      fifelse(",
  "        check_abs_detail < 0,",
  "        \"Abs detail overlapping\",",
  "        \"Unknown\"",
  "      )",
  "    )",
  "  )",
  "]",
  "",
  "AK[",
  "  ,",
  "  nc_detail_flag := fifelse(",
  "    check_nc_detail == 0,",
  "    \"NC detail consistent\",",
  "    fifelse(",
  "      check_nc_detail > 0,",
  "      \"NC detail incomplete\",",
  "      fifelse(",
  "        check_nc_detail < 0,",
  "        \"NC detail overlapping\",",
  "        \"Unknown\"",
  "      )",
  "    )",
  "  )",
  "]",
  "",
  "AK[",
  "  ,",
  "  qc_flag := fifelse(",
  "    reconciliation_flag == \"Consistent\" &",
  "      abs_detail_flag == \"Abs detail consistent\" &",
  "      nc_detail_flag == \"NC detail consistent\",",
  "    \"OK\",",
  "    \"Needs review\"",
  "  )",
  "]",
  "",
  "# ============================================================",
  "# 10B) SM ANALYTICS INDICATORS",
  "# ============================================================",
  "",
  "AK[",
  "  ,",
  "  sm_intensity_group := fifelse(",
  "    sm_total_awareness_sources == 0,",
  "    \"No awareness source\",",
  "    fifelse(",
  "      sm_total_awareness_sources == 1,",
  "      \"One awareness source\",",
  "      fifelse(",
  "        sm_total_awareness_sources <= 3,",
  "        \"2-3 awareness sources\",",
  "        \"4+ awareness sources\"",
  "      )",
  "    )",
  "  )",
  "]",
  "",
  "AK[",
  "  ,",
  "  sm_non_compliance_pressure := fifelse(",
  "    sm_total_awareness_sources == 0 & r_non_FM_NC > 0,",
  "    \"Non-compliance with no awareness source\",",
  "    fifelse(",
  "      sm_total_awareness_sources > 0 & r_non_FM_NC > 0,",
  "      \"Non-compliance despite awareness\",",
  "      fifelse(",
  "        sm_total_awareness_sources > 0 & r_non_FM_NC == 0,",
  "        \"Awareness with no non-compliance\",",
  "        \"No SM / no non-compliance\"",
  "      )",
  "    )",
  "  )",
  "]",
  "",
  "AK[",
  "  ,",
  "  sm_gap_flag := fifelse(",
  "    sm_total_awareness_sources == 0,",
  "    \"SM gap detected\",",
  "    \"SM source recorded\"",
  "  )",
  "]",
  "",
  "AK[",
  "  ,",
  "  sm_priority_flag := fifelse(",
  "    sm_total_awareness_sources == 0 & cv < 0.9,",
  "    \"High priority SM gap\",",
  "    fifelse(",
  "      r_non_FM_NC > 0 & sm_health_worker == 0 & sm_vcm_unicef == 0,",
  "      \"Community resistance / weak technical source\",",
  "      fifelse(",
  "        sm_not_aware > 0,",
  "        \"Not aware reported\",",
  "        \"No major SM alert\"",
  "      )",
  "    )",
  "  )",
  "]",
  "",
  "",
  "# ============================================================",
  "# 10B.1) FINAL SANITIZATION BEFORE EXPORT",
  "# ============================================================",
  "",
  "cat(\"\\nApplying final Nigeria sanitation and consistency checks...\\n\")",
  "AK <- sanitize_nigeria_im_output(AK)",
  "AK <- enterprise_clean_nigeria_export(AK)",
  "",
  "cat(\"\\nDenominator QC flags after sanitation:\\n\")",
  "if (\"denominator_qc_flag\" %in% names(AK)) {",
  "  print(AK[, .N, by = denominator_qc_flag][order(-N)])",
  "}",
  "",
  "# ============================================================",
  "# 10C) FINAL COLUMN ORDER - HARMONIZED",
  "# ============================================================",
  "",
  "final_col_order <- c(",
  "  \"Country\",",
  "  \"Region\",",
  "  \"District\",",
  "  \"Response\",",
  "  \"Vaccine.type\",",
  "  \"roundNumber\",",
  "  \"round_start_date\",",
  "  \"start_date\",",
  "  \"end_date\",",
  "  \"year\",",
  "  \"u5_present\",",
  "  \"u5_FM\",",
  "  \"missed_child\",",
  "  \"cv\",",
  "  \"denominator_reconstructed\",",
  "  \"numerator_reconstructed\",",
  "  \"numerator_capped\",",
  "  \"denominator_qc_flag\",",
  "  ",
  "  main_reason_vars,",
  "  abs_reason_vars,",
  "  nc_reason_vars,",
  "  ",
  "  \"total_main_reasons\",",
  "  \"abs_detail_total\",",
  "  \"nc_detail_total\",",
  "  ",
  "  \"check_missed\",",
  "  \"unexplained_missed\",",
  "  \"overreported_reasons\",",
  "  \"explained_ratio\",",
  "  \"unexplained_ratio\",",
  "  \"check_abs_detail\",",
  "  \"check_nc_detail\",",
  "  ",
  "  sm_vars,",
  "  \"sm_total_sources\",",
  "  \"sm_total_awareness_sources\",",
  "  ",
  "  qc_vars,",
  "  sm_indicator_vars",
  ")",
  "",
  "existing_final_cols <- intersect(final_col_order, names(AK))",
  "remaining_cols <- setdiff(names(AK), existing_final_cols)",
  "",
  "setcolorder(AK, c(existing_final_cols, remaining_cols))",
  "",
  "cat(\"Final merge completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "",
  "# ============================================================",
  "# 11) QC",
  "# ============================================================",
  "",
  "cat(\"\\n================ QC SUMMARY ================\\n\")",
  "",
  "cat(\"\\nMain reason totals:\\n\")",
  "print(colSums(as.data.frame(AK[, ..main_reason_vars]), na.rm = TRUE))",
  "",
  "cat(\"\\nAbsence reason totals:\\n\")",
  "print(colSums(as.data.frame(AK[, ..abs_reason_vars]), na.rm = TRUE))",
  "",
  "cat(\"\\nNon-compliance reason totals:\\n\")",
  "print(colSums(as.data.frame(AK[, ..nc_reason_vars]), na.rm = TRUE))",
  "",
  "cat(\"\\nSocial mobilization totals:\\n\")",
  "print(colSums(as.data.frame(AK[, ..sm_vars]), na.rm = TRUE))",
  "",
  "cat(\"\\nSM total sources:\\n\")",
  "print(sum(AK$sm_total_sources, na.rm = TRUE))",
  "",
  "cat(\"\\nSM total awareness sources excluding Not Aware:\\n\")",
  "print(sum(AK$sm_total_awareness_sources, na.rm = TRUE))",
  "",
  "cat(\"\\nReconciliation flags:\\n\")",
  "print(AK[, .N, by = reconciliation_flag][order(-N)])",
  "",
  "cat(\"\\nAbs detail flags:\\n\")",
  "print(AK[, .N, by = abs_detail_flag][order(-N)])",
  "",
  "cat(\"\\nNC detail flags:\\n\")",
  "print(AK[, .N, by = nc_detail_flag][order(-N)])",
  "",
  "cat(\"\\nSM reconciliation flags:\\n\")",
  "print(AK[, .N, by = sm_reconciliation_flag][order(-N)])",
  "",
  "cat(\"\\nQC flags:\\n\")",
  "print(AK[, .N, by = qc_flag][order(-N)])",
  "",
  "cat(\"\\nSM intensity groups:\\n\")",
  "print(AK[, .N, by = sm_intensity_group][order(-N)])",
  "",
  "cat(\"\\nSM non-compliance pressure:\\n\")",
  "print(AK[, .N, by = sm_non_compliance_pressure][order(-N)])",
  "",
  "cat(\"\\nSM gap flags:\\n\")",
  "print(AK[, .N, by = sm_gap_flag][order(-N)])",
  "",
  "cat(\"\\nSM priority flags:\\n\")",
  "print(AK[, .N, by = sm_priority_flag][order(-N)])",
  "",
  "cat(\"\\nRows where total_main_reasons > missed_child:\\n\")",
  "print(",
  "  AK[",
  "    total_main_reasons > missed_child,",
  "    .(",
  "      Country,",
  "      Region,",
  "      District,",
  "      Response,",
  "      roundNumber,",
  "      missed_child,",
  "      total_main_reasons,",
  "      reconciliation_flag",
  "    )",
  "  ][1:20]",
  ")",
  "",
  "cat(\"\\nRows where u5_present is 0 or missing:\\n\")",
  "print(",
  "  AK[",
  "    is.na(u5_present) | u5_present == 0,",
  "    .(",
  "      Country,",
  "      Region,",
  "      District,",
  "      Response,",
  "      roundNumber,",
  "      u5_present,",
  "      u5_FM,",
  "      missed_child",
  "    )",
  "  ][1:20]",
  ")",
  "",
  "cat(\"\\n============================================\\n\")",
  "",
  "# ============================================================",
  "# 12) EXPORT",
  "# ============================================================",
  "",
  "cat(\"\\nWriting output...\\n\")",
  "t0 <- Sys.time()",
  "",
  "fwrite(AK, out_file)",
  "",
  "cat(\"Export completed in:\", round(difftime(Sys.time(), t0, units = \"secs\"), 1), \"seconds\\n\")",
  "cat(\"\\nNigeria IM repository successfully written to:\\n\", out_file, \"\\n\")",
  "",
  "",
  "",
  "",
  ""
)


# ============================================================
# HELPERS
# ============================================================
parse_mixed_dates <- function(x) {
  x <- as.character(x)
  suppressWarnings(
    dplyr::coalesce(
      ymd(x),
      dmy(x),
      mdy(x),
      ymd_hms(x),
      dmy_hms(x),
      mdy_hms(x)
    )
  )
}

clean_numeric <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  x[x %in% c("", " ", "n/a", "NA", "NaN", "null", "NULL")] <- "0"
  suppressWarnings(as.numeric(x))
}

# ============================================================
# UNIVERSAL SPECIAL MISSING / NUMERIC SANITIZER
# Fixes special missing codes such as -999/-998/-997 before row sums and QC
# ============================================================
SPECIAL_MISSING_CODES <- c(
  -999, -998, -997, -996, -995,
  999,  998,  997,  996
)

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

clean_yes_no_numeric <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  dplyr::case_when(
    x %in% c("Y", "YES", "Yes", "yes", "1", "TRUE", "True", "true") ~ 1,
    x %in% c("N", "NO", "No", "no", "0", "FALSE", "False", "false") ~ 0,
    x %in% c("", " ", "n/a", "NA", "NaN", "null", "NULL") ~ 0,
    TRUE ~ suppressWarnings(as.numeric(x))
  )
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
        } else if (inherits(proto, "POSIXct")) {
          x[[m]] <- as.POSIXct(rep(NA_character_, nrow(x)), origin = "1970-01-01")
        } else if (is.logical(proto)) {
          x[[m]] <- rep(NA, nrow(x))
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
# SOCIAL MOBILIZATION HELPERS - OPTIMIZED VECTORIZED VERSION
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

# Vectorized version - processes all rows at once for speed
extract_sm_from_text <- function(df, cols) {
  cols <- intersect(cols, names(df))
  n <- nrow(df)
  
  # Initialize result matrix
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
  
  # Combine all text columns efficiently
  txt <- apply(df[, cols, drop = FALSE], 1, function(x) {
    paste(normalize_sm_text(x), collapse = " ")
  })
  
  txt <- gsub("[[:space:]]+", " ", txt)
  txt <- trimws(txt)
  
  # Remove non-informative words in one pass
  txt <- gsub(
    regex("\\b(oui|yes|non|no|0|1|00|nn|na|n/a|ras|personal|people|sociaux|other people|la sh|pas de probleme|bien passe|non informe)\\b", 
          ignore_case = TRUE),
    " ",
    txt
  )
  txt <- gsub("[[:space:]]+", " ", txt)
  txt <- trimws(txt)
  
  # Detect space-separated format (Mauritania style)
  is_space_sep <- grepl("^[a-z_]+( [a-z_]+)*$", txt) & !grepl(" ", txt) & nchar(txt) < 500
  space_sep_idx <- which(is_space_sep)
  free_text_idx <- which(!is_space_sep)
  
  # Process space-separated rows (Mauritania format)
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
        } else if (token %in% c("health_worker", "hworker", "agent de sante", "personnel de sante", 
                                "hopital", "hospital", "مستشفى", "المستوصف", "ممرضة", "طاقم طبي")) {
          result[idx, "hworker"] <- 1
        } else if (token %in% c("mob_vanpa", "van pa", "megaphone car", "haut parleur", "مكبرات الصوت", "الفرق المتنقلة")) {
          result[idx, "mob_vanpa"] <- 1
        } else if (token %in% c("town_crier", "gong_gong", "crieur public", "تحسيس")) {
          result[idx, "town_crier"] <- 1
        } else if (token %in% c("volunteers", "volunteer", "benevole", "جمعية", "avs")) {
          result[idx, "volunteers"] <- 1
        } else if (token %in% c("com_info_centre", "community information centre", "centre d information")) {
          result[idx, "com_infocentre"] <- 1
        } else if (token %in% c("community_leader", "community leader", "chef de quartier", "voisin", "الجيران")) {
          result[idx, "community_leader"] <- 1
        } else if (token %in% c("religious_leader", "religious leader", "imam", "المسجد")) {
          result[idx, "religious_leader"] <- 1
        } else if (token %in% c("mobilemessaging_socialmedia", "social media", "facebook", "whatsapp", 
                                "sms", "telephone", "وسائل التواصل الاجتماعي", "فيسبوك")) {
          result[idx, "mobile_social_media"] <- 1
        } else if (token %in% c("h2h_mobilizer", "house to house", "door to door", "bouche a oreille", "العائلة")) {
          result[idx, "h2h_mobilizer"] <- 1
        } else if (token %in% c("mourchidate", "مرشدون", "مرشدات")) {
          result[idx, "mourchidate"] <- 1
        } else if (token %in% c("mosque", "mosquee", "masjid")) {
          result[idx, "mosque"] <- 1
        } else if (token %in% c("vaccinators", "vaccinator", "vaccinateurs", "ملقحات", "محققين")) {
          result[idx, "vaccinators"] <- 1
        } else if (token %in% c("sticker", "poster", "affiche", "ملصقات")) {
          result[idx, "sticker"] <- 1
        } else if (token %in% c("newspaper", "الأعلام")) {
          result[idx, "newspaper"] <- 1
        } else if (token %in% c("teachers_student", "school", "ecole", "école", "مدرسة", "معلمة")) {
          result[idx, "teachers_student"] <- 1
        } else if (token %in% c("iec_materials", "محاضرات", "التطعيم")) {
          result[idx, "iec_materials"] <- 1
        }
      }
    }
  }
  
  # Process free-text rows (Algeria, etc.) - vectorized for speed
  if (length(free_text_idx) > 0) {
    txt_free <- txt[free_text_idx]
    
    result[free_text_idx, "tv"] <- as.integer(str_detect(txt_free, regex("\\btv\\b|television|t[eé]l[eé]vision|تلفاز|التلفاز|التلفزة|قنواة التلفاز النهار", ignore_case = TRUE)))
    result[free_text_idx, "radio"] <- as.integer(str_detect(txt_free, regex("\\bradio\\b|مذياع|المذياع", ignore_case = TRUE)))
    result[free_text_idx, "others"] <- as.integer(str_detect(txt_free, regex("\\bothers\\b|\\bother\\b|\\bautres\\b|\\bautre\\b|اخر|اخرون|اشخاص اخرون|أشخاص آخرون|بين الاشخاص|بين الأشخاص|تداول بين الاشخاص|تداول بين الأشخاص|الأهل فيما بينهم|معلومات انتشرت في المجتمع|الشعب|الناس|rue|dans la rue|dans les rues|في الشارع", ignore_case = TRUE)))
    result[free_text_idx, "hworker"] <- as.integer(str_detect(txt_free, regex("\\bhealth_worker\\b|\\bhworker\\b|health worker|agent de sante|agent sante|personnel de sante|personnel de santé|طاقم طبي|طاقم الطبي|عامل بقطاع الصحة|عامل في قطاع الصحة|عامل ف الصحة|عامل في قطاع الصخة|من عمال الصحه|من عمال الصحه|ممرضة|ممرض|زوج ممرض|الام ممرضة|الأم ممرضة|المستوصف|االمستوصف|مستوصف|hopital|hospital|مستشفى|المستشفى|في المستشفى|من المستشفى|centre de sante|العيادة|في العيادة|العيادة متعددة الخدمات|قاعة العلاج|pharmacie|مصلحة الوقاية|مكتب التلقيح|المؤسسات العمومية للصحة الجوارية|المؤسسة العمومية للصحة الجوارية|مؤسسة عمومية للصحة الجوارية|عبادة متعددة الخدمات", ignore_case = TRUE)))
    result[free_text_idx, "mob_vanpa"] <- as.integer(str_detect(txt_free, regex("\\bmob_vanpa\\b|van pa|megaphone car|car with megaphone|haut parleur|مكبرات الصوت|مكبر الصوت|مبكر الصوت|ميكروفون|سيارة الاسعاف|سيارة  الاسعاف|ambulance a la maison haut parleur|ambulance a haut parleur|الفرق المتنقلة|الفرقة المتنقلة|فرقة متنقلة|الفرقة المتنقلة للتلقيح في الحي|equipe mobile|فريق متنقل", ignore_case = TRUE)))
    result[free_text_idx, "town_crier"] <- as.integer(str_detect(txt_free, regex("\\btown_crier\\b|town crier|gong_gong|gong gong|crieur public|crieurs public|تحسيس|الحملات التحسيسية", ignore_case = TRUE)))
    result[free_text_idx, "volunteers"] <- as.integer(str_detect(txt_free, regex("\\bvolunteers\\b|volunteer|benevole|benevoles|جمعية|الجمعية|جمعيات|الجمعيات|جمعية الحي|جمعيات الحي|avs\\b|evole", ignore_case = TRUE)))
    result[free_text_idx, "com_infocentre"] <- as.integer(str_detect(txt_free, regex("\\bcom_info_centre\\b|community information centre|centre d information|centre information", ignore_case = TRUE)))
    result[free_text_idx, "community_leader"] <- as.integer(str_detect(txt_free, regex("\\bcommunity_leader\\b|community leader|chef communautaire|leader communautaire|chef de quartier|quartier|les habitants du quartier|المجتمع|الجتمع|الجيران|جيران|الجار|الجارة|احد الجيران|أحد الجيران|من الجيران|les voisins|les voisin|voisin|voisine|voisins|voisinage|voisinages|neighbor|neighbour|voision|vois|أشخاص آخرون جيران|عبر الخيران|جيرانى|ااجيران|les voisin", ignore_case = TRUE)))
    result[free_text_idx, "religious_leader"] <- as.integer(str_detect(txt_free, regex("\\breligious_leader\\b|religious leader|leader religieux|chef religieux|imam|mosque|mosquee|masjid|mourchidate|المسجد|المساجد|مرشدون|مرشدات|مرشدون اجتماعين|مرشدون جتماعين", ignore_case = TRUE)))
    result[free_text_idx, "mobile_social_media"] <- as.integer(str_detect(txt_free, regex("\\bmobilemessaging_socialmedia\\b|social media|facebook|face book|facebok|facebok|fecbook|facook|fasbook|فيسبوك|فيس بوك|فايس بوك|الفيس بوك|الفايس بوك|الفايسبوك|الفسبوك|فيسبو|فيسب وك|فيسبوك\\.|فيس بوك،|فيس بوك ،|فيس بوك صفحة البلاد|وسائل التواصل الاجتماعي|وسائط الاجتماعية|وسائل التواصل|التواصل الاجتماعي|التواصل الإجتماعي|مواقع التواصل الاجتماعي|مواقع التواصل الإجتماعي|مواقع التوصل الاجتماعية|المواقع الإجتماعية|المواقع الاجتماعيه|موقع التواصل الاجتماعي|موقع التواصل الإجتماعي|موقع التواصل الآجتماعي fb|reseaux sociaux|reseux sociaux|reseau sociaux|reseau social|réseau sociaux|sms|الهاتف|هاتف|عبر الهاتف|telephone|t[eé]l[eé]phone|whatsapp|صفحة وات ساب|الانترنت|internet|إنترنت|منصات تواصل الإجتماعي|facebook", ignore_case = TRUE)))
    result[free_text_idx, "h2h_mobilizer"] <- as.integer(str_detect(txt_free, regex("\\bh2h_mobilizer\\b|house to house|door to door|bouche a oreille|bouche a l oreille|bouche a bouche|من الأهل|عن طريق العائلة|العائلة|عائلة|famille|la famille|الأهل|الاهل|الأقارب|الاقارب|اقارب|من عند فرد من العائلة|الأصدقاء|الاصدقاء|أصدقاء|اصدقاء|amis|amie|coll[eè]gue|زملاء العمل|مكان عمل الزوج|في عمل ولي الأمر|معلمة|المعلمة|المعلمة الحي|معلمة المدرسة|معلمة الحضانه|معلمة ابنها في الروضة|voisins et ecole|voisins et  ecole|voisins, ecole|voisins..ecole|voisin et ecole|ecole, voisins|ecole,vousins|school|[ée]cole|l'ecole|في المدرسة|من المدرسة|تلقيح في المدرسة|ecole des enfants|les voisins|voisins|voisin|voisine|les voisin|la famille|سمعت من عند فرد من العائلة", ignore_case = TRUE)))
    result[free_text_idx, "mourchidate"] <- as.integer(str_detect(txt_free, regex("\\bmourchidate\\b|مرشدون|مرشدات|مرشدون اجتماعين|مرشدون جتماعين", ignore_case = TRUE)))
    result[free_text_idx, "mosque"] <- as.integer(str_detect(txt_free, regex("\\bmosque\\b|mosquee|masjid|imam|المسجد|المساجد", ignore_case = TRUE)))
    result[free_text_idx, "vaccinators"] <- as.integer(str_detect(txt_free, regex("\\bvaccinators\\b|vaccinator|vaccinateurs|ملقحات|محققين|محققو الحملة|فريق تحقيق|فريق التحقيق|المحقق|فريف تحقيق|coll[eè]gue des vaccinateurs|فريق التحقيق", ignore_case = TRUE)))
    result[free_text_idx, "sticker"] <- as.integer(str_detect(txt_free, regex("\\bsticker\\b|poster|affiche|ملصقات|الملصقات|الملصقات في السحات العمومية", ignore_case = TRUE)))
    result[free_text_idx, "newspaper"] <- as.integer(str_detect(txt_free, regex("\\bnewspaper\\b|الأعلام", ignore_case = TRUE)))
    result[free_text_idx, "teachers_student"] <- as.integer(str_detect(txt_free, regex("\\bteachers_student\\b|teachers student|[ée]cole|ecole|school|college|coll[eè]ge|cr[eè]che|creche|crech|créche|créch|les creches|la cr[eè]che|روضة|روضة الاطفال|الحضانة|حضانة|حضانة الاطفال|دور الحضانة|المدرسة|مدرسة|قسم التحضيري|في قسم تحضيري|التحضيري|تلاميذ المتوسطة|معلمة|المعلمة|معلمة المدرسة|معلمة الحضانه|معلمة ابنها في الروضة|اطفال اخبرو اولياءهم|أطفال اخبرو اولياءهم|اشخاص لقحوا أبنائهم", ignore_case = TRUE)))
    result[free_text_idx, "iec_materials"] <- as.integer(str_detect(txt_free, regex("\\biec_materials\\b|iec materials|محاضرات|أنشطة ثقافية صحية|التطعيم|الحملات التحسيسية", ignore_case = TRUE)))
  }
  
  # Return as tibble
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
# INPUT READER - MULTI-FORMAT + EXTENSION-AGNOSTIC
# Supports: .rds, .qs, .csv, .txt, .tsv, .xlsx, .xls, .parquet, .feather, .arrow, .ipc
# Note: .rds files may actually be QS objects; this reader tries qs::qread first, then readRDS.
# ============================================================
SUPPORTED_INPUT_EXTENSIONS <- c(
  "rds", "qs", "csv", "txt", "tsv", "xlsx", "xls",
  "parquet", "feather", "arrow", "ipc"
)

read_csv_flexible <- function(input_file) {
  # Try standard comma-separated CSV first, then semicolon-delimited CSV.
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
    stop(
      "Unsupported file extension: .", ext,
      " for file: ", basename(input_file),
      ". Supported extensions are: ", paste(SUPPORTED_INPUT_EXTENSIONS, collapse = ", ")
    )
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
    # Some PADACORD files are QS objects saved with .rds extension.
    obj <- tryCatch(
      qs::qread(input_file),
      error = function(e) NULL
    )
    
    if (is.null(obj)) {
      obj <- tryCatch(
        readRDS(input_file),
        error = function(e) {
          stop("Cannot read file: ", basename(input_file), " - not valid QS or RDS format")
        }
      )
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

# ============================================================
# SOCIAL MOBILIZATION / SOURCE OF INFORMATION CANDIDATES
# ============================================================
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
# PREPAREDNESS LOOKUP
# ============================================================
load_preparedness_lookup <- function(preparedness_file) {
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

lookup_table <- load_preparedness_lookup(preparedness_file)

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

  # Botswana (form 8832) has no Region level in its administrative
  # boundaries -- District is the top level below Country. Mirror it into
  # Region (same pattern as form 8834 above) so it lines up with the
  # standard Country > Region > District template instead of being left
  # as NA (the generic fallback added in process_im_file() for any form
  # whose template omits Region).
  if (startsWith(file_name, "8832")) {
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

standardize_districts <- function(df) {
  needed <- c("Country", "Region", "District")
  if (!all(needed %in% names(df))) {
    return(df)
  }
  
  df %>%
    mutate(District = case_when(
      Country == "COTE D'IVOIRE" & Region == "MORONOU" & District == "MBATTO" ~ "MBATTO",
      Country == "COTE D'IVOIRE" & Region == "MORONOU" & District == "M'BATTO" ~ "MBATTO",
      Country == "COTE D'IVOIRE" & Region == "ABIDJAN1" & District == "ABOBO_EST" ~ "ABOBO EST",
      Country == "COTE D'IVOIRE" & Region == "ABIDJAN1" & District == "ABOBO_OUEST" ~ "ABOBO OUEST",
      Country == "CHAD" & Region == "BATHA" & District == "OUM_HADJER" ~ "OUM_HADJER",
      Country == "CHAD" & Region == "BATHA" & District == "OUM HADJER" ~ "OUM_HADJER",
      Country == "CHAD" & Region == "NDJAMENA" & District == "NDJAMENA_SUD" ~ "N'DJAMENA-SUD",
      Country == "CHAD" & Region == "NDJAMENA" & District == "NDJAMENA_NORD" ~ "N'DJAMENA-NORD",
      Country == "BENIN" & Region == "LITTORAL" & District == "COTONOU 1" ~ "COTONOU 1",
      Country == "BENIN" & Region == "LITTORAL" & District == "Cotonou I" ~ "COTONOU 1",
      TRUE ~ District
    ))
}

standardize_responses <- function(df) {
  needed <- c("Country", "Response")
  if (!all(needed %in% names(df))) {
    return(df)
  }
  
  df %>%
    mutate(Response = case_when(
      Country == "COTE D'IVOIRE" & str_detect(Response, "ABENGOUROU|ABOBO_EST|ABOBO_OUEST|ABOISSO") ~ "CIV-113DS-09-2020",
      Country == "MAL" & str_detect(Response, "Arfounda|BAMAKO|Banamba|Nara") ~ "MLI-12DS-01-2021",
      TRUE ~ Response
    ))
}

assign_vaccine_types <- function(df) {
  if (!all(c("Country", "Response", "roundNumber") %in% names(df))) {
    return(df)
  }
  
  df %>%
    mutate(
      roundNumber = toupper(roundNumber),
      roundNumber = case_when(
        str_detect(roundNumber, "0") ~ "Rnd0",
        str_detect(roundNumber, "1") ~ "Rnd1",
        str_detect(roundNumber, "2") ~ "Rnd2",
        str_detect(roundNumber, "3") ~ "Rnd3",
        str_detect(roundNumber, "4") ~ "Rnd4",
        str_detect(roundNumber, "5") ~ "Rnd5",
        str_detect(roundNumber, "6") ~ "Rnd6",
        TRUE ~ roundNumber
      )
    ) %>%
    mutate(
      Vaccine.type = case_when(
        Country == "BENIN" & Response == "KETOU" ~ "mOPV",
        Country == "COG" & Response == "Congo" ~ "nOPV",
        Country == "GUI" & Response == "Conakry" ~ "mOPV",
        Country == "COTE D'IVOIRE" & Response == "CIV-113DS-09-2020" ~ "mOPV",
        Country == "MAL" & Response == "MLI-12DS-01-2021" ~ "mOPV",
        str_detect(Response, "CHD-2025-10-0n_bOPV-NIDs|GUI-2025-01-NID_bOPV-nOPV") ~ "nOPV2 & bOPV",
        str_detect(Response, "BITTOU|MENAKA-mOPV2|BAMAKO-mOPV2|KANKAN-mOPV|MLI-12DS-01-2021-mOPV2|CONAKRY-mOPV|Ouagadogou|Bangui 1|GOTHEY|YOPOUGON|Golfe|MDG-2023-03-01_bOPV|BEN-xxDS-02-2020|BEN-26DS-08-2020|Chavuma-mOPV|Luapula-mOPV") ~ "mOPV",
        str_detect(Response, "nOPV|VPOn|TSHUAPA|Tanganyika|Liberia|Mauritania|KOUIBLY|Sierra Leone|SEN|CEN|MAL|BEN-39DS-01-2021|BERTOUA|EBOLOWA|EXNORD|ExtNord2023|ADDIS ABABA|Mekelle|AMANSIE SOUTH|CAF-2020-002|CENBLOCK|CENTRALBLK|CHA-17DS-02-2020|DONOMANGA|GNBnOPV|GOLFE|GOTHEYE|KEN-13DS-02-2021|MopUp2022|SSD-79DS-09-2020|ALG-2023-09-01_nOPV|ALG-2024-01-01_nOPV|nOPV2022|BEN-2023-09-01_nOPV|BFA-2023-05-01_nOPV|BFA-2023-09-01_nOPV|BFA-2024-02-01_nOPV|BITTOU-mOPV2|Ouagadogou-mOPV2|BOT-2023-02-01_nOPV|CAM-2023-05-01_nOPV|CAM-2023-08-01_nOPV|CAM-2024-02-01_nOPV|nOPV2023|nVPO|nVPO_Maradi|nVPO_Zinder|nVPO2|May2021|OPVb2021|OPVb2022|RSSmOPV10C2021|SEN_VPOn|UGAnOPV|VPOb|VPOb13ProV") ~ "nOPV2",
        str_detect(Response, "BOPV|bOPV|OPVb|WPV1") ~ "bOPV",
        str_detect(Response, "mOPV") ~ "mOPV",
        str_detect(Response, "OPV") & !str_detect(Response, "nOPV|bOPV|mOPV") ~ "bOPV",
        TRUE ~ "other"
      ),
      Response = case_when(
        Response == "nOPV2022" & Country == "GHA" ~ "nOPV2022",
        Response == "CENTRALBLK" ~ "DRC-7DS-02-2022",
        Response == "nOPV2022" & Country == "RDC" ~ "DRC-39DS-01-2021",
        Response %in% c("Tshuapa", "TSHUAPA") ~ "DRC-23DS-12-2020",
        Response == "VPOb13ProV" ~ "DRC-39DS-01-2021",
        TRUE ~ Response
      )
    ) %>%
    # This DRC-only patch (Response == "DRC-2025-02-01_nOPV_sNID") references
    # Region/District, which not every form's template has (e.g. form 8832 /
    # Botswana goes straight from Country to District with no Region level).
    # case_when() evaluates every referenced column for ALL rows regardless
    # of whether a row's condition can ever be TRUE, so simply referencing
    # a missing Region column here throws "object 'Region' not found" for
    # any form without one -- even though this branch would never match
    # non-DRC data anyway. Guard on column existence so forms lacking
    # Region/District just skip this DRC-specific override untouched.
    {
      if (all(c("Region", "District") %in% names(.))) {
        mutate(
          .,
          Vaccine.type = case_when(
            Response == "DRC-2025-02-01_nOPV_sNID" &
              roundNumber == "Rnd1" &
              Region %in% c("HAUT KATANGA", "HAUT LOMAMI", "TANGANIKA", "KINSHASA") ~ "nOPV2",
            Response == "DRC-2025-02-01_nOPV_sNID" &
              roundNumber == "Rnd1" &
              Region == "TSHOPO" &
              District %in% c("ALUNGULI", "FEREKENI", "KAILO", "LUBUTU", "OBOKOTE", "OPIENGE") ~ "bOPV",
            TRUE ~ Vaccine.type
          )
        )
      } else {
        .
      }
    }
}

create_summary_columns <- function(df, file_name) {
  is_algeria_8587 <- identical(file_name, ALGERIA_IM_FORM_ID)
  
  if (is_algeria_8587) {
    present_cols <- names(df)[names(df) %in% sprintf("HH[%s]/Total_U6_Present_HH", 1:10)]
    fm_cols <- names(df)[names(df) %in% sprintf("HH[%s]/U6_Vac_FM_HH", 1:10)]
  } else {
    present_cols <- names(df)[names(df) %in% sprintf("HH[%s]/Total_U5_Present_HH", 1:10)]
    fm_cols <- names(df)[names(df) %in% sprintf("HH[%s]/U5_Vac_FM_HH", 1:10)]
  }
  
  abs_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Tot_child_Absent_HH$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Tot_child_Absent_HH$")
  ))
  
  nc_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Tot_child_NC_HH$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Tot_child_NC_HH$")
  ))
  
  notvisited_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Tot_child_NotVisited_HH$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Tot_child_NotVisited_HH$")
  ))
  
  notrevisited_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Tot_child_NotRevisited$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Tot_child_NotRevisited$")
  ))
  
  asleep_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Tot_child_Asleep_HH$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Tot_child_Asleep_HH$")
  ))
  
  routine_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Tot_child_VaccinatedRoutine$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Tot_child_VaccinatedRoutine$")
  ))
  
  other_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Tot_child_Others_HH$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Tot_child_Others_HH$")
  ))
  
  caregiver_cols <- unique(c(
    get_regex_cols(df, "^HH\\[[0-9]+\\]/group1/Parent_Caregive_Inform_HH$"),
    get_regex_cols(df, "^HH\\[[0-9]+\\]/Parent_Caregive_Inform_HH$")
  ))
  
  abs_sick_hh_cols   <- get_regex_cols(df, algeria_abs_hh_patterns$r_abs_sick_hh)
  abs_school_hh_cols <- get_regex_cols(df, algeria_abs_hh_patterns$r_abs_school_hh)
  abs_play_hh_cols   <- get_regex_cols(df, algeria_abs_hh_patterns$r_abs_play_hh)
  abs_social_hh_cols <- get_regex_cols(df, algeria_abs_hh_patterns$r_abs_social_hh)
  abs_travel_hh_cols <- get_regex_cols(df, algeria_abs_hh_patterns$r_abs_travel_hh)
  abs_other_hh_cols  <- get_regex_cols(df, algeria_abs_hh_patterns$r_abs_other_hh)
  
  nc_childsick_hh_cols <- get_regex_cols(df, algeria_nc_hh_patterns$r_nc_child_sick_hh)
  nc_notdecide_hh_cols <- get_regex_cols(df, algeria_nc_hh_patterns$r_nc_not_decided_hh)
  nc_poliofree_hh_cols <- get_regex_cols(df, algeria_nc_hh_patterns$r_nc_polio_free_hh)
  nc_nopv_hh_cols      <- get_regex_cols(df, algeria_nc_hh_patterns$r_nc_nopv_hh)
  nc_other_hh_cols     <- get_regex_cols(df, algeria_nc_hh_patterns$r_nc_other_hh)
  
  sm_tv_hh_cols                  <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_tv_hh)
  sm_radio_hh_cols               <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_radio_hh)
  sm_others_hh_cols              <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_others_hh)
  sm_hworker_hh_cols             <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_hworker_hh)
  sm_mob_vanpa_hh_cols           <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_mob_vanpa_hh)
  sm_town_crier_hh_cols          <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_town_crier_hh)
  sm_volunteers_hh_cols          <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_volunteers_hh)
  sm_com_infocentre_hh_cols      <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_com_infocentre_hh)
  sm_community_leader_hh_cols    <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_community_leader_hh)
  sm_religious_leader_hh_cols    <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_religious_leader_hh)
  sm_mobile_social_media_hh_cols <- get_regex_cols(df, standard_sm_hh_patterns$sm_info_mobile_social_media_hh)
  
  sm_radio_alg_hh_cols         <- get_regex_cols(df, algeria_sm_hh_patterns$sm_info_radio_hh)
  sm_mourchidate_hh_cols       <- get_regex_cols(df, algeria_sm_hh_patterns$sm_info_mourchidate_hh)
  sm_mosque_hh_cols            <- get_regex_cols(df, algeria_sm_hh_patterns$sm_info_mosque_hh)
  sm_vaccinators_hh_cols       <- get_regex_cols(df, algeria_sm_hh_patterns$sm_info_vaccinators_hh)
  sm_h2h_mobilizer_hh_cols     <- get_regex_cols(df, algeria_sm_hh_patterns$sm_info_h2h_mobilizer_hh)
  sm_sticker_hh_cols           <- get_regex_cols(df, algeria_sm_hh_patterns$sm_info_sticker_hh)
  sm_others_alg_hh_cols        <- get_regex_cols(df, algeria_sm_hh_patterns$sm_info_others_hh)
  
  sm_text_cols <- unique(c(
    get_regex_cols(df, sm_text_patterns$sm_source_text_hh),
    get_regex_cols(df, sm_text_patterns$sm_other_text_hh),
    get_regex_cols(df, sm_text_patterns$sm_source_text_alg),
    get_regex_cols(df, sm_text_patterns$sm_other_text_alg)
  ))
  
  sm_text_parsed <- extract_sm_from_text(df, sm_text_cols)
  df2 <- bind_cols(df, sm_text_parsed)
  
  df2 %>%
    mutate(
      u5_present = safe_row_sum(., present_cols),
      u5_FM1 = safe_row_sum(., fm_cols),
      u5_FM = ifelse(u5_FM1 > u5_present & u5_present > 0, u5_present, u5_FM1),
      u5_FM = ifelse(is.na(u5_FM), 0, u5_FM),
      missed_child = pmax(0, u5_present - u5_FM),
      
      r_non_FM_Absent = safe_row_sum(., abs_cols),
      r_non_FM_NC = safe_row_sum(., nc_cols),
      r_non_FM_hh_notvisited = safe_row_sum(., notvisited_cols),
      r_non_FM_hh_notrevisited = safe_row_sum(., notrevisited_cols),
      r_non_FM_sleep = safe_row_sum(., asleep_cols),
      r_non_FM_vaccinatedRoutine = safe_row_sum(., routine_cols),
      r_non_FM_other = safe_row_sum(., other_cols),
      care_Giver_Informed_SIA = safe_row_sum(., caregiver_cols),
      
      r_abs_play_areas = safe_pick_first(., absence_total_candidates$r_abs_play_areas),
      r_abs_market = safe_pick_first(., absence_total_candidates$r_abs_market),
      r_abs_school = safe_pick_first(., absence_total_candidates$r_abs_school),
      r_abs_farm = safe_pick_first(., absence_total_candidates$r_abs_farm),
      r_abs_social_event = safe_pick_first(., absence_total_candidates$r_abs_social_event),
      r_abs_travelling = safe_pick_first(., absence_total_candidates$r_abs_travelling),
      r_abs_parent_absent = safe_pick_first(., absence_total_candidates$r_abs_parent_absent),
      r_abs_other_detail_form = safe_pick_first(., absence_total_candidates$r_abs_other_detail),
      
      r_abs_sick = safe_row_sum(., abs_sick_hh_cols),
      r_abs_school_hh = safe_row_sum(., abs_school_hh_cols),
      r_abs_play_hh = safe_row_sum(., abs_play_hh_cols),
      r_abs_social_hh = safe_row_sum(., abs_social_hh_cols),
      r_abs_travel_hh = safe_row_sum(., abs_travel_hh_cols),
      r_abs_other_hh = safe_row_sum(., abs_other_hh_cols),
      
      r_nc_religious_beliefs = safe_pick_first(., nc_total_candidates$r_nc_religious_beliefs),
      r_nc_side_effects = safe_pick_first(., nc_total_candidates$r_nc_side_effects),
      r_nc_too_many_doses = safe_pick_first(., nc_total_candidates$r_nc_too_many_doses),
      r_nc_child_sick_form = safe_pick_first(., nc_total_candidates$r_nc_child_sick),
      r_nc_covid = safe_pick_first(., nc_total_candidates$r_nc_covid),
      r_nc_other_detail_form = safe_pick_first(., nc_total_candidates$r_nc_other_detail),
      
      r_nc_child_sick_hh = safe_row_sum(., nc_childsick_hh_cols),
      r_nc_not_decided = safe_row_sum(., nc_notdecide_hh_cols),
      r_nc_polio_free = safe_row_sum(., nc_poliofree_hh_cols),
      r_nc_nopv = safe_row_sum(., nc_nopv_hh_cols),
      r_nc_other_hh = safe_row_sum(., nc_other_hh_cols),
      
      sm_info_tv_count                  = safe_pick_first(., sm_count_candidates$sm_info_tv),
      sm_info_radio_count               = safe_pick_first(., sm_count_candidates$sm_info_radio),
      sm_info_others_count              = safe_pick_first(., sm_count_candidates$sm_info_others),
      sm_info_hworker_count             = safe_pick_first(., sm_count_candidates$sm_info_hworker),
      sm_info_mob_vanpa_count           = safe_pick_first(., sm_count_candidates$sm_info_mob_vanpa),
      sm_info_town_crier_count          = safe_pick_first(., sm_count_candidates$sm_info_town_crier),
      sm_info_volunteers_count          = safe_pick_first(., sm_count_candidates$sm_info_volunteers),
      sm_info_com_infocentre_count      = safe_pick_first(., sm_count_candidates$sm_info_com_infocentre),
      sm_info_community_leader_count    = safe_pick_first(., sm_count_candidates$sm_info_community_leader),
      sm_info_religious_leader_count    = safe_pick_first(., sm_count_candidates$sm_info_religious_leader),
      sm_info_mobile_social_media_count = safe_pick_first(., sm_count_candidates$sm_info_mobile_social_media),
      
      sm_info_tv_hh                  = safe_row_sum(., sm_tv_hh_cols),
      sm_info_radio_hh               = safe_row_sum(., sm_radio_hh_cols),
      sm_info_others_hh              = safe_row_sum(., sm_others_hh_cols),
      sm_info_hworker_hh             = safe_row_sum(., sm_hworker_hh_cols),
      sm_info_mob_vanpa_hh           = safe_row_sum(., sm_mob_vanpa_hh_cols),
      sm_info_town_crier_hh          = safe_row_sum(., sm_town_crier_hh_cols),
      sm_info_volunteers_hh          = safe_row_sum(., sm_volunteers_hh_cols),
      sm_info_com_infocentre_hh      = safe_row_sum(., sm_com_infocentre_hh_cols),
      sm_info_community_leader_hh    = safe_row_sum(., sm_community_leader_hh_cols),
      sm_info_religious_leader_hh    = safe_row_sum(., sm_religious_leader_hh_cols),
      sm_info_mobile_social_media_hh = safe_row_sum(., sm_mobile_social_media_hh_cols),
      
      sm_info_radio_alg_hh         = safe_row_sum(., sm_radio_alg_hh_cols),
      sm_info_mourchidate_hh       = safe_row_sum(., sm_mourchidate_hh_cols),
      sm_info_mosque_hh            = safe_row_sum(., sm_mosque_hh_cols),
      sm_info_vaccinators_hh       = safe_row_sum(., sm_vaccinators_hh_cols),
      sm_info_h2h_mobilizer_hh     = safe_row_sum(., sm_h2h_mobilizer_hh_cols),
      sm_info_sticker_hh           = safe_row_sum(., sm_sticker_hh_cols),
      sm_info_others_alg_hh        = safe_row_sum(., sm_others_alg_hh_cols)
    ) %>%
    mutate(
      r_abs_other_detail = pmax(r_abs_other_detail_form, r_abs_other_hh, na.rm = TRUE),
      r_abs_school = pmax(r_abs_school, r_abs_school_hh, na.rm = TRUE),
      r_abs_play_areas = pmax(r_abs_play_areas, r_abs_play_hh, na.rm = TRUE),
      r_abs_social_event = pmax(r_abs_social_event, r_abs_social_hh, na.rm = TRUE),
      r_abs_travelling = pmax(r_abs_travelling, r_abs_travel_hh, na.rm = TRUE),
      
      r_nc_child_sick = pmax(r_nc_child_sick_form, r_nc_child_sick_hh, na.rm = TRUE),
      r_nc_other_detail = pmax(r_nc_other_detail_form, r_nc_other_hh, na.rm = TRUE),
      
      sm_info_tv = coalesce_max(sm_info_tv_count, sm_info_tv_hh, sm_info_tv_text),
      sm_info_radio = coalesce_max(sm_info_radio_count, sm_info_radio_hh, sm_info_radio_alg_hh, sm_info_radio_text),
      sm_info_others = coalesce_max(sm_info_others_count, sm_info_others_hh, sm_info_others_alg_hh, sm_info_others_text),
      sm_info_hworker = coalesce_max(sm_info_hworker_count, sm_info_hworker_hh, sm_info_hworker_text),
      sm_info_mob_vanpa = coalesce_max(sm_info_mob_vanpa_count, sm_info_mob_vanpa_hh, sm_info_mob_vanpa_text),
      sm_info_town_crier = coalesce_max(sm_info_town_crier_count, sm_info_town_crier_hh, sm_info_town_crier_text),
      sm_info_volunteers = coalesce_max(sm_info_volunteers_count, sm_info_volunteers_hh, sm_info_volunteers_text),
      sm_info_com_infocentre = coalesce_max(sm_info_com_infocentre_count, sm_info_com_infocentre_hh, sm_info_com_infocentre_text),
      sm_info_community_leader = coalesce_max(sm_info_community_leader_count, sm_info_community_leader_hh, sm_info_community_leader_text),
      sm_info_religious_leader = coalesce_max(sm_info_religious_leader_count, sm_info_religious_leader_hh, sm_info_religious_leader_text),
      sm_info_mobile_social_media = coalesce_max(sm_info_mobile_social_media_count, sm_info_mobile_social_media_hh, sm_info_mobile_social_media_text),
      
      sm_info_h2h_mobilizer = coalesce_max(sm_info_h2h_mobilizer_hh, sm_info_h2h_mobilizer_text),
      sm_info_mourchidate = coalesce_max(sm_info_mourchidate_hh, sm_info_mourchidate_text),
      sm_info_mosque = coalesce_max(sm_info_mosque_hh, sm_info_mosque_text),
      sm_info_vaccinators = coalesce_max(sm_info_vaccinators_hh, sm_info_vaccinators_text),
      sm_info_sticker = coalesce_max(sm_info_sticker_hh, sm_info_sticker_text),
      
      sm_total_sources =
        sm_info_tv + sm_info_radio + sm_info_others + sm_info_hworker +
        sm_info_mob_vanpa + sm_info_town_crier + sm_info_volunteers +
        sm_info_com_infocentre + sm_info_community_leader +
        sm_info_religious_leader + sm_info_mobile_social_media +
        sm_info_h2h_mobilizer + sm_info_mourchidate + sm_info_mosque +
        sm_info_vaccinators + sm_info_sticker +
        sm_info_newspaper_text + sm_info_teachers_student_text + sm_info_iec_materials_text,
      
      abs_detail_total =
        r_abs_sick + r_abs_play_areas + r_abs_market + r_abs_school +
        r_abs_farm + r_abs_social_event + r_abs_travelling +
        r_abs_parent_absent + r_abs_other_detail,
      
      nc_detail_total =
        r_nc_religious_beliefs + r_nc_side_effects + r_nc_too_many_doses +
        r_nc_child_sick + r_nc_covid + r_nc_other_detail +
        r_nc_not_decided + r_nc_polio_free + r_nc_nopv
    )
}

process_final_data <- function(df) {
  numeric_clean_cols <- intersect(
    c(
      "u5_present", "u5_FM1", "u5_FM", "missed_child",
      "r_non_FM_Absent", "r_non_FM_NC",
      "r_non_FM_hh_notvisited", "r_non_FM_hh_notrevisited",
      "r_non_FM_sleep", "r_non_FM_vaccinatedRoutine",
      "r_non_FM_other", "care_Giver_Informed_SIA",
      "sm_info_tv", "sm_info_radio", "sm_info_others", "sm_info_hworker",
      "sm_info_mob_vanpa", "sm_info_town_crier", "sm_info_volunteers",
      "sm_info_com_infocentre", "sm_info_community_leader",
      "sm_info_religious_leader", "sm_info_mobile_social_media",
      "sm_info_h2h_mobilizer", "sm_info_mourchidate", "sm_info_mosque",
      "sm_info_vaccinators", "sm_info_sticker",
      "sm_info_newspaper_text", "sm_info_teachers_student_text",
      "sm_info_iec_materials_text", "sm_total_sources",
      "r_abs_sick", "r_abs_play_areas", "r_abs_market",
      "r_abs_school", "r_abs_farm", "r_abs_social_event",
      "r_abs_travelling", "r_abs_parent_absent", "r_abs_other_detail",
      "r_nc_religious_beliefs", "r_nc_side_effects",
      "r_nc_too_many_doses", "r_nc_child_sick",
      "r_nc_covid", "r_nc_other_detail",
      "r_nc_not_decided", "r_nc_polio_free", "r_nc_nopv",
      "abs_detail_total", "nc_detail_total"
    ),
    names(df)
  )
  
  df %>%
    mutate(across(all_of(numeric_clean_cols), safe_numeric_zero)) %>%
    mutate(
      Country = case_when(
        Country == "DRC" ~ "RDC",
        Country == "Camerooun" ~ "CAE",
        Country == "BURKINA_FASO" ~ "BFA",
        Country == "CAMEROON" ~ "CAE",
        Country == "CHAD" ~ "CHD",
        TRUE ~ Country
      ),
      roundNumber = case_when(
        roundNumber == "RND2" ~ "Rnd2",
        TRUE ~ roundNumber
      ),
      
      # Keep original denominator values for QC/traceability
      u5_present_original = u5_present,
      u5_FM_original = u5_FM,
      missed_child_original = missed_child,
      
      # Reconstruct denominator when the denominator is missing/zero but FM and missed children exist.
      # Example: u5_present = 0, u5_FM = 917, missed_child = 81 => u5_present = 998.
      denominator_reconstructed = case_when(
        (is.na(u5_present) | u5_present <= 0) &
          coalesce(u5_FM, 0) > 0 &
          coalesce(missed_child, 0) > 0 ~ 1L,
        TRUE ~ 0L
      ),
      u5_present = case_when(
        denominator_reconstructed == 1L ~ coalesce(u5_FM, 0) + coalesce(missed_child, 0),
        TRUE ~ u5_present
      ),
      
      # If denominator is present but FM exceeds it, cap FM to denominator.
      u5_FM = ifelse(u5_FM > u5_present & u5_present > 0, u5_present, u5_FM),
      missed_child = pmax(0, u5_present - u5_FM),
      cv = ifelse(u5_present > 0, round(u5_FM / u5_present, 4), NA_real_),
      cv = case_when(
        is.infinite(cv) ~ NA_real_,
        cv < 0 ~ NA_real_,
        cv > 1 ~ 1,
        TRUE ~ cv
      ),
      
      reasons_total =
        r_non_FM_Absent +
        r_non_FM_NC +
        r_non_FM_hh_notvisited +
        r_non_FM_hh_notrevisited +
        r_non_FM_sleep +
        r_non_FM_vaccinatedRoutine +
        r_non_FM_other,
      
      abs_detail_total =
        r_abs_sick + r_abs_play_areas + r_abs_market + r_abs_school +
        r_abs_farm + r_abs_social_event + r_abs_travelling +
        r_abs_parent_absent + r_abs_other_detail,
      
      nc_detail_total =
        r_nc_religious_beliefs + r_nc_side_effects + r_nc_too_many_doses +
        r_nc_child_sick + r_nc_covid + r_nc_other_detail +
        r_nc_not_decided + r_nc_polio_free + r_nc_nopv,
      
      check_missed = missed_child - reasons_total,
      unexplained_missed = pmax(check_missed, 0),
      overreported_reasons = pmax(-check_missed, 0),
      explained_ratio = ifelse(missed_child > 0, round(reasons_total / missed_child, 3), NA_real_),
      unexplained_ratio = ifelse(missed_child > 0, round(unexplained_missed / missed_child, 3), NA_real_),
      
      check_abs_detail = r_non_FM_Absent - abs_detail_total,
      check_nc_detail = r_non_FM_NC - nc_detail_total,
      
      check_sm_info = care_Giver_Informed_SIA - sm_total_sources,
      sm_info_gap = pmax(check_sm_info, 0),
      sm_info_overlap = pmax(-check_sm_info, 0),
      
      denominator_qc_flag = case_when(
        denominator_reconstructed == 1L ~ "Missing denominator reconstructed",
        u5_present <= 0 & u5_FM > 0 ~ "Missing denominator unresolved",
        u5_FM_original > u5_present_original & u5_present_original > 0 ~ "FM capped to denominator",
        TRUE ~ "Denominator OK"
      ),
      
      reconciliation_flag = case_when(
        denominator_reconstructed == 1L ~ "Missing denominator reconstructed",
        check_missed == 0 ~ "Consistent",
        check_missed > 0 & reasons_total == 0 ~ "No reasons recorded",
        check_missed > 0 ~ "Partial reasons recorded",
        check_missed < 0 ~ "Overlapping reasons",
        TRUE ~ "Unknown"
      ),
      
      abs_detail_flag = case_when(
        check_abs_detail == 0 ~ "Abs detail consistent",
        check_abs_detail > 0 ~ "Abs detail incomplete",
        check_abs_detail < 0 ~ "Abs detail overlapping",
        TRUE ~ "Unknown"
      ),
      
      nc_detail_flag = case_when(
        check_nc_detail == 0 ~ "NC detail consistent",
        check_nc_detail > 0 ~ "NC detail incomplete",
        check_nc_detail < 0 ~ "NC detail overlapping",
        TRUE ~ "Unknown"
      ),
      
      sm_reconciliation_flag = case_when(
        care_Giver_Informed_SIA > 0 & sm_total_sources == 0 ~ "No source recorded",
        check_sm_info == 0 ~ "SM consistent",
        check_sm_info < 0 ~ "Multiple sources per informed HH",
        check_sm_info > 0 ~ "Some informed HH missing source",
        TRUE ~ "Unknown"
      ),
      
      qc_flag = case_when(
        denominator_qc_flag == "Missing denominator unresolved" ~ "Needs review",
        check_missed == 0 &
          check_abs_detail == 0 &
          check_nc_detail == 0 &
          check_sm_info <= 0 ~ "OK",
        TRUE ~ "Needs review"
      )
    )
}

# ============================================================
# ============================================================
# HARMONIZED SM INTELLIGENCE INDICATORS
# Compatible with both Regional IM and Nigeria IM structures
# Fixes missing sm_not_aware issue in Regional files
# ============================================================
add_sm_intelligence_indicators <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  
  needed_numeric <- c(
    "sm_total_sources",
    "sm_total_awareness_sources",
    "sm_not_aware",
    "r_non_compliance",
    "r_non_FM_NC",
    "cv",
    "sm_info_hworker",
    "sm_info_vaccinators",
    "sm_health_worker",
    "sm_vcm_unicef"
  )
  
  for (cc in needed_numeric) {
    if (!cc %in% names(df)) df[[cc]] <- 0
    df[[cc]] <- suppressWarnings(as.numeric(df[[cc]]))
    df[[cc]][is.na(df[[cc]])] <- 0
  }
  
  df <- df %>%
    mutate(
      sm_total_awareness_sources = pmax(0, sm_total_sources - sm_not_aware),
      r_non_compliance = case_when(
        is.na(r_non_compliance) ~ r_non_FM_NC,
        r_non_compliance == 0 & r_non_FM_NC > 0 ~ r_non_FM_NC,
        TRUE ~ r_non_compliance
      )
    )
  
  technical_cols <- intersect(
    c("sm_info_hworker", "sm_info_vaccinators", "sm_health_worker", "sm_vcm_unicef"),
    names(df)
  )
  
  technical_sm_source <- if (length(technical_cols) > 0) {
    safe_row_sum(df, technical_cols)
  } else {
    rep(0, nrow(df))
  }
  
  df %>%
    mutate(
      sm_intensity_group = case_when(
        sm_total_awareness_sources == 0 ~ "No awareness source",
        sm_total_awareness_sources == 1 ~ "One awareness source",
        sm_total_awareness_sources <= 3 ~ "2-3 awareness sources",
        sm_total_awareness_sources >= 4 ~ "4+ awareness sources",
        TRUE ~ "Unknown"
      ),
      sm_non_compliance_pressure = case_when(
        sm_total_awareness_sources == 0 & r_non_compliance > 0 ~ "Non-compliance with no awareness source",
        sm_total_awareness_sources > 0 & r_non_compliance > 0 ~ "Non-compliance despite awareness",
        sm_total_awareness_sources > 0 & r_non_compliance == 0 ~ "Awareness with no non-compliance",
        TRUE ~ "No SM / no non-compliance"
      ),
      sm_gap_flag = case_when(
        sm_total_awareness_sources == 0 ~ "SM gap detected",
        TRUE ~ "SM source recorded"
      ),
      sm_priority_flag = case_when(
        sm_total_awareness_sources == 0 & cv < 0.9 ~ "High priority SM gap",
        r_non_compliance > 0 & technical_sm_source == 0 ~ "Community resistance / weak technical source",
        sm_not_aware > 0 ~ "Not aware reported",
        TRUE ~ "No major SM alert"
      )
    )
}


# ============================================================
# NIGERIA IM SPECIAL PROCESSOR FOR FORM 7178
# Tailored logic integrated from nigeria_im_data_cleaning_and_aggregation.R
# ============================================================
normalize_nigeria_reason_text <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x[x %in% c("", "na", "nan", "null")] <- NA_character_
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT", sub = "")
  x <- gsub("[\r\n\t]+", " ", x)
  x <- gsub("[[:punct:]]+", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

detect_nigeria_main_reason <- function(x) {
  x0 <- normalize_nigeria_reason_text(x)
  dplyr::case_when(
    is.na(x0) | x0 == "" ~ NA_character_,
    str_detect(x0, "\\bnew born\\b|\\bnewborn\\b|\\bnew birth\\b|\\bnewly born\\b|\\ba day child\\b|\\ba day old\\b|\\bthree days old\\b|\\bjust gave birth\\b|\\bgiven birth\\b|\\bwas born yesterday\\b|\\bchild was born yesterday\\b|\\bdelivered on\\b|\\bbaby has four days\\b|\\bbaby was just born\\b|\\bzero dose\\b|\\bnew born baby\\b|\\bnew born babies\\b|\\bnew born child\\b|\\bnew born bby\\b") ~ "r_non_FM_childnotborn",
    str_detect(x0, "\\bsecurity\\b|security related issues") ~ "r_non_FM_security",
    str_detect(x0, "finger mark|finger marked|finger marking|not finger marked|no mark on left finger|fingers not mark|mark was seen|mark was not seen|cleaned off|wrongly finger marked|vaccinated but was not marked|immunized but no mark|vaccinated but no mark|finger marking erased|finger marking has cleaned off|child was immunized|the child was immunized|immunized at different occasions|passed the immunization|received routine opv|received vaccine last month") ~ "r_non_FM_vaccinated_but_not_FM",
    str_detect(x0, "team not visited|team not visit|team did not visit|team didn t visit|household not visited|household not visit|house was not visit|house not visited|not revisited|never revisited|no revisit|revisit household|team omitted|did not make effort|didn t make effort|team failed to check|questions were not asked|didn t ask|did not ask|team didn t see the children|team didn t immunise|team didn t immunize|team visited but.*not.*effort|team got to the house but.*not.*effort|missed by the team|team do not ask five key question|teams unable to ask questions|team wrote revisit but never revisited|team wrote revisited but never revisited|team didn t reached out|team failed to check for children|house was not visit by the team") ~ "r_non_FM_hh_notvisited",
    str_detect(x0, "\\basleep\\b|\\bsleeping\\b|\\bwas sleeping\\b|\\bchild sleeping\\b|\\bchild was sleep\\b|\\bchild was asleep\\b|\\bwas slept\\b|\\bat sleep\\b|\\bchild was sleeping\\b|\\bchild is sleeping\\b|\\bshe was sleeping\\b|\\bmother was sleeping\\b") ~ "r_non_FM_sleep",
    str_detect(x0, "\\bvisitor\\b|\\bvisitors\\b|came for visiting|came for a visit|came visiting|came on visit|visiting child|visiting parent|just arrived|just came|just came back|moved in|from outside the settlement|from another state|from other state|not from the settlement|came for holiday|just came for holiday|holiday|sallah festival|omugwo|from village|from ibadan|from kano|from lagos|visit child from other lga|newly located|packed in|visitor from village|came from ibadan|came from kano|came from lagos|from nassarawa state|child just came visiting|child was visiting from another state|he is a visitor|the child is a visitor|he s on a visit to the house") ~ "r_non_FM_child_is_a_visitor",
    str_detect(x0, "non compliance|noncompliance|refusal|refused|rejection|does not want|do not allow|did not allow|father refused|father did not allow|father do not allow|mother requested not to give|not intrested|not interested|religious|traditional|cultural|no felt need|polio can be cured|polio has been eradicated|too many rounds|too many round|too many rnd|no caregiver consent|no care giver consent|no parental consent|caregiver refusal|scared|afraid|vaccine.*safe|vaccines.*safe|negative way|not been educated|ignorance|the say no|religious beliefs|announcement from mosque") ~ "r_non_FM_NC",
    str_detect(x0, "absent|abcent|absant|absend|abcend|abset|absence|absences|not around|not arround|not arrnd|not a round|not arond|not sround|not araun|not home|not at home|not as home|note at home|no at home|not present|not found at home|not in the house|not in house|not in area|not available|not seen|not met|wasn t present|wasnt present|wasn t around|wasnt around|wasn t home|wasnt home|away during|away with|went out|out of house|market|farm|school|shool|sch|islamiya|modiraza|qur an school|play ground|playground|playing ground|play graunt|play grouwn|play groud|play grand|social event|social events|socialevert|socialevent|social evert|social getthering|event center|church|travel|travelled|travelling|traveling|journey|transit|errand|river|work|office|wedding|ceremony|burial|meeting") ~ "r_non_FM_Absent",
    TRUE ~ "r_non_FM_other"
  )
}

detect_nigeria_abs_reason <- function(x) {
  x0 <- normalize_nigeria_reason_text(x)
  dplyr::case_when(
    is.na(x0) | x0 == "" ~ NA_character_,
    str_detect(x0, "travel|travelled|travelling|traveling|journey|transit|out of town|other state|outside the lga|trip|travel back|returned from journey") ~ "abs_reason_travelled",
    str_detect(x0, "farm|farming|bush|firewood") ~ "abs_reason_farm",
    str_detect(x0, "market|shop") ~ "abs_reason_market",
    str_detect(x0, "school|schools|shool|sch|islamiya|modiraza|qur an school") ~ "abs_reason_school",
    str_detect(x0, "play ground|playground|playing ground|play graunt|play grouwn|play grand|play groud|went to play|he was playing|play away") ~ "abs_reason_in_playground",
    TRUE ~ "abs_reason_other"
  )
}

detect_nigeria_nc_reason <- function(x) {
  x0 <- normalize_nigeria_reason_text(x)
  dplyr::case_when(
    is.na(x0) | x0 == "" ~ NA_character_,
    str_detect(x0, "religious|cultural|traditional|announcement from mosque|religious beliefs") ~ "nc_reason_religious_cultural",
    str_detect(x0, "polio can be cured|polio free|polio has been eradicated|poliofree") ~ "nc_reason_poliofree",
    str_detect(x0, "vaccine.*safe|vaccines.*safe|afraid|scared|negative way|reacted on child|interaction|safety") ~ "nc_reason_vaccines_safety",
    str_detect(x0, "no felt need|no need|no perceived need") ~ "nc_reason_no_felt_need",
    str_detect(x0, "too many rounds|too many round|too many rnd") ~ "nc_reason_too_many_rnd",
    str_detect(x0, "father refused|father did not allow|father do not allow|does not want|do not allow|did not allow|no caregiver consent|no care giver consent|no parental consent|caregiver refusal|mother requested not to give|refusal|refused|rejection|the say no") ~ "nc_reason_no_care_giver_consent",
    str_detect(x0, "child is sick|child was sick|child sick|child seek|child was ill|not healthy|unwell|hospital|admitted|not well|no medicine|physically fit|seriously sick|child are sick") ~ "nc_reason_child_sick",
    str_detect(x0, "covid") ~ "nc_reason_covid_19",
    str_detect(x0, "nopv|n opv") ~ "nc_reason_nopvconcern",
    TRUE ~ "nc_reason_others"
  )
}


process_nigeria_im_file <- function(input_file, output_folder, qc_output_folder) {
  file_name <- tools::file_path_sans_ext(basename(input_file))
  output_file <- file.path(output_folder, paste0(file_name, ".csv"))
  qc_output_file <- file.path(qc_output_folder, paste0(file_name, "_QC.csv"))
  
  message("\n============================================================")
  message("Processing Nigeria special IM form 7178 using inline tailored sanitized processor (any supported extension)")
  message("============================================================")
  
  if (!exists("NIGERIA_IM_SCRIPT_INLINE") || length(NIGERIA_IM_SCRIPT_INLINE) == 0) {
    stop("NIGERIA_IM_SCRIPT_INLINE is missing or empty.")
  }
  
  # Run the finalized Nigeria cleaning logic in an isolated environment.
  # The code is embedded in this same script, so no external source() is required.
  nigeria_env <- new.env(parent = globalenv())
  nigeria_env$rds_file <- input_file
  nigeria_env$out_file <- output_file
  
  eval(parse(text = NIGERIA_IM_SCRIPT_INLINE), envir = nigeria_env)
  
  if (!file.exists(output_file)) {
    stop("Nigeria special processor did not create expected output: ", output_file)
  }
  
  ng <- readr::read_csv(output_file, show_col_types = FALSE) %>% as_tibble()
  
  # Harmonize the sanitized Nigeria output to the regional repository schema.
  FE <- ng %>%
    transmute(
      country = dplyr::coalesce(as.character(.data$Country), "NIE"),
      province = as.character(.data$Region),
      district = as.character(.data$District),
      response = as.character(.data$Response),
      vaccine.type = as.character(.data$`Vaccine.type`),
      roundNumber = as.character(.data$roundNumber),
      round_start_date = lubridate::as_date(.data$round_start_date),
      start_date_IM_end = lubridate::as_date(.data$start_date),
      end_date_IM_end = lubridate::as_date(.data$end_date),
      year = safe_numeric_zero(.data$year),
      Number_of_HH_visited = NA_real_,
      
      u5_present = safe_numeric_zero(.data$u5_present),
      u5_FM = safe_numeric_zero(.data$u5_FM),
      missed_child = safe_numeric_zero(.data$missed_child),
      cv = suppressWarnings(as.numeric(.data$cv)),
      
      r_non_FM_Absent = safe_numeric_zero(.data$r_non_FM_Absent),
      r_non_FM_NC = safe_numeric_zero(.data$r_non_FM_NC),
      r_non_FM_hh_notvisited = safe_numeric_zero(.data$r_non_FM_hh_notvisited),
      r_non_FM_hh_notrevisited = if ("r_non_FM_hh_notrevisited" %in% names(ng)) safe_numeric_zero(.data$r_non_FM_hh_notrevisited) else 0,
      r_non_FM_sleep = safe_numeric_zero(.data$r_non_FM_sleep),
      r_non_FM_vaccinatedRoutine = if ("r_non_FM_vaccinatedRoutine" %in% names(ng)) safe_numeric_zero(.data$r_non_FM_vaccinatedRoutine) else 0,
      r_non_FM_other = safe_numeric_zero(.data$r_non_FM_other),
      r_non_FM_vaccinated_but_not_FM = safe_numeric_zero(.data$r_non_FM_vaccinated_but_not_FM),
      r_non_FM_child_is_a_visitor = safe_numeric_zero(.data$r_non_FM_child_is_a_visitor),
      r_non_FM_childnotborn = safe_numeric_zero(.data$r_non_FM_childnotborn),
      r_non_FM_security = safe_numeric_zero(.data$r_non_FM_security),
      
      r_abs_sick = 0,
      r_abs_play_areas = safe_numeric_zero(.data$abs_reason_in_playground),
      r_abs_market = safe_numeric_zero(.data$abs_reason_market),
      r_abs_school = safe_numeric_zero(.data$abs_reason_school),
      r_abs_farm = safe_numeric_zero(.data$abs_reason_farm),
      r_abs_social_event = 0,
      r_abs_travelling = safe_numeric_zero(.data$abs_reason_travelled),
      r_abs_parent_absent = 0,
      r_abs_other_detail = safe_numeric_zero(.data$abs_reason_other),
      
      r_nc_religious_beliefs = safe_numeric_zero(.data$nc_reason_religious_cultural),
      r_nc_side_effects = safe_numeric_zero(.data$nc_reason_vaccines_safety),
      r_nc_too_many_doses = safe_numeric_zero(.data$nc_reason_too_many_rnd),
      r_nc_child_sick = safe_numeric_zero(.data$nc_reason_child_sick),
      r_nc_covid = safe_numeric_zero(.data$nc_reason_covid_19),
      r_nc_other_detail = safe_numeric_zero(.data$nc_reason_others) +
        safe_numeric_zero(.data$nc_reason_no_felt_need) +
        safe_numeric_zero(.data$nc_reason_no_care_giver_consent),
      r_nc_not_decided = 0,
      r_nc_polio_free = safe_numeric_zero(.data$nc_reason_poliofree),
      r_nc_nopv = safe_numeric_zero(.data$nc_reason_nopvconcern),
      
      care_Giver_Informed_SIA = safe_numeric_zero(.data$sm_total_awareness_sources),
      percent_care_Giver_Informed_SIA = NA_real_,
      sm_info_tv = 0,
      sm_info_radio = safe_numeric_zero(.data$sm_radio),
      sm_info_others = safe_numeric_zero(.data$sm_other),
      sm_info_hworker = safe_numeric_zero(.data$sm_health_worker),
      sm_info_mob_vanpa = 0,
      sm_info_town_crier = safe_numeric_zero(.data$sm_town_announcer),
      sm_info_volunteers = safe_numeric_zero(.data$sm_vcm_unicef),
      sm_info_com_infocentre = 0,
      sm_info_community_leader = safe_numeric_zero(.data$sm_traditional_leader),
      sm_info_religious_leader = safe_numeric_zero(.data$sm_mosque_announcement),
      sm_info_mobile_social_media = 0,
      sm_info_h2h_mobilizer = safe_numeric_zero(.data$sm_relative_neighbour_friend),
      sm_info_mourchidate = 0,
      sm_info_mosque = safe_numeric_zero(.data$sm_mosque_announcement),
      sm_info_vaccinators = 0,
      sm_info_sticker = safe_numeric_zero(.data$sm_poster_leaflets) + safe_numeric_zero(.data$sm_banner_hoarding),
      sm_info_newspaper_text = safe_numeric_zero(.data$sm_newspaper),
      sm_info_teachers_student_text = safe_numeric_zero(.data$sm_school_children_rally_visit),
      sm_info_iec_materials_text = 0,
      sm_total_sources = safe_numeric_zero(.data$sm_total_sources),
      sm_total_awareness_sources = safe_numeric_zero(.data$sm_total_awareness_sources),
      
      denominator_qc_flag = if ("denominator_qc_flag" %in% names(ng)) as.character(.data$denominator_qc_flag) else "Denominator OK",
      numerator_reconstructed = if ("numerator_reconstructed" %in% names(ng)) safe_numeric_zero(.data$numerator_reconstructed) else 0,
      nigeria_qc_flag = if ("qc_flag" %in% names(ng)) as.character(.data$qc_flag) else NA_character_,
      source_file = basename(input_file)
    )
  
  # ------------------------------------------------------------
  # IMPORTANT:
  # Nigeria output is already cleaned and aggregated by the
  # tailored 7178 processor. At this point FE is already in the
  # regional lowercase schema (country/province/district/...).
  # Do NOT send it to process_final_data(), because that function
  # expects raw uppercase columns such as Country/Region/District
  # and will fail with: Country = case_when(...).
  # ------------------------------------------------------------
  FE <- FE %>%
    mutate(
      reasons_total =
        r_non_FM_Absent +
        r_non_FM_NC +
        r_non_FM_hh_notvisited +
        r_non_FM_hh_notrevisited +
        r_non_FM_sleep +
        r_non_FM_vaccinatedRoutine +
        r_non_FM_other,
      
      abs_detail_total =
        r_abs_sick + r_abs_play_areas + r_abs_market + r_abs_school +
        r_abs_farm + r_abs_social_event + r_abs_travelling +
        r_abs_parent_absent + r_abs_other_detail,
      
      nc_detail_total =
        r_nc_religious_beliefs + r_nc_side_effects + r_nc_too_many_doses +
        r_nc_child_sick + r_nc_covid + r_nc_other_detail +
        r_nc_not_decided + r_nc_polio_free + r_nc_nopv,
      
      # Coverage is already cleaned by Nigeria processor; keep final safety.
      u5_FM = ifelse(u5_FM > u5_present & u5_present > 0, u5_present, u5_FM),
      missed_child = pmax(0, u5_present - u5_FM),
      cv = ifelse(u5_present > 0, round(u5_FM / u5_present, 4), NA_real_),
      cv = case_when(
        is.infinite(cv) ~ NA_real_,
        cv < 0 ~ NA_real_,
        cv > 1 ~ 1,
        TRUE ~ cv
      ),
      
      check_missed = missed_child - reasons_total,
      unexplained_missed = pmax(check_missed, 0),
      overreported_reasons = pmax(-check_missed, 0),
      explained_ratio = ifelse(missed_child > 0, round(reasons_total / missed_child, 3), NA_real_),
      unexplained_ratio = ifelse(missed_child > 0, round(unexplained_missed / missed_child, 3), NA_real_),
      
      check_abs_detail = r_non_FM_Absent - abs_detail_total,
      check_nc_detail = r_non_FM_NC - nc_detail_total,
      check_sm_info = care_Giver_Informed_SIA - sm_total_sources,
      sm_info_gap = pmax(check_sm_info, 0),
      sm_info_overlap = pmax(-check_sm_info, 0),
      
      reconciliation_flag = case_when(
        check_missed == 0 ~ "Consistent",
        check_missed > 0 & reasons_total == 0 ~ "No reasons recorded",
        check_missed > 0 ~ "Partial reasons recorded",
        check_missed < 0 ~ "Overlapping reasons",
        TRUE ~ "Unknown"
      ),
      abs_detail_flag = case_when(
        check_abs_detail == 0 ~ "Abs detail consistent",
        check_abs_detail > 0 ~ "Abs detail incomplete",
        check_abs_detail < 0 ~ "Abs detail overlapping",
        TRUE ~ "Unknown"
      ),
      nc_detail_flag = case_when(
        check_nc_detail == 0 ~ "NC detail consistent",
        check_nc_detail > 0 ~ "NC detail incomplete",
        check_nc_detail < 0 ~ "NC detail overlapping",
        TRUE ~ "Unknown"
      ),
      sm_reconciliation_flag = case_when(
        sm_total_awareness_sources == 0 & sm_total_sources > 0 ~ "Not aware reported",
        sm_total_sources == 0 ~ "No source recorded",
        TRUE ~ "SM source recorded"
      ),
      qc_flag = case_when(
        denominator_qc_flag %in% c("Denominator inconsistency", "Missing denominator unresolved") ~ "Needs review",
        check_missed == 0 & check_abs_detail == 0 & check_nc_detail == 0 ~ "OK",
        TRUE ~ "Needs review"
      )
    )
  
  FE <- add_sm_intelligence_indicators(FE)
  FE <- sanitize_regional_im_output(FE)
  
  QC <- FE %>%
    filter(
      qc_flag == "Needs review" |
        denominator_qc_flag %in% c(
          "Denominator inconsistency",
          "Missing denominator unresolved",
          "Numerator exceeds denominator",
          "FM capped to denominator"
        ) |
        reconciliation_flag != "Consistent"
    )
  
  readr::write_csv(FE, output_file)
  readr::write_csv(QC, qc_output_file)
  
  message("Done: Nigeria special form 7178")
  message("  Output: ", output_file)
  message("  QC: ", qc_output_file)
  
  list(
    file = basename(input_file),
    status = "success",
    data = FE,
    qc = QC,
    output_file = output_file,
    qc_output_file = qc_output_file,
    rows = nrow(FE),
    qc_rows = nrow(QC),
    error = NA_character_,
    summary = tibble(
      file = basename(input_file),
      rows_output = nrow(FE),
      rows_qc = nrow(QC),
      countries = paste(unique(FE$country), collapse = ", "),
      min_date = suppressWarnings(if (nrow(FE) > 0) min(FE$start_date_IM_end, na.rm = TRUE) else as.Date(NA)),
      max_date = suppressWarnings(if (nrow(FE) > 0) max(FE$start_date_IM_end, na.rm = TRUE) else as.Date(NA))
    )
  )
}


process_im_file <- function(input_file, output_folder, qc_output_folder, lookup_table) {
  file_name <- tools::file_path_sans_ext(basename(input_file))
  output_file <- file.path(output_folder, paste0(file_name, ".csv"))
  qc_output_file <- file.path(qc_output_folder, paste0(file_name, "_QC.csv"))
  
  message("\n============================================================")
  message("Processing file: ", basename(input_file))
  message("============================================================")
  
  if (identical(file_name, NIGERIA_IM_FORM_ID)) {
    return(process_nigeria_im_file(input_file, output_folder, qc_output_folder))
  }
  
  data <- read_input_data(input_file)
  
  minimum_im_markers <- c("Response", "roundNumber", "Type_Monitoring")
  if (!any(minimum_im_markers %in% names(data))) {
    stop("File does not look like an IM dataset.")
  }
  
  if (!"Country" %in% names(data)) {
    data$Country <- NA_character_
  }

  # Some country templates (e.g. form 8832 / Botswana) go straight from
  # Country to District with no Region level at all. Region is referenced
  # unconditionally further downstream (assign_vaccine_types()'s DRC-only
  # override, and process_final_data()'s final select(province = Region)),
  # so default it here the same way Country is defaulted above -- otherwise
  # those references fail with "object/column 'Region' not found" for any
  # form whose template omits it.
  if (!"Region" %in% names(data)) {
    data$Region <- NA_character_
  }

  data <- apply_country_specific_transformations(data, file_name)
  data <- rename_repetitive_columns(data)
  
  active_hh_patterns <- if (identical(file_name, ALGERIA_IM_FORM_ID)) {
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
  
  hh_cols <- names(GF)[str_detect(names(GF), "^HH\\[")]
  
  sm_text_keep_cols <- hh_cols[str_detect(
    hh_cols,
    regex("Source_Info_SIA_HH$|Other_Source_Info$", ignore_case = TRUE)
  )]
  
  hh_numeric_cols <- setdiff(hh_cols, sm_text_keep_cols)
  
  for (col in hh_numeric_cols) {
    GF[[col]] <- clean_yes_no_numeric(GF[[col]])
  }
  
  for (col in sm_text_keep_cols) {
    GF[[col]] <- as.character(GF[[col]])
  }
  
  numeric_cols <- intersect(
    c(
      "HH_count", "Total_U5_Present", "TotalFM", "sum_missed_children",
      "Total_Absent", "Total_refusal",
      unlist(absence_total_candidates),
      unlist(nc_total_candidates),
      unlist(sm_count_candidates),
      "Tot_child_NC_NotDecide_T", "Tot_child_NC_PolioFREE_T",
      "Tot_child_NC_nOPV_T", "Tot_child_NC_ChildSick_T",
      "Tot_child_NC_Others_T", "Tot_child_Abs_Sick_T"
    ),
    names(GF)
  )
  
  if (length(numeric_cols) > 0) {
    GF[numeric_cols] <- lapply(GF[numeric_cols], clean_numeric)
  }
  
  if ("date_monitored" %in% names(GF)) {
    GF <- GF %>% mutate(date_monitored = parse_mixed_dates(date_monitored))
  }
  
  GH <- create_summary_columns(GF, file_name = file_name)
  
  if ("HH_count" %in% names(GH)) {
    GH <- GH %>%
      mutate(Number_of_HH_visited = suppressWarnings(as.numeric(HH_count)))
  } else if ("Number_of_HH_visited" %in% names(GH)) {
    GH <- GH %>%
      mutate(Number_of_HH_visited = suppressWarnings(as.numeric(Number_of_HH_visited)))
  } else {
    GH$Number_of_HH_visited <- NA_real_
  }
  
  if (!"Total_U5_Present" %in% names(GH)) GH$Total_U5_Present <- NA_real_
  if (!"TotalFM" %in% names(GH)) GH$TotalFM <- NA_real_
  
  GJ <- GH %>%
    mutate(
      Total_U5_Present = suppressWarnings(as.numeric(Total_U5_Present)),
      TotalFM = suppressWarnings(as.numeric(TotalFM))
    ) %>%
    standardize_districts()
  
  GO <- GJ %>% standardize_responses()
  GK <- GO %>% assign_vaccine_types()
  GL <- GK %>% process_final_data()
  
  required_final_columns <- c(
    "Country", "Region", "District", "Response", "Vaccine.type", "roundNumber",
    "date_monitored", "Number_of_HH_visited", "u5_present", "u5_FM", "missed_child",
    "denominator_reconstructed", "denominator_qc_flag",
    "r_non_FM_Absent", "r_non_FM_NC", "r_non_FM_hh_notvisited", "r_non_FM_hh_notrevisited",
    "r_non_FM_sleep", "r_non_FM_vaccinatedRoutine", "r_non_FM_other",
    "care_Giver_Informed_SIA",
    "sm_info_tv", "sm_info_radio", "sm_info_others", "sm_info_hworker",
    "sm_info_mob_vanpa", "sm_info_town_crier", "sm_info_volunteers",
    "sm_info_com_infocentre", "sm_info_community_leader",
    "sm_info_religious_leader", "sm_info_mobile_social_media",
    "sm_info_mourchidate", "sm_info_mosque", "sm_info_vaccinators",
    "sm_info_h2h_mobilizer", "sm_info_sticker",
    "sm_info_newspaper_text", "sm_info_teachers_student_text", "sm_info_iec_materials_text",
    "sm_total_sources",
    "check_sm_info", "sm_info_gap", "sm_info_overlap", "sm_reconciliation_flag",
    "r_abs_sick", "r_abs_play_areas", "r_abs_market", "r_abs_school",
    "r_abs_farm", "r_abs_social_event", "r_abs_travelling", "r_abs_parent_absent", "r_abs_other_detail",
    "r_nc_religious_beliefs", "r_nc_side_effects", "r_nc_too_many_doses",
    "r_nc_child_sick", "r_nc_covid", "r_nc_other_detail", "r_nc_not_decided",
    "r_nc_polio_free", "r_nc_nopv",
    "abs_detail_total", "nc_detail_total", "reasons_total",
    "check_missed", "check_abs_detail", "check_nc_detail",
    "unexplained_missed", "overreported_reasons",
    "explained_ratio", "unexplained_ratio",
    "reconciliation_flag", "abs_detail_flag", "nc_detail_flag", "qc_flag"
  )
  
  for (col in required_final_columns) {
    if (!col %in% names(GL)) {
      GL[[col]] <- NA
    }
  }
  
  F5 <- GL %>%
    mutate(
      start_date = as_date(date_monitored),
      end_date = as_date(date_monitored),
      year = year(start_date),
      cv = ifelse(u5_present > 0, round(u5_FM / u5_present, 2), NA_real_),
      percent_care_Giver_Informed_SIA = ifelse(
        Number_of_HH_visited > 0,
        round((care_Giver_Informed_SIA / Number_of_HH_visited) * 100, 2),
        NA_real_
      )
    ) %>%
    group_by(Country, Region, District, Response, Vaccine.type, roundNumber) %>%
    summarise(
      start_date = min(start_date, na.rm = TRUE),
      end_date = max(end_date, na.rm = TRUE),
      Number_of_HH_visited = sum(Number_of_HH_visited, na.rm = TRUE),
      u5_present = sum(u5_present, na.rm = TRUE),
      u5_FM = sum(u5_FM, na.rm = TRUE),
      missed_child = sum(missed_child, na.rm = TRUE),
      denominator_reconstructed = sum(denominator_reconstructed, na.rm = TRUE),
      
      r_non_FM_Absent = sum(r_non_FM_Absent, na.rm = TRUE),
      r_non_FM_NC = sum(r_non_FM_NC, na.rm = TRUE),
      r_non_FM_hh_notvisited = sum(r_non_FM_hh_notvisited, na.rm = TRUE),
      r_non_FM_hh_notrevisited = sum(r_non_FM_hh_notrevisited, na.rm = TRUE),
      r_non_FM_sleep = sum(r_non_FM_sleep, na.rm = TRUE),
      r_non_FM_vaccinatedRoutine = sum(r_non_FM_vaccinatedRoutine, na.rm = TRUE),
      r_non_FM_other = sum(r_non_FM_other, na.rm = TRUE),
      
      care_Giver_Informed_SIA = sum(care_Giver_Informed_SIA, na.rm = TRUE),
      
      sm_info_tv = sum(sm_info_tv, na.rm = TRUE),
      sm_info_radio = sum(sm_info_radio, na.rm = TRUE),
      sm_info_others = sum(sm_info_others, na.rm = TRUE),
      sm_info_hworker = sum(sm_info_hworker, na.rm = TRUE),
      sm_info_mob_vanpa = sum(sm_info_mob_vanpa, na.rm = TRUE),
      sm_info_town_crier = sum(sm_info_town_crier, na.rm = TRUE),
      sm_info_volunteers = sum(sm_info_volunteers, na.rm = TRUE),
      sm_info_com_infocentre = sum(sm_info_com_infocentre, na.rm = TRUE),
      sm_info_community_leader = sum(sm_info_community_leader, na.rm = TRUE),
      sm_info_religious_leader = sum(sm_info_religious_leader, na.rm = TRUE),
      sm_info_mobile_social_media = sum(sm_info_mobile_social_media, na.rm = TRUE),
      sm_info_mourchidate = sum(sm_info_mourchidate, na.rm = TRUE),
      sm_info_mosque = sum(sm_info_mosque, na.rm = TRUE),
      sm_info_vaccinators = sum(sm_info_vaccinators, na.rm = TRUE),
      sm_info_h2h_mobilizer = sum(sm_info_h2h_mobilizer, na.rm = TRUE),
      sm_info_sticker = sum(sm_info_sticker, na.rm = TRUE),
      sm_info_newspaper_text = sum(sm_info_newspaper_text, na.rm = TRUE),
      sm_info_teachers_student_text = sum(sm_info_teachers_student_text, na.rm = TRUE),
      sm_info_iec_materials_text = sum(sm_info_iec_materials_text, na.rm = TRUE),
      sm_total_sources = sum(sm_total_sources, na.rm = TRUE),
      
      r_abs_sick = sum(r_abs_sick, na.rm = TRUE),
      r_abs_play_areas = sum(r_abs_play_areas, na.rm = TRUE),
      r_abs_market = sum(r_abs_market, na.rm = TRUE),
      r_abs_school = sum(r_abs_school, na.rm = TRUE),
      r_abs_farm = sum(r_abs_farm, na.rm = TRUE),
      r_abs_social_event = sum(r_abs_social_event, na.rm = TRUE),
      r_abs_travelling = sum(r_abs_travelling, na.rm = TRUE),
      r_abs_parent_absent = sum(r_abs_parent_absent, na.rm = TRUE),
      r_abs_other_detail = sum(r_abs_other_detail, na.rm = TRUE),
      
      r_nc_religious_beliefs = sum(r_nc_religious_beliefs, na.rm = TRUE),
      r_nc_side_effects = sum(r_nc_side_effects, na.rm = TRUE),
      r_nc_too_many_doses = sum(r_nc_too_many_doses, na.rm = TRUE),
      r_nc_child_sick = sum(r_nc_child_sick, na.rm = TRUE),
      r_nc_covid = sum(r_nc_covid, na.rm = TRUE),
      r_nc_other_detail = sum(r_nc_other_detail, na.rm = TRUE),
      r_nc_not_decided = sum(r_nc_not_decided, na.rm = TRUE),
      r_nc_polio_free = sum(r_nc_polio_free, na.rm = TRUE),
      r_nc_nopv = sum(r_nc_nopv, na.rm = TRUE),
      
      abs_detail_total = sum(abs_detail_total, na.rm = TRUE),
      nc_detail_total = sum(nc_detail_total, na.rm = TRUE),
      reasons_total = sum(reasons_total, na.rm = TRUE),
      unexplained_missed = sum(unexplained_missed, na.rm = TRUE),
      overreported_reasons = sum(overreported_reasons, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(
      # Reconstruct denominator at aggregated district-round level if needed.
      u5_present = case_when(
        u5_present <= 0 & u5_FM > 0 & missed_child > 0 ~ u5_FM + missed_child,
        TRUE ~ u5_present
      ),
      u5_FM = ifelse(u5_FM > u5_present & u5_present > 0, u5_present, u5_FM),
      missed_child = pmax(0, u5_present - u5_FM),
      cv = ifelse(u5_present > 0, round(u5_FM / u5_present, 2), NA_real_),
      cv = case_when(
        is.infinite(cv) ~ NA_real_,
        cv < 0 ~ NA_real_,
        cv > 1 ~ 1,
        TRUE ~ cv
      ),
      denominator_qc_flag = case_when(
        denominator_reconstructed > 0 ~ "Missing denominator reconstructed",
        u5_present <= 0 & u5_FM > 0 ~ "Missing denominator unresolved",
        TRUE ~ "Denominator OK"
      ),
      year = year(start_date),
      percent_care_Giver_Informed_SIA = ifelse(
        Number_of_HH_visited > 0,
        round((care_Giver_Informed_SIA / Number_of_HH_visited) * 100, 2),
        NA_real_
      ),
      
      check_missed = missed_child - reasons_total,
      check_abs_detail = r_non_FM_Absent - abs_detail_total,
      check_nc_detail = r_non_FM_NC - nc_detail_total,
      check_sm_info = care_Giver_Informed_SIA - sm_total_sources,
      sm_info_gap = pmax(check_sm_info, 0),
      sm_info_overlap = pmax(-check_sm_info, 0),
      
      explained_ratio = ifelse(missed_child > 0, round(reasons_total / missed_child, 3), NA_real_),
      unexplained_ratio = ifelse(missed_child > 0, round(unexplained_missed / missed_child, 3), NA_real_),
      
      reconciliation_flag = case_when(
        denominator_qc_flag == "Missing denominator reconstructed" ~ "Missing denominator reconstructed",
        check_missed == 0 ~ "Consistent",
        check_missed > 0 & reasons_total == 0 ~ "No reasons recorded",
        check_missed > 0 ~ "Partial reasons recorded",
        check_missed < 0 ~ "Overlapping reasons",
        TRUE ~ "Unknown"
      ),
      
      abs_detail_flag = case_when(
        check_abs_detail == 0 ~ "Abs detail consistent",
        check_abs_detail > 0 ~ "Abs detail incomplete",
        check_abs_detail < 0 ~ "Abs detail overlapping",
        TRUE ~ "Unknown"
      ),
      
      nc_detail_flag = case_when(
        check_nc_detail == 0 ~ "NC detail consistent",
        check_nc_detail > 0 ~ "NC detail incomplete",
        check_nc_detail < 0 ~ "NC detail overlapping",
        TRUE ~ "Unknown"
      ),
      
      sm_reconciliation_flag = case_when(
        care_Giver_Informed_SIA > 0 & sm_total_sources == 0 ~ "No source recorded",
        check_sm_info == 0 ~ "SM consistent",
        check_sm_info < 0 ~ "Multiple sources per informed HH",
        check_sm_info > 0 ~ "Some informed HH missing source",
        TRUE ~ "Unknown"
      ),
      
      qc_flag = case_when(
        check_missed == 0 &
          check_abs_detail == 0 &
          check_nc_detail == 0 &
          check_sm_info <= 0 ~ "OK",
        TRUE ~ "Needs review"
      )
    ) %>%
    add_sm_intelligence_indicators() %>%
    filter(start_date > as_date("2019-10-01"))
  
  FI <- F5 %>%
    left_join(
      lookup_table,
      by = c("Response", "Vaccine.type", "roundNumber"),
      suffix = c("", "_lookup")
    ) %>%
    mutate(
      start_date = coalesce(start_date_lookup, start_date),
      end_date = coalesce(end_date_lookup, end_date),
      round_start_date = coalesce(round_start_date, start_date - days(4))
    ) %>%
    select(-ends_with("_lookup")) %>%
    filter(District != "NA")
  
  FE <- FI %>%
    select(
      country = Country,
      province = Region,
      district = District,
      response = Response,
      vaccine.type = Vaccine.type,
      roundNumber,
      round_start_date,
      start_date_IM_end = start_date,
      end_date_IM_end = end_date,
      year,
      Number_of_HH_visited,
      u5_present,
      u5_FM,
      missed_child,
      denominator_reconstructed,
      denominator_qc_flag,
      cv,
      
      r_non_FM_Absent,
      r_non_FM_NC,
      r_non_FM_hh_notvisited,
      r_non_FM_hh_notrevisited,
      r_non_FM_sleep,
      r_non_FM_vaccinatedRoutine,
      r_non_FM_other,
      
      care_Giver_Informed_SIA,
      percent_care_Giver_Informed_SIA,
      
      sm_info_tv,
      sm_info_radio,
      sm_info_others,
      sm_info_hworker,
      sm_info_mob_vanpa,
      sm_info_town_crier,
      sm_info_volunteers,
      sm_info_com_infocentre,
      sm_info_community_leader,
      sm_info_religious_leader,
      sm_info_mobile_social_media,
      sm_info_mourchidate,
      sm_info_mosque,
      sm_info_vaccinators,
      sm_info_h2h_mobilizer,
      sm_info_sticker,
      sm_info_newspaper_text,
      sm_info_teachers_student_text,
      sm_info_iec_materials_text,
      sm_total_sources,
      check_sm_info,
      sm_info_gap,
      sm_info_overlap,
      sm_reconciliation_flag,
      sm_total_awareness_sources,
      sm_intensity_group,
      sm_non_compliance_pressure,
      sm_gap_flag,
      sm_priority_flag,
      
      r_abs_sick,
      r_abs_play_areas,
      r_abs_market,
      r_abs_school,
      r_abs_farm,
      r_abs_social_event,
      r_abs_travelling,
      r_abs_parent_absent,
      r_abs_other_detail,
      
      r_nc_religious_beliefs,
      r_nc_side_effects,
      r_nc_too_many_doses,
      r_nc_child_sick,
      r_nc_covid,
      r_nc_other_detail,
      r_nc_not_decided,
      r_nc_polio_free,
      r_nc_nopv,
      
      reasons_total,
      abs_detail_total,
      nc_detail_total,
      check_missed,
      check_abs_detail,
      check_nc_detail,
      unexplained_missed,
      overreported_reasons,
      explained_ratio,
      unexplained_ratio,
      reconciliation_flag,
      abs_detail_flag,
      nc_detail_flag,
      qc_flag
    ) %>%
    arrange(start_date_IM_end)
  
  FE_QC <- FE %>%
    filter(
      qc_flag == "Needs review" |
        denominator_qc_flag == "Missing denominator unresolved" |
        abs(check_missed) >= 5 |
        abs(check_abs_detail) >= 3 |
        abs(check_nc_detail) >= 3 |
        check_sm_info > 0
    ) %>%
    arrange(desc(abs(check_missed)), desc(abs(check_abs_detail)), desc(abs(check_nc_detail)), desc(check_sm_info))
  
  write_csv(FE, output_file)
  write_csv(FE_QC, qc_output_file)
  
  message("Done: ", basename(input_file))
  message("  Output: ", output_file)
  message("  QC: ", qc_output_file)
  
  list(
    data = FE,
    qc = FE_QC,
    summary = tibble(
      file = basename(input_file),
      rows_output = nrow(FE),
      rows_qc = nrow(FE_QC),
      countries = paste(unique(FE$country), collapse = ", "),
      min_date = suppressWarnings(if (nrow(FE) > 0) min(FE$start_date_IM_end, na.rm = TRUE) else as.Date(NA)),
      max_date = suppressWarnings(if (nrow(FE) > 0) max(FE$start_date_IM_end, na.rm = TRUE) else as.Date(NA))
    )
  )
}



# ============================================================
# FINAL DENOMINATOR / NUMERATOR CONSISTENCY ENGINE
# Applies after file-level processing and after regional binding
# ============================================================
enforce_denominator_consistency <- function(df) {
  
  if (is.null(df) || nrow(df) == 0) return(df)
  
  required_cols <- c("u5_present", "u5_FM", "missed_child")
  missing_cols <- setdiff(required_cols, names(df))
  
  if (length(missing_cols) > 0) {
    message("Skipping denominator consistency: missing columns: ", paste(missing_cols, collapse = ", "))
    return(df)
  }
  
  # Ensure required fields are numeric and free from special missing codes
  df$u5_present <- safe_numeric_zero(df$u5_present)
  df$u5_FM <- safe_numeric_zero(df$u5_FM)
  df$missed_child <- safe_numeric_zero(df$missed_child)
  
  # Keep trace of original values before repair
  original_u5_present <- df$u5_present
  original_u5_FM <- df$u5_FM
  original_missed_child <- df$missed_child
  
  # Extreme value protection. Very large values are not valid IM district totals
  # and are treated as unresolved denominator/numerator inconsistencies.
  extreme_limit <- 50000
  
  extreme_denominator <- !is.na(df$u5_present) & df$u5_present > extreme_limit
  extreme_numerator <- !is.na(df$u5_FM) & df$u5_FM > extreme_limit
  extreme_missed <- !is.na(df$missed_child) & df$missed_child > extreme_limit
  
  df$u5_present[extreme_denominator] <- NA_real_
  df$u5_FM[extreme_numerator] <- NA_real_
  df$missed_child[extreme_missed] <- NA_real_
  
  # Replace NA with zero only after flagging extreme values
  df$u5_present[is.na(df$u5_present)] <- 0
  df$u5_FM[is.na(df$u5_FM)] <- 0
  df$missed_child[is.na(df$missed_child)] <- 0
  
  # Reconstruct denominator when denominator is missing but numerator and missed are available
  reconstructed_denominator <- (
    df$u5_present <= 0 &
      df$u5_FM > 0 &
      df$missed_child > 0
  )
  
  df$u5_present <- ifelse(
    reconstructed_denominator,
    df$u5_FM + df$missed_child,
    df$u5_present
  )
  
  # Reconstruct numerator when numerator is missing but denominator and missed are available
  reconstructed_numerator <- (
    df$u5_FM <= 0 &
      df$u5_present > 0 &
      df$missed_child >= 0
  )
  
  df$u5_FM <- ifelse(
    reconstructed_numerator,
    pmax(0, df$u5_present - df$missed_child),
    df$u5_FM
  )
  
  # Final safety: numerator cannot exceed denominator
  numerator_capped <- df$u5_FM > df$u5_present & df$u5_present > 0
  df$u5_FM <- ifelse(numerator_capped, df$u5_present, df$u5_FM)
  
  # Recalculate missed children and coverage from corrected denominator/numerator
  df$missed_child <- pmax(0, df$u5_present - df$u5_FM)
  
  df$cv <- ifelse(
    df$u5_present > 0,
    round(df$u5_FM / df$u5_present, 4),
    NA_real_
  )
  
  df$cv <- case_when(
    is.infinite(df$cv) ~ NA_real_,
    df$cv < 0 ~ NA_real_,
    df$cv > 1 ~ 1,
    TRUE ~ df$cv
  )
  
  # Store explicit reconstruction flags
  df$denominator_reconstructed <- as.integer(reconstructed_denominator)
  df$numerator_reconstructed <- as.integer(reconstructed_numerator)
  df$numerator_capped <- as.integer(numerator_capped)
  df$extreme_value_flag <- as.integer(extreme_denominator | extreme_numerator | extreme_missed)
  
  # Final denominator QC flag
  df$denominator_qc_flag <- case_when(
    df$extreme_value_flag == 1L ~
      "Extreme denominator/numerator value removed",
    df$denominator_reconstructed == 1L ~
      "Denominator reconstructed",
    df$numerator_reconstructed == 1L ~
      "Numerator reconstructed",
    df$numerator_capped == 1L ~
      "Numerator capped to denominator",
    df$u5_present <= 0 & (df$u5_FM > 0 | df$missed_child > 0) ~
      "Denominator inconsistency",
    df$u5_FM > df$u5_present ~
      "Numerator exceeds denominator",
    TRUE ~
      "Denominator OK"
  )
  
  df
}


# ============================================================
# FINAL NEGATIVE VALUE AUDIT + REPAIR
# Keeps diagnostic fields such as check_missed/check_abs_detail/check_nc_detail
# allowed to be negative, but repairs count/indicator variables where negatives
# are never meaningful.
# ============================================================
repair_negative_values <- function(df, context = "regional_im") {
  
  if (is.null(df) || nrow(df) == 0) return(df)
  
  numeric_cols <- names(df)[sapply(df, is.numeric)]
  if (length(numeric_cols) == 0) return(df)
  
  negative_report <- df %>%
    summarise(across(
      all_of(numeric_cols),
      ~ sum(.x < 0, na.rm = TRUE)
    )) %>%
    pivot_longer(
      everything(),
      names_to = "variable",
      values_to = "negative_count"
    ) %>%
    filter(negative_count > 0)
  
  if (nrow(negative_report) > 0) {
    message("\nNEGATIVE VALUES DETECTED in ", context, ":")
    print(negative_report)
  }
  
  # Variables where negative values are never meaningful.
  # Do NOT include check_missed/check_abs_detail/check_nc_detail/check_sm_info,
  # because those are diagnostic balance variables and can legitimately be negative.
  non_negative_cols <- intersect(
    c(
      "u5_present", "u5_FM", "u5_FM1", "missed_child", "cv",
      "number_of_hh_visited", "HH_count",
      "care_Giver_Informed_SIA",
      "r_non_FM_Absent", "r_non_FM_NC",
      "r_non_FM_hh_notvisited", "r_non_FM_hh_notrevisited",
      "r_non_FM_sleep", "r_non_FM_vaccinatedRoutine",
      "r_non_FM_other", "r_non_FM_vaccinated_but_not_FM",
      "r_non_FM_child_is_a_visitor", "r_non_FM_childnotborn",
      "r_non_FM_security",
      "reasons_total", "total_main_reasons",
      "abs_detail_total", "nc_detail_total",
      "unexplained_missed", "overreported_reasons",
      "explained_ratio", "unexplained_ratio",
      "sm_total_sources", "sm_total_awareness_sources",
      "sm_info_gap", "sm_info_overlap",
      "denominator_reconstructed", "numerator_reconstructed",
      "numerator_capped", "extreme_value_flag"
    ),
    names(df)
  )
  
  # Include reason/detail/social-mobilisation count prefixes.
  non_negative_cols <- unique(c(
    non_negative_cols,
    grep("^r_abs|^r_nc|^abs_reason|^nc_reason|^sm_info_|^sm_traditional|^sm_town|^sm_mosque|^sm_radio|^sm_newspaper|^sm_poster|^sm_banner|^sm_relative|^sm_health|^sm_vcm|^sm_school|^sm_not_aware|^sm_other", names(df), value = TRUE)
  ))
  
  non_negative_cols <- intersect(non_negative_cols, numeric_cols)
  
  if (length(non_negative_cols) > 0) {
    df <- df %>%
      mutate(across(
        all_of(non_negative_cols),
        ~ ifelse(is.na(.x), .x, ifelse(.x < 0, 0, .x))
      ))
  }
  
  df
}

# ============================================================
# FINAL REGIONAL OUTPUT SANITIZER
# Applies a last defensive pass before final regional export
# ============================================================
sanitize_regional_im_output <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  
  numeric_cols <- names(df)[sapply(df, is.numeric)]
  if (length(numeric_cols) > 0) {
    df[numeric_cols] <- lapply(df[numeric_cols], safe_numeric_zero)
  }
  
  df <- enforce_denominator_consistency(df)
  
  # Recompute core QC values after any denominator/numerator reconstruction.
  if (all(c("missed_child", "r_non_FM_Absent", "r_non_FM_NC", "r_non_FM_hh_notvisited",
            "r_non_FM_hh_notrevisited", "r_non_FM_sleep", "r_non_FM_vaccinatedRoutine",
            "r_non_FM_other") %in% names(df))) {
    df <- df %>%
      mutate(
        reasons_total =
          r_non_FM_Absent + r_non_FM_NC + r_non_FM_hh_notvisited +
          r_non_FM_hh_notrevisited + r_non_FM_sleep +
          r_non_FM_vaccinatedRoutine + r_non_FM_other,
        check_missed = missed_child - reasons_total,
        unexplained_missed = pmax(check_missed, 0),
        overreported_reasons = pmax(-check_missed, 0),
        explained_ratio = ifelse(missed_child > 0, round(reasons_total / missed_child, 3), NA_real_),
        unexplained_ratio = ifelse(missed_child > 0, round(unexplained_missed / missed_child, 3), NA_real_),
        reconciliation_flag = case_when(
          denominator_reconstructed == 1L ~ "Missing denominator reconstructed",
          numerator_reconstructed == 1L ~ "Numerator reconstructed",
          check_missed == 0 ~ "Consistent",
          check_missed > 0 & reasons_total == 0 ~ "No reasons recorded",
          check_missed > 0 ~ "Partial reasons recorded",
          check_missed < 0 ~ "Overlapping reasons",
          TRUE ~ "Unknown"
        )
      )
  }
  
  if (all(c("r_non_FM_Absent", "abs_detail_total") %in% names(df))) {
    df <- df %>%
      mutate(
        check_abs_detail = r_non_FM_Absent - abs_detail_total,
        abs_detail_flag = case_when(
          check_abs_detail == 0 ~ "Abs detail consistent",
          check_abs_detail > 0 ~ "Abs detail incomplete",
          check_abs_detail < 0 ~ "Abs detail overlapping",
          TRUE ~ "Unknown"
        )
      )
  }
  
  if (all(c("r_non_FM_NC", "nc_detail_total") %in% names(df))) {
    df <- df %>%
      mutate(
        check_nc_detail = r_non_FM_NC - nc_detail_total,
        nc_detail_flag = case_when(
          check_nc_detail == 0 ~ "NC detail consistent",
          check_nc_detail > 0 ~ "NC detail incomplete",
          check_nc_detail < 0 ~ "NC detail overlapping",
          TRUE ~ "Unknown"
        )
      )
  }
  
  if (all(c("care_Giver_Informed_SIA", "sm_total_sources") %in% names(df))) {
    df <- df %>%
      mutate(
        check_sm_info = care_Giver_Informed_SIA - sm_total_sources,
        sm_info_gap = pmax(check_sm_info, 0),
        sm_info_overlap = pmax(-check_sm_info, 0),
        sm_reconciliation_flag = case_when(
          care_Giver_Informed_SIA > 0 & sm_total_sources == 0 ~ "No source recorded",
          check_sm_info == 0 ~ "SM consistent",
          check_sm_info < 0 ~ "Multiple sources per informed HH",
          check_sm_info > 0 ~ "Some informed HH missing source",
          TRUE ~ "Unknown"
        )
      )
  }
  
  if (all(c("check_missed", "check_abs_detail", "check_nc_detail", "check_sm_info") %in% names(df))) {
    df <- df %>%
      mutate(
        qc_flag = case_when(
          denominator_qc_flag %in% c("Denominator inconsistency", "Numerator exceeds denominator") ~ "Needs review",
          check_missed == 0 & check_abs_detail == 0 & check_nc_detail == 0 & check_sm_info <= 0 ~ "OK",
          TRUE ~ "Needs review"
        )
      )
  }
  
  # Final negative-value repair after denominator and QC recomputation.
  df <- repair_negative_values(df, context = "sanitize_regional_im_output")
  
  date_cols <- intersect(
    c("round_start_date", "start_date_IM_end", "end_date_IM_end"),
    names(df)
  )
  
  for (dc in date_cols) {
    df[[dc]] <- suppressWarnings(as.Date(df[[dc]]))
  }
  
  df
}


# ============================================================
# METADATA EXPORT FOR EXTERNAL USERS
# ============================================================

export_im_repository_metadata <- function(
    regional_im,
    metadata_file,
    regional_repository_file,
    regional_qc_repository_file
) {
  
  pacman::p_load(openxlsx, dplyr, tibble, stringr)
  
  metadata_overview <- tibble(
    item = c(
      "Repository name",
      "Repository purpose",
      "Unit of analysis",
      "Main file",
      "QC file",
      "Generated on",
      "Rows",
      "Columns",
      "District uniqueness rule",
      "Coverage definition",
      "Missed children definition",
      "Denominator repair rule",
      "Numerator repair rule",
      "Recommended analytics exclusion"
    ),
    description = c(
      "Regional Independent Monitoring Repository",
      "Cleaned and harmonized regional repository for Independent Monitoring campaign analysis.",
      "Country / Province / District / Response / Round / Vaccine type",
      regional_repository_file,
      regional_qc_repository_file,
      as.character(Sys.Date()),
      as.character(nrow(regional_im)),
      as.character(ncol(regional_im)),
      "country + province + district",
      "cv = u5_FM / u5_present",
      "missed_child = u5_present - u5_FM",
      "If u5_present is missing/zero but u5_FM and missed_child exist, denominator is reconstructed as u5_FM + missed_child.",
      "If u5_FM is missing/zero but u5_present and missed_child exist, numerator is reconstructed as u5_present - missed_child.",
      "Exclude denominator_qc_flag == 'Denominator inconsistency' from final analytics."
    )
  )
  
  variable_dictionary <- tibble(
    variable = names(regional_im),
    type = sapply(regional_im, function(x) paste(class(x), collapse = ", ")),
    missing_values = sapply(regional_im, function(x) sum(is.na(x))),
    example_value = sapply(regional_im, function(x) {
      val <- x[!is.na(x)][1]
      ifelse(length(val) == 0, NA_character_, as.character(val))
    })
  ) %>%
    mutate(
      description = case_when(
        variable == "country" ~ "Country code or standardized country name.",
        variable == "province" ~ "First administrative level / region / province.",
        variable == "district" ~ "District or health district.",
        variable == "response" ~ "Campaign response identifier.",
        variable == "roundNumber" ~ "Campaign round number.",
        variable == "vaccine_type" | variable == "Vaccine.type" ~ "Vaccine used during the campaign.",
        variable == "u5_present" ~ "Total eligible children present during independent monitoring.",
        variable == "u5_FM" ~ "Children with finger mark / vaccinated evidence.",
        variable == "missed_child" ~ "Children missed by campaign, calculated as u5_present - u5_FM.",
        variable == "cv" ~ "Independent monitoring coverage, calculated as u5_FM / u5_present.",
        variable == "reasons_total" ~ "Total reasons reported for missed children.",
        variable == "check_missed" ~ "Difference between missed_child and reasons_total.",
        variable == "unexplained_missed" ~ "Missed children without complete reason explanation.",
        variable == "overreported_reasons" ~ "Reasons reported above total missed children.",
        variable == "reconciliation_flag" ~ "QC flag comparing missed children and reported reasons.",
        variable == "qc_flag" ~ "Overall quality control flag.",
        variable == "denominator_reconstructed" ~ "1 if denominator was rebuilt from u5_FM + missed_child.",
        variable == "numerator_reconstructed" ~ "1 if numerator was rebuilt from u5_present - missed_child.",
        variable == "denominator_qc_flag" ~ "Denominator and numerator consistency status.",
        str_detect(variable, "^r_non_FM") ~ "Primary reason category for missed children.",
        str_detect(variable, "^r_abs") ~ "Detailed absence reason category.",
        str_detect(variable, "^r_nc") ~ "Detailed non-compliance reason category.",
        str_detect(variable, "^sm_info") ~ "Social mobilisation / information source variable.",
        variable == "sm_total_sources" ~ "Total recorded social mobilisation information sources.",
        variable == "care_Giver_Informed_SIA" ~ "Number of caregivers informed about the SIA.",
        variable == "sm_reconciliation_flag" ~ "QC flag comparing informed caregivers and recorded information sources.",
        TRUE ~ "Repository variable."
      )
    ) %>%
    select(variable, description, type, missing_values, example_value)
  
  qc_flag_dictionary <- tibble(
    flag_variable = c(
      "qc_flag",
      "reconciliation_flag",
      "abs_detail_flag",
      "nc_detail_flag",
      "sm_reconciliation_flag",
      "denominator_qc_flag"
    ),
    possible_value = c(
      "OK / Needs review",
      "Consistent / Partial reasons recorded / No reasons recorded / Overlapping reasons",
      "Abs detail consistent / Abs detail incomplete / Abs detail overlapping",
      "NC detail consistent / NC detail incomplete / NC detail overlapping",
      "SM consistent / Some informed HH missing source / Multiple sources per informed HH / No source recorded",
      "Denominator OK / Denominator reconstructed / Numerator reconstructed / Denominator inconsistency"
    ),
    interpretation = c(
      "Overall QC status.",
      "Compares missed children against total reasons.",
      "Checks whether absence details reconcile with total absent children.",
      "Checks whether non-compliance details reconcile with total refusal/non-compliance children.",
      "Checks whether caregivers informed about SIA have corresponding information-source attribution.",
      "Checks and documents denominator/numerator reconstruction status."
    )
  )
  
  recommended_use <- tibble(
    use_case = c(
      "Coverage analysis",
      "Missed children analysis",
      "Root cause analysis",
      "Social mobilisation analysis",
      "Risk scoring",
      "External reporting"
    ),
    recommendation = c(
      "Use records where denominator_qc_flag != 'Denominator inconsistency'.",
      "Use missed_child, reasons_total, reconciliation_flag and qc_flag together.",
      "Use r_non_FM_* variables as primary reason categories.",
      "Use care_Giver_Informed_SIA, sm_info_* and sm_reconciliation_flag.",
      "Exclude unresolved denominator inconsistencies and review high-risk QC records.",
      "Always include metadata workbook and QC repository when sharing externally."
    )
  )
  
  wb <- createWorkbook()
  
  addWorksheet(wb, "Overview")
  writeData(wb, "Overview", metadata_overview)
  
  addWorksheet(wb, "Variable Dictionary")
  writeData(wb, "Variable Dictionary", variable_dictionary)
  
  addWorksheet(wb, "QC Flags")
  writeData(wb, "QC Flags", qc_flag_dictionary)
  
  addWorksheet(wb, "Recommended Use")
  writeData(wb, "Recommended Use", recommended_use)
  
  for (s in names(wb)) {
    freezePane(wb, s, firstRow = TRUE)
    setColWidths(wb, s, cols = 1:10, widths = "auto")
  }
  
  saveWorkbook(wb, metadata_file, overwrite = TRUE)
  
  message("Metadata workbook exported: ", metadata_file)
}


# ============================================================
# MULTI-FORMAT EXPORT FUNCTIONS
# Exports to CSV, RDS, and Parquet formats
# ============================================================

# ============================================================
# MULTI-FORMAT EXPORT FUNCTIONS
# Exports to CSV, RDS, and Parquet formats
# ============================================================

export_multi_format <- function(data, base_path) {
  # Export data to CSV, RDS, and Parquet formats
  #
  # Parameters:
  #   data: dataframe to export
  #   base_path: base file path (without extension)
  #
  # Returns:
  #   list with paths to exported files
  
  if (is.null(data) || nrow(data) == 0) {
    message("  Warning: No data to export for ", basename(base_path))
    return(NULL)
  }
  
  # Ensure directory exists
  dir_path <- dirname(base_path)
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE)
  }
  
  exported_files <- list()
  
  # 1. Export to CSV
  csv_path <- paste0(base_path, ".csv")
  tryCatch({
    write_csv(data, csv_path)
    csv_size <- round(file.size(csv_path) / 1024 / 1024, 2)
    message(sprintf("  ✓ CSV: %s (%.2f MB)", basename(csv_path), csv_size))
    exported_files$csv <- csv_path
  }, error = function(e) {
    message(sprintf("  ✗ CSV export failed: %s", e$message))
  })
  
  # 2. Export to RDS (compressed, preserves R data types perfectly)
  rds_path <- paste0(base_path, ".rds")
  tryCatch({
    saveRDS(data, rds_path, compress = TRUE)
    rds_size <- round(file.size(rds_path) / 1024 / 1024, 2)
    message(sprintf("  ✓ RDS: %s (%.2f MB)", basename(rds_path), rds_size))
    exported_files$rds <- rds_path
  }, error = function(e) {
    message(sprintf("  ✗ RDS export failed: %s", e$message))
  })
  
  # 3. Export to Parquet (columnar storage, efficient for big data)
  parquet_path <- paste0(base_path, ".parquet")
  tryCatch({
    arrow::write_parquet(data, parquet_path, compression = "snappy")
    parquet_size <- round(file.size(parquet_path) / 1024 / 1024, 2)
    message(sprintf("  ✓ Parquet: %s (%.2f MB)", basename(parquet_path), parquet_size))
    exported_files$parquet <- parquet_path
  }, error = function(e) {
    message(sprintf("  ✗ Parquet export failed: %s", e$message))
    message("    Tip: Install pyarrow with: install.packages('arrow')")
  })
  
  return(exported_files)
} 


# ============================================================
# REGIONAL REPOSITORY BUILDER (UPDATED WITH MULTI-FORMAT EXPORT)
# ============================================================
build_regional_im_repository <- function(processed_results, regional_repository_file, regional_qc_repository_file) {
  message("\n============================================================")
  message("Building Regional IM Repository")
  message("============================================================")
  
  clean_list <- lapply(processed_results, function(x) x$data)
  qc_list <- lapply(processed_results, function(x) x$qc)
  
  regional_im <- bind_rows_fill(clean_list)
  regional_im_qc <- bind_rows_fill(qc_list)
  
  if (nrow(regional_im) == 0) {
    regional_im <- tibble(
      country = character(),
      province = character(),
      district = character(),
      response = character(),
      vaccine.type = character(),
      roundNumber = character(),
      round_start_date = as.Date(character()),
      start_date_IM_end = as.Date(character()),
      end_date_IM_end = as.Date(character())
    )
  }
  
  if (nrow(regional_im_qc) == 0) {
    regional_im_qc <- tibble(
      country = character(),
      province = character(),
      district = character(),
      response = character(),
      vaccine.type = character(),
      roundNumber = character(),
      round_start_date = as.Date(character()),
      start_date_IM_end = as.Date(character()),
      end_date_IM_end = as.Date(character()),
      check_missed = numeric(),
      check_abs_detail = numeric(),
      check_nc_detail = numeric(),
      check_sm_info = numeric(),
      sm_total_awareness_sources = numeric(),
      sm_intensity_group = character(),
      sm_non_compliance_pressure = character(),
      sm_gap_flag = character(),
      sm_priority_flag = character(),
      qc_flag = character()
    )
  }
  
  # Final repository-level safety cleaning before SM intelligence indicators
  regional_im <- sanitize_regional_im_output(regional_im)
  regional_im_qc <- sanitize_regional_im_output(regional_im_qc)
  
  # Final safety pass: guarantees harmonized SM intelligence columns exist
  regional_im <- add_sm_intelligence_indicators(regional_im)
  regional_im_qc <- add_sm_intelligence_indicators(regional_im_qc)
  
  # Re-run final sanitizer after SM intelligence indicators are added
  regional_im <- sanitize_regional_im_output(regional_im)
  regional_im_qc <- sanitize_regional_im_output(regional_im_qc)
  
  if (all(c("country", "province", "district", "start_date_IM_end") %in% names(regional_im))) {
    regional_im <- regional_im %>%
      arrange(country, province, district, start_date_IM_end)
  }
  
  if (all(c("check_missed", "check_abs_detail", "check_nc_detail", "check_sm_info") %in% names(regional_im_qc))) {
    regional_im_qc <- regional_im_qc %>%
      arrange(
        desc(abs(check_missed)),
        desc(abs(check_abs_detail)),
        desc(abs(check_nc_detail)),
        desc(check_sm_info)
      )
  }
  
  # ============================================================
  # EXPORT IN MULTIPLE FORMATS (CSV, RDS, PARQUET)
  # ============================================================
  
  message("\n📦 Exporting Regional IM Repository in multiple formats...")
  message("============================================================")
  
  # Export main repository
  message("\n📊 MAIN REPOSITORY:")
  main_base <- sub("\\.csv$", "", regional_repository_file)
  main_exports <- export_multi_format(regional_im, main_base)
  
  # Export QC repository
  message("\n🔍 QC REPOSITORY:")
  qc_base <- sub("\\.csv$", "", regional_qc_repository_file)
  qc_exports <- export_multi_format(regional_im_qc, qc_base)
  
  # Also export metadata workbook for external users
  metadata_file <- file.path(
    dirname(regional_repository_file),
    "Regional_IM_repository_METADATA.xlsx"
  )
  
  export_im_repository_metadata(
    regional_im = regional_im,
    metadata_file = metadata_file,
    regional_repository_file = regional_repository_file,
    regional_qc_repository_file = regional_qc_repository_file
  )
  
  # Create a manifest file listing all exports
  manifest_file <- file.path(dirname(regional_repository_file), "export_manifest.txt")
  
  manifest_lines <- c(
    "============================================================",
    "REGIONAL IM REPOSITORY EXPORT MANIFEST",
    "============================================================",
    paste("Generated:", Sys.time()),
    paste("Rows in main repository:", nrow(regional_im)),
    paste("Columns in main repository:", ncol(regional_im)),
    paste("Rows in QC repository:", nrow(regional_im_qc)),
    paste("Columns in QC repository:", ncol(regional_im_qc)),
    "",
    "MAIN REPOSITORY FILES:",
    paste("  - CSV:", basename(main_exports$csv), if(!is.null(main_exports$csv)) paste0("(", round(file.size(main_exports$csv) / 1024 / 1024, 2), " MB)") else "(failed)"),
    paste("  - RDS:", basename(main_exports$rds), if(!is.null(main_exports$rds)) paste0("(", round(file.size(main_exports$rds) / 1024 / 1024, 2), " MB)") else "(failed)"),
    paste("  - Parquet:", basename(main_exports$parquet), if(!is.null(main_exports$parquet)) paste0("(", round(file.size(main_exports$parquet) / 1024 / 1024, 2), " MB)") else "(failed)"),
    "",
    "QC REPOSITORY FILES:",
    paste("  - CSV:", basename(qc_exports$csv), if(!is.null(qc_exports$csv)) paste0("(", round(file.size(qc_exports$csv) / 1024 / 1024, 2), " MB)") else "(failed)"),
    paste("  - RDS:", basename(qc_exports$rds), if(!is.null(qc_exports$rds)) paste0("(", round(file.size(qc_exports$rds) / 1024 / 1024, 2), " MB)") else "(failed)"),
    paste("  - Parquet:", basename(qc_exports$parquet), if(!is.null(qc_exports$parquet)) paste0("(", round(file.size(qc_exports$parquet) / 1024 / 1024, 2), " MB)") else "(failed)"),
    "",
    "METADATA:",
    paste("  - Excel:", basename(metadata_file)),
    "",
    "FORMAT RECOMMENDATIONS:",
    "  - CSV:     Universal compatibility, Excel-friendly",
    "  - RDS:     Fast loading in R, preserves all data types",
    "  - Parquet: Best for big data, Python/pandas integration",
    "============================================================"
  )
  
  writeLines(manifest_lines, manifest_file)
  message("\n📋 Export manifest saved: ", basename(manifest_file))
  message("📘 Metadata workbook: ", basename(metadata_file))
  message("============================================================")
  
  list(
    regional_im = regional_im,
    regional_im_qc = regional_im_qc,
    metadata_file = metadata_file,
    manifest_file = manifest_file,
    exports = list(main = main_exports, qc = qc_exports)
  )
}


# ============================================================
# BATCH RUNNER
# ============================================================
process_all_im_files <- function(input_folder, output_folder, qc_output_folder, lookup_table) {
  input_pattern <- paste0("\\.(", paste(SUPPORTED_INPUT_EXTENSIONS, collapse = "|"), ")$")
  
  files <- list.files(
    input_folder,
    pattern = input_pattern,
    full.names = TRUE,
    ignore.case = TRUE
  )
  
  if (length(files) == 0) {
    stop("No supported files found in: ", input_folder)
  }
  
  bad_patterns <- c(
    "fetch_log",
    "processing_summary",
    "regional_im_repository",
    "_qc",
    "^qc$",
    "repository"
  )
  
  keep_file <- function(f) {
    b <- tolower(basename(f))
    !any(stringr::str_detect(b, regex(paste(bad_patterns, collapse = "|"), ignore_case = TRUE)))
  }
  
  files <- files[vapply(files, keep_file, logical(1))]
  
  if (length(files) == 0) {
    stop("No valid IM input files found after excluding logs/repository files in: ", input_folder)
  }
  
  message("Found ", length(files), " files to process.")
  
  processed_results <- list()
  summary_results <- list()
  
  for (f in files) {
    res <- tryCatch(
      process_im_file(f, output_folder, qc_output_folder, lookup_table),
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
  
  list(
    processed_results = processed_results,
    summary_table = bind_rows(summary_results)
  )
}

# ============================================================
# RUN FULL PIPELINE
# ============================================================
batch_run <- process_all_im_files(
  input_folder = input_folder,
  output_folder = output_folder,
  qc_output_folder = qc_output_folder,
  lookup_table = lookup_table
)

summary_table <- batch_run$summary_table
processed_results <- batch_run$processed_results

write_csv(summary_table, summary_file)

message("Successful files with non-null data: ",
        sum(vapply(processed_results, function(x) !is.null(x$data), logical(1))))
message("Successful files with non-null qc: ",
        sum(vapply(processed_results, function(x) !is.null(x$qc), logical(1))))

regional_repo <- build_regional_im_repository(
  processed_results = processed_results,
  regional_repository_file = regional_repository_file,
  regional_qc_repository_file = regional_qc_repository_file
)

print(summary_table)

message("\nBatch processing completed.")
message("Summary file: ", summary_file)
message("Regional repository rows: ", nrow(regional_repo$regional_im))
message("Regional QC rows: ", nrow(regional_repo$regional_im_qc))


# ============================================================
# OPTIONAL: READ FUNCTION FOR ANY FORMAT
# ============================================================

# ============================================================
# OPTIONAL: READ FUNCTION FOR ANY FORMAT
# ============================================================

read_im_repository <- function(file_path) {
  # Read IM repository file regardless of format (CSV, RDS, Parquet)
  #
  # Parameters:
  #   file_path: path to file (can be .csv, .rds, or .parquet)
  #
  # Returns:
  #   dataframe
  
  if (!file.exists(file_path)) {
    # Try alternative extensions
    base_path <- sub("\\.(csv|rds|parquet)$", "", file_path, ignore.case = TRUE)
    
    for (ext in c("csv", "rds", "parquet")) {
      test_path <- paste0(base_path, ".", ext)
      if (file.exists(test_path)) {
        message("Found alternative format: ", basename(test_path))
        file_path <- test_path
        break
      }
    }
    
    if (!file.exists(file_path)) {
      stop("File not found: ", file_path)
    }
  }
  
  ext <- tolower(tools::file_ext(file_path))
  
  result <- switch(ext,
                   csv = readr::read_csv(file_path, show_col_types = FALSE),
                   rds = readRDS(file_path),
                   parquet = arrow::read_parquet(file_path),
                   stop("Unsupported file extension: ", ext, ". Use .csv, .rds, or .parquet")
  )
  
  message(sprintf("✓ Loaded %s: %d rows, %d columns", 
                  basename(file_path), nrow(result), ncol(result)))
  
  return(result)
}

