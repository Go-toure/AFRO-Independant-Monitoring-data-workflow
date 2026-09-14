#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC v2: lookup-calendar-first attribution for form 6839.
#
# Supersedes diagnose_6839_datematch.R -- that one used a narrow
# +-N-day window around a derived monitoring window. Per the
# workflow owner's clarification, on-the-ground implementation can
# run 5-30 days late, and campaigns can also be adjacent in time,
# so the correct rule is an INTERVAL rule, not a narrow window:
#
#   1) If a submission's raw Response/roundNumber text can be
#      matched (directly, or after fixing the one known typo /
#      stripping the one known verbose prefix / recovering the one
#      known field-swap) to an OFFICIAL OBR Name in the calendar,
#      that calendar row wins outright -- Response, Vaccine.type,
#      roundNumber, AND round_start_date are all taken FROM THE
#      CALENDAR (never from the raw text, even where it disagrees --
#      e.g. raw roundNumber = "Rnd5" for an OBR the calendar lists
#      only as Round 1 gets overridden to Rnd1).
#   2) Otherwise (bare place names, or anything else unrecognized),
#      fall back to date attribution: sort every Ethiopia round in
#      the calendar chronologically by round_start_date, and assign
#      the submission to whichever round had most recently STARTED
#      as of date_monitored (round N owns every date from its own
#      start up until round N+1's start -- an "as-of"/rolling join,
#      not a fixed window). A date before the first ever round, or
#      an unparseable date, has no legitimate campaign to attach to
#      and stays excluded.
#
# READ-ONLY. Writes the final attribution to one CSV in data/lookup/
# so it can be reviewed before this logic goes into the production
# script.
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(readxl)
  library(lubridate)
  library(tibble)
  library(arrow)
})

BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
input_file <- file.path(BASE_DIR, "data", "raw", "6839.parquet")
lookup_file <- file.path(BASE_DIR, "data", "lookup", "lookup.xlsx")
out_dir <- file.path(BASE_DIR, "data", "lookup")

# ------------------------------------------------------------
# 1) Ethiopia calendar, sorted chronologically.
# ------------------------------------------------------------
cal_raw <- read_excel(lookup_file)
cal <- cal_raw %>%
  filter(toupper(Country) == "ETHIOPIA") %>%
  transmute(
    Response = `OBR Name`,
    Vaccine.type = Vaccines,
    roundNumber = case_when(
      `Round Number` == "Round 0" ~ "Rnd0",
      `Round Number` == "Round 1" ~ "Rnd1",
      `Round Number` == "Round 2" ~ "Rnd2",
      `Round Number` == "Round 3" ~ "Rnd3",
      `Round Number` == "Round 4" ~ "Rnd4",
      `Round Number` == "Round 5" ~ "Rnd5",
      `Round Number` == "Round 6" ~ "Rnd6",
      TRUE ~ `Round Number`
    ),
    round_start_date = as_date(`Round Start Date`)
  ) %>%
  filter(!is.na(round_start_date)) %>%
  arrange(round_start_date) %>%
  mutate(.cal_id = row_number())

cat("=== Ethiopia calendar, chronological (", nrow(cal), " rounds) ===\n", sep = "")
print(as.data.frame(cal %>% select(.cal_id, Response, Vaccine.type, roundNumber, round_start_date)))

normalize_obr <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x <- str_remove(x, "^BOPV\\s+RND\\s*[0-9]+\\s+")
  gsub("[^A-Z0-9]", "", x)
}

# The one confirmed raw-data typo: "ETH-2026-05-bOPV-sNID" (missing the
# "2") should read as the calendar's real "ETH-2026-05-bOPV2-sNID".
KNOWN_TYPO_FIX <- c("ETH202605BOPVSNID" = "ETH202605BOPV2SNID")

fix_known_typos <- function(norm_x) {
  hit <- norm_x %in% names(KNOWN_TYPO_FIX)
  norm_x[hit] <- unname(KNOWN_TYPO_FIX[norm_x[hit]])
  norm_x
}

cal <- cal %>% mutate(obr_norm = normalize_obr(Response))

# ------------------------------------------------------------
# 2) Raw 6839 data: majority-voted household Response/roundNumber
#    text, plus date_monitored.
# ------------------------------------------------------------
data <- arrow::read_parquet(input_file) %>% as_tibble()

resp_cols  <- sprintf("HH[%d]/HH/Response", 1:10)
round_cols <- sprintf("HH[%d]/HH/roundNumber", 1:10)

majority_value <- function(mat) {
  apply(mat, 1, function(r) {
    r <- trimws(as.character(r))
    r <- r[!is.na(r) & r != ""]
    if (length(r) == 0) return(NA_character_)
    ux <- unique(r)
    if (length(ux) == 1) return(ux)
    tab <- sort(table(r), decreasing = TRUE)
    names(tab)[1]
  })
}

data <- data %>%
  mutate(
    .row_id = row_number(),
    Response_raw = majority_value(as.matrix(data[resp_cols])),
    roundNumber_raw = majority_value(as.matrix(data[round_cols])),
    date_monitored_parsed = suppressWarnings(as_date(date_monitored)),
    resp_norm = fix_known_typos(normalize_obr(Response_raw)),
    round_norm = fix_known_typos(normalize_obr(roundNumber_raw))
  )

