#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC: check the preparedness lookup table (data/lookup/
# lookup.xlsx) for Ethiopia-related entries, before deciding how
# to handle form 6839's messy Response/roundNumber values.
#
# Two things this settles:
#   1) Does the lookup table define a round number for the
#      swapped-code campaign "ETH-2025-10-b-nOPV2-sNID"? If so,
#      that's the authoritative source -- no guessing needed.
#   2) Do any of "ADDIS ABABA" / "Addis Ababa" / "Mekelle" appear
#      in the lookup table as an OBR Name? If so, those ~112K
#      bare-place-name records could be mapped after all, instead
#      of being excluded.
#
# Also lists every ETH-prefixed OBR Name found, so we can see
# which of 6839's "clean" codes (ETH-2025-12-b-nOPV2-NIDs,
# ETH-2026-03-nOPV2-sNID, ETH-2026-05-bOPV-sNID,
# ETH-2026-05-bOPV2-sNID) will actually successfully join and
# pick up round_start_date / Vaccine.type from the lookup table.
#
# READ-ONLY. Writes one CSV to data/lookup/.
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(readxl)
  library(lubridate)
})

BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
lookup_file <- file.path(BASE_DIR, "data", "lookup", "lookup.xlsx")
out_dir <- file.path(BASE_DIR, "data", "lookup")

if (!file.exists(lookup_file)) stop("lookup.xlsx not found at: ", lookup_file)

raw <- read_excel(lookup_file)
cat("lookup.xlsx columns:", paste(names(raw), collapse = ", "), "\n")
cat("lookup.xlsx rows:", nrow(raw), "\n\n")

# Try to find the OBR Name-like column robustly (name may vary slightly).
obr_col <- names(raw)[str_detect(tolower(names(raw)), "obr")]
round_col <- names(raw)[str_detect(tolower(names(raw)), "round")]
vaccine_col <- names(raw)[str_detect(tolower(names(raw)), "vaccine")]
date_col <- names(raw)[str_detect(tolower(names(raw)), "date")]

cat("Detected columns -> OBR:", paste(obr_col, collapse = "/"),
    " | Round:", paste(round_col, collapse = "/"),
    " | Vaccine:", paste(vaccine_col, collapse = "/"),
    " | Date:", paste(date_col, collapse = "/"), "\n\n")

if (length(obr_col) == 0) stop("Could not find an OBR-like column in lookup.xlsx")
obr_col <- obr_col[1]

eth_rows <- raw %>% filter(str_detect(toupper(.data[[obr_col]]), "ETH"))
cat("=== All ETH-prefixed OBR Name rows in lookup.xlsx (", nrow(eth_rows), " found) ===\n", sep = "")
print(as.data.frame(eth_rows))

cat("\n=== Specifically searching for 'ETH-2025-10-b-nOPV2-sNID' (the swapped-code campaign) ===\n")
swap_match <- raw %>% filter(str_detect(toupper(.data[[obr_col]]), toupper("ETH-2025-10-b-nOPV2-sNID")))
if (nrow(swap_match) > 0) {
  print(as.data.frame(swap_match))
} else {
  cat("NOT FOUND in lookup.xlsx.\n")
}

cat("\n=== Specifically searching for 'ADDIS ABABA' / 'Mekelle' as an OBR Name ===\n")
place_match <- raw %>% filter(str_detect(toupper(.data[[obr_col]]), "ADDIS|MEKELLE"))
if (nrow(place_match) > 0) {
  print(as.data.frame(place_match))
} else {
  cat("NOT FOUND in lookup.xlsx -- these place-name entries cannot be mapped via the lookup table.\n")
}

cat("\n=== Checking the other 6839 'clean' OBR codes for a lookup match ===\n")
other_codes <- c("ETH-2025-12-b-nOPV2-NIDs", "ETH-2026-03-nOPV2-sNID", "ETH-2026-05-bOPV-sNID", "ETH-2026-05-bOPV2-sNID")
for (code in other_codes) {
  m <- raw %>% filter(toupper(.data[[obr_col]]) == toupper(code))
  cat(sprintf("  %-30s : %d match(es)\n", code, nrow(m)))
  if (nrow(m) > 0) print(as.data.frame(m))
}

out_file <- file.path(out_dir, "6839_lookup_eth_rows.csv")
write_csv(eth_rows, out_file)
cat("\nWrote:", out_file, "\n")
