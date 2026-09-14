#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC PART 2: form 6839 (Ethiopia IM) -- Response /
# roundNumber contamination + within-row consistency.
#
# Part 1 (diagnose_6839.R) established that:
#   - Response and roundNumber are captured PER HOUSEHOLD, inside
#     HH[1..10]/HH/Response and HH[1..10]/HH/roundNumber, instead
#     of once per submission (top-level).
#   - Sampled unique values suggested some contamination: the
#     roundNumber field sometimes holds a full OBR-style code
#     (e.g. "ETH-2025-10-b-nOPV2-sNID") instead of "Rnd#", and the
#     Response field sometimes holds a place name (e.g. "Mekelle")
#     instead of a proper OBR/response code.
#
# This script is READ-ONLY. It pools HH[1..10]/HH/Response and
# HH[1..10]/HH/roundNumber across ALL households and rows to get:
#   1) full frequency table of every distinct Response value
#   2) full frequency table of every distinct roundNumber value
#   3) a cross-tab of (Response, roundNumber) pairs as they occur
#      together in the same household slot, to see whether the
#      "place name" values and the "OBR code in roundNumber"
#      values are correlated (e.g. always co-occurring) or random
#   4) per-submission (row) consistency: for each row, are all 10
#      households' Response values identical? Same for roundNumber?
#   5) full unique values for HH[n]/HH/count and top-level Country
#
# Writes 3 small CSVs to data/lookup/ and prints key stats.
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(tibble)
  library(tidyr)
  library(arrow)
})

BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
input_file <- file.path(BASE_DIR, "data", "raw", "6839.parquet")
out_dir <- file.path(BASE_DIR, "data", "lookup")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!file.exists(input_file)) stop("6839.parquet not found at: ", input_file)

cat("Reading 6839.parquet...\n")
data <- arrow::read_parquet(input_file) %>% as_tibble()
cat("rows:", nrow(data), " cols:", ncol(data), "\n\n")

resp_cols  <- sprintf("HH[%d]/HH/Response", 1:10)
round_cols <- sprintf("HH[%d]/HH/roundNumber", 1:10)
count_cols <- sprintf("HH[%d]/HH/count", 1:10)

stopifnot(all(resp_cols %in% names(data)))
stopifnot(all(round_cols %in% names(data)))

data <- data %>% mutate(.row_id = row_number())

# ------------------------------------------------------------
# 1) Pooled Response frequency table
# ------------------------------------------------------------
resp_long <- data %>%
  select(.row_id, all_of(resp_cols)) %>%
  pivot_longer(cols = all_of(resp_cols), names_to = "hh_slot", values_to = "Response") %>%
  mutate(Response_clean = ifelse(is.na(Response) | trimws(Response) == "", NA_character_, trimws(Response)))

resp_freq <- resp_long %>%
  filter(!is.na(Response_clean)) %>%
  count(Response_clean, sort = TRUE, name = "n_household_slots")

cat("=== Full pooled Response value frequency (non-blank household slots) ===\n")
print(as.data.frame(resp_freq), row.names = FALSE)
write_csv(resp_freq, file.path(out_dir, "6839_response_freq.csv"))

cat("\nBlank/NA Response slots:", sum(is.na(resp_long$Response_clean)), "out of", nrow(resp_long), "\n")

# ------------------------------------------------------------
# 2) Pooled roundNumber frequency table
# ------------------------------------------------------------
round_long <- data %>%
  select(.row_id, all_of(round_cols)) %>%
  pivot_longer(cols = all_of(round_cols), names_to = "hh_slot", values_to = "roundNumber") %>%
  mutate(roundNumber_clean = ifelse(is.na(roundNumber) | trimws(roundNumber) == "", NA_character_, trimws(roundNumber)))

round_freq <- round_long %>%
  filter(!is.na(roundNumber_clean)) %>%
  count(roundNumber_clean, sort = TRUE, name = "n_household_slots")

