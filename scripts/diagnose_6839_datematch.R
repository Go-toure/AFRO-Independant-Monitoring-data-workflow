#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC: test LOOKUP-TABLE-FIRST matching for form 6839.
#
# Per the workflow owner: the lookup table (data/lookup/lookup.xlsx,
# the official campaign calendar) should be the base case for
# Response / Vaccine.type / roundNumber / round_start_date -- not
# the raw form's messy text fields. This script tests whether we
# can attribute each 6839 submission to an official Ethiopia
# campaign round using date_monitored against that round's expected
# monitoring window (round_start_date + 4/+5 days, same logic
# already used by load_preparedness_lookup() in the main script),
# instead of trusting the raw Response/roundNumber text.
#
# For several tolerance widths around that window, it reports:
#   - how many submissions match exactly one official round (usable)
#   - how many match zero rounds (would be excluded)
#   - how many match more than one round (ambiguous -- ties)
#   - for the ones with exactly one match, whether the matched
#     campaign's Response agrees with the raw (majority-voted)
#     Response text, as a sanity check on the method
#   - specifically for the "Addis Ababa"/"Mekelle" bare-place-name
#     rows (currently excluded because their raw text carries no
#     usable code), how many CAN be rescued via date matching
#
# READ-ONLY. Writes one CSV to data/lookup/.
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
# Load the Ethiopia slice of the official campaign calendar,
# with the same start_date/end_date monitoring-window logic
# load_preparedness_lookup() uses in the main script.
# ------------------------------------------------------------
cal_raw <- read_excel(lookup_file)
cal <- cal_raw %>%
  filter(toupper(Country) == "ETHIOPIA") %>%
  transmute(
    Response = `OBR Name`,
    Vaccine.type = Vaccines,
    roundNumber_lookup = `Round Number`,
    round_start_date = as_date(`Round Start Date`),
    round_end_date = as_date(`Round End Date`)
  ) %>%
  mutate(
    roundNumber = case_when(
      roundNumber_lookup == "Round 0" ~ "Rnd0",
      roundNumber_lookup == "Round 1" ~ "Rnd1",
      roundNumber_lookup == "Round 2" ~ "Rnd2",
      roundNumber_lookup == "Round 3" ~ "Rnd3",
      roundNumber_lookup == "Round 4" ~ "Rnd4",
      roundNumber_lookup == "Round 5" ~ "Rnd5",
      roundNumber_lookup == "Round 6" ~ "Rnd6",
      TRUE ~ roundNumber_lookup
    ),
    # Same monitoring-window derivation as load_preparedness_lookup().
    monitor_start = round_start_date + 4,
    monitor_end = monitor_start + 1
  ) %>%
  select(Response, Vaccine.type, roundNumber, round_start_date, round_end_date, monitor_start, monitor_end)

cat("=== Ethiopia rounds in lookup.xlsx (", nrow(cal), ") ===\n", sep = "")
print(as.data.frame(cal))

# ------------------------------------------------------------
# Raw 6839 data: date_monitored + majority-voted raw Response/
# roundNumber (for the sanity-check cross-tab only).
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
    date_monitored_parsed = suppressWarnings(as_date(date_monitored))
  )

cat("\nRows with a parseable date_monitored:", sum(!is.na(data$date_monitored_parsed)),
    "out of", nrow(data), "\n")
cat("date_monitored range in this file:", as.character(min(data$date_monitored_parsed, na.rm = TRUE)),
    "to", as.character(max(data$date_monitored_parsed, na.rm = TRUE)), "\n\n")

# ------------------------------------------------------------
# Try several tolerance widths (days before/after the derived
# monitor_start/monitor_end window) and report match quality.
# ------------------------------------------------------------
test_tolerance <- function(tol_days) {
  matches <- data %>%
    select(.row_id, date_monitored_parsed, Response_raw, roundNumber_raw) %>%
    filter(!is.na(date_monitored_parsed)) %>%
    tidyr::crossing(cal %>% mutate(.cal_id = row_number())) %>%
    filter(
      date_monitored_parsed >= (monitor_start - tol_days),
      date_monitored_parsed <= (monitor_end + tol_days)
    )

  match_counts <- matches %>% count(.row_id, name = "n_candidates")

  n_zero <- sum(!is.na(data$date_monitored_parsed)) - nrow(match_counts)
  n_one <- sum(match_counts$n_candidates == 1)
  n_multi <- sum(match_counts$n_candidates > 1)

  # Agreement check for the unambiguous (n==1) matches.
  single <- matches %>%
    semi_join(match_counts %>% filter(n_candidates == 1), by = ".row_id")

  agree <- mean(toupper(trimws(single$Response_raw)) == toupper(trimws(single$Response)), na.rm = TRUE)

  list(
    tol_days = tol_days,
    n_zero_match = n_zero,
    n_one_match = n_one,
    n_multi_match = n_multi,
    pct_one_match_agrees_with_raw_response = round(100 * agree, 1)
  )
}

cat("=== Match-quality summary at different date tolerances ===\n")
tol_results <- lapply(c(0, 2, 5, 10, 14), test_tolerance)
tol_df <- bind_rows(lapply(tol_results, as_tibble))
print(as.data.frame(tol_df))

# ------------------------------------------------------------
# Focus on the currently-excluded bare place-name rows: how many
# get exactly one date-match at tol=5 days?
# ------------------------------------------------------------
tol_days <- 5
place_rows <- data %>%
  filter(!is.na(date_monitored_parsed)) %>%
  filter(toupper(trimws(Response_raw)) %in% c("ADDIS ABABA", "MEKELLE"))

place_matches <- place_rows %>%
  select(.row_id, date_monitored_parsed, Response_raw, roundNumber_raw) %>%
  tidyr::crossing(cal %>% mutate(.cal_id = row_number())) %>%
  filter(
    date_monitored_parsed >= (monitor_start - tol_days),
    date_monitored_parsed <= (monitor_end + tol_days)
  )

place_match_counts <- place_matches %>% count(.row_id, name = "n_candidates")

cat("\n=== Bare place-name rows (Addis Ababa / Mekelle):", nrow(place_rows), "with a parseable date ===\n")
cat("At tolerance =", tol_days, "days:\n")
cat("  0 candidate rounds:", nrow(place_rows) - nrow(place_match_counts), "\n")
cat("  exactly 1 candidate round (rescuable):", sum(place_match_counts$n_candidates == 1), "\n")
cat("  >1 candidate rounds (ambiguous):", sum(place_match_counts$n_candidates > 1), "\n")

if (sum(place_match_counts$n_candidates == 1) > 0) {
  rescued <- place_matches %>%
    semi_join(place_match_counts %>% filter(n_candidates == 1), by = ".row_id")
  cat("\nWhich official campaigns would these rescued rows be assigned to:\n")
  print(as.data.frame(rescued %>% count(Response, roundNumber, sort = TRUE)))
}

out_file <- file.path(out_dir, "6839_datematch_summary.csv")
write_csv(tol_df, out_file)
cat("\nWrote:", out_file, "\n")