# ------------------------------------------------------------
# 3) TEXT MATCH pass (fully vectorized): try Response_raw, then
#    roundNumber_raw (covers the swapped-fields case), against
#    calendar OBR names. Multi-round OBRs (currently only
#    "ETH-2026-05-bOPV2-sNID") are disambiguated using the raw
#    roundNumber text.
# ------------------------------------------------------------
obr_counts <- table(cal$obr_norm)
dup_norms <- names(obr_counts[obr_counts > 1])

cal_unique <- cal %>% filter(!(obr_norm %in% dup_norms))
cal_dup <- cal %>%
  filter(obr_norm %in% dup_norms) %>%
  mutate(round_key = gsub("[^A-Z0-9]", "", toupper(roundNumber)))

raw_round_key <- gsub("[^A-Z0-9]", "", toupper(trimws(data$roundNumber_raw)))

match_one_field <- function(norm_field) {
  idx_unique <- match(norm_field, cal_unique$obr_norm)
  cal_id_unique <- cal_unique$.cal_id[idx_unique]

  key_data <- paste(norm_field, raw_round_key, sep = "||")
  key_cal <- paste(cal_dup$obr_norm, cal_dup$round_key, sep = "||")
  idx_dup <- match(key_data, key_cal)
  cal_id_dup <- cal_dup$.cal_id[idx_dup]

  dplyr::coalesce(cal_id_unique, cal_id_dup)
}

cal_id_from_resp <- match_one_field(data$resp_norm)
cal_id_from_round <- match_one_field(data$round_norm)

matched_cal_id <- dplyr::coalesce(cal_id_from_resp, cal_id_from_round)
match_method <- dplyr::case_when(
  !is.na(cal_id_from_resp) ~ "text_response",
  !is.na(cal_id_from_round) ~ "text_round_swap",
  TRUE ~ NA_character_
)

cat("\n=== TEXT MATCH pass ===\n")
cat("Resolved by text match:", sum(!is.na(matched_cal_id)), "out of", nrow(data), "\n")
print(table(match_method, useNA = "always"))

# ------------------------------------------------------------
# 4) DATE FALLBACK pass, for everything text-match couldn't
#    resolve: as-of / rolling assignment to the most recent round
#    that had started by date_monitored.
# ------------------------------------------------------------
sorted_starts <- cal$round_start_date  # already sorted ascending
unresolved_idx <- which(is.na(matched_cal_id) & !is.na(data$date_monitored_parsed))

if (length(unresolved_idx) > 0) {
  pos <- findInterval(data$date_monitored_parsed[unresolved_idx], sorted_starts)
  valid <- pos > 0
  matched_cal_id[unresolved_idx[valid]] <- cal$.cal_id[pos[valid]]
  match_method[unresolved_idx[valid]] <- "date_fallback"
}

cat("\n=== DATE FALLBACK pass ===\n")
cat("Additionally resolved by date fallback:", sum(match_method == "date_fallback", na.rm = TRUE), "\n")
cat("Still unresolved (before first round, or unparseable date):", sum(is.na(matched_cal_id)), "\n")

# ------------------------------------------------------------
# 5) Final attribution + summary
# ------------------------------------------------------------
final <- data %>%
  mutate(.cal_id = matched_cal_id, match_method = match_method) %>%
  left_join(cal %>% select(.cal_id, cal_Response = Response, cal_Vaccine = Vaccine.type,
                            cal_roundNumber = roundNumber, cal_round_start_date = round_start_date),
             by = ".cal_id")

cat("\n=== Final attribution summary ===\n")
cat("Total submissions:", nrow(final), "\n")
cat("Resolved (kept):", sum(!is.na(final$.cal_id)), "\n")
cat("Excluded (unresolved):", sum(is.na(final$.cal_id)), "\n\n")

cat("By match method:\n")
print(table(final$match_method, useNA = "always"))

cat("\nResolved rows by calendar campaign/round assigned:\n")
print(as.data.frame(
  final %>% filter(!is.na(.cal_id)) %>%
    count(cal_Response, cal_roundNumber, cal_round_start_date, match_method, sort = TRUE)
))

cat("\nWhere text-matched, how often did the calendar's roundNumber differ from the raw roundNumber text?\n")
text_matched <- final %>% filter(match_method %in% c("text_response", "text_round_swap"))
disagree <- text_matched %>%
  filter(toupper(trimws(roundNumber_raw)) != toupper(trimws(cal_roundNumber)))
cat("Disagreements:", nrow(disagree), "out of", nrow(text_matched), "text-matched rows\n")
if (nrow(disagree) > 0) {
  print(as.data.frame(disagree %>% count(Response_raw, roundNumber_raw, cal_Response, cal_roundNumber, sort = TRUE)))
}

cat("\nDate-fallback rows: distribution of the raw Response text that triggered the fallback\n")
print(as.data.frame(
  final %>% filter(match_method == "date_fallback") %>%
    count(Response_raw, cal_Response, cal_roundNumber, sort = TRUE) %>%
    utils::head(20)
))

out_file <- file.path(out_dir, "6839_final_attribution.csv")
write_csv(
  final %>% select(.row_id, Response_raw, roundNumber_raw, date_monitored_parsed,
                    match_method, cal_Response, cal_Vaccine, cal_roundNumber, cal_round_start_date),
  out_file
)
cat("\nWrote:", out_file, "\n")