cat("\n=== Full pooled roundNumber value frequency (non-blank household slots) ===\n")
print(as.data.frame(round_freq), row.names = FALSE)
write_csv(round_freq, file.path(out_dir, "6839_roundnumber_freq.csv"))

cat("\nBlank/NA roundNumber slots:", sum(is.na(round_long$roundNumber_clean)), "out of", nrow(round_long), "\n")

# ------------------------------------------------------------
# 3) Cross-tab: (Response, roundNumber) pairs in the SAME
#    household slot (hh index within the same row)
# ------------------------------------------------------------
resp_long2 <- resp_long %>%
  mutate(hh_num = str_extract(hh_slot, "(?<=HH\\[)[0-9]+(?=\\])")) %>%
  select(.row_id, hh_num, Response_clean)

round_long2 <- round_long %>%
  mutate(hh_num = str_extract(hh_slot, "(?<=HH\\[)[0-9]+(?=\\])")) %>%
  select(.row_id, hh_num, roundNumber_clean)

pair_tab <- resp_long2 %>%
  inner_join(round_long2, by = c(".row_id", "hh_num")) %>%
  filter(!is.na(Response_clean) | !is.na(roundNumber_clean)) %>%
  count(Response_clean, roundNumber_clean, sort = TRUE, name = "n_household_slots")

cat("\n=== Cross-tab: (Response, roundNumber) pairs within the same household slot ===\n")
print(as.data.frame(pair_tab), row.names = FALSE)
write_csv(pair_tab, file.path(out_dir, "6839_response_round_pairs.csv"))

# ------------------------------------------------------------
# 4) Per-submission (row) consistency check
# ------------------------------------------------------------
row_resp_consistency <- resp_long %>%
  filter(!is.na(Response_clean)) %>%
  group_by(.row_id) %>%
  summarise(n_distinct_response = n_distinct(Response_clean), .groups = "drop")

row_round_consistency <- round_long %>%
  filter(!is.na(roundNumber_clean)) %>%
  group_by(.row_id) %>%
  summarise(n_distinct_round = n_distinct(roundNumber_clean), .groups = "drop")

cat("\n=== Per-submission Response consistency ===\n")
cat("Rows with >=1 non-blank Response:", nrow(row_resp_consistency), "out of", nrow(data), "\n")
print(table(row_resp_consistency$n_distinct_response))

cat("\n=== Per-submission roundNumber consistency ===\n")
cat("Rows with >=1 non-blank roundNumber:", nrow(row_round_consistency), "out of", nrow(data), "\n")
print(table(row_round_consistency$n_distinct_round))

n_multi_resp <- sum(row_resp_consistency$n_distinct_response > 1)
n_multi_round <- sum(row_round_consistency$n_distinct_round > 1)
cat("\nRows where Response DISAGREES across households:", n_multi_resp, "\n")
cat("Rows where roundNumber DISAGREES across households:", n_multi_round, "\n")

if (n_multi_round > 0) {
  cat("\nSample of rows where roundNumber disagrees across households (up to 10):\n")
  bad_rows <- row_round_consistency %>% filter(n_distinct_round > 1) %>% pull(.row_id) %>% utils::head(10)
  sample_bad <- data %>% filter(.row_id %in% bad_rows) %>% select(.row_id, all_of(round_cols))
  print(as.data.frame(sample_bad))
}

# ------------------------------------------------------------
# 5) HH[n]/HH/count full unique values + top-level Country
# ------------------------------------------------------------
cat("\n=== HH[1]/HH/count full unique values (up to 30) ===\n")
count_vals <- sort(unique(trimws(as.character(data[["HH[1]/HH/count"]]))))
print(utils::head(count_vals, 30))

cat("\n=== Top-level Country full unique values ===\n")
print(table(as.character(data$Country), useNA = "always"))

cat("\nDone. CSVs written to data/lookup/:\n")
cat("  6839_response_freq.csv\n  6839_roundnumber_freq.csv\n  6839_response_round_pairs.csv\n")
