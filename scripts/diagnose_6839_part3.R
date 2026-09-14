#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC PART 3: form 6839 (Ethiopia IM) -- context for each
# of the 7 raw Response values found in part 2, to help decide
# how to map them to canonical (Response, roundNumber, Vaccine.type).
#
# For each raw (Response, roundNumber) combination found in part 2,
# report: number of submissions (rows, not household-slots), the
# date_monitored range, and which Region/District values appear --
# this is meant to help recall which real-world campaign each
# place-name-only entry (e.g. "Addis Ababa" / "Mekelle") actually
# corresponds to.
#
# READ-ONLY. Writes one CSV to data/lookup/.
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(tibble)
  library(arrow)
})

BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
input_file <- file.path(BASE_DIR, "data", "raw", "6839.parquet")
out_dir <- file.path(BASE_DIR, "data", "lookup")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

data <- arrow::read_parquet(input_file) %>% as_tibble()

resp_cols  <- sprintf("HH[%d]/HH/Response", 1:10)
round_cols <- sprintf("HH[%d]/HH/roundNumber", 1:10)

first_non_blank <- function(df, cols) {
  m <- as.matrix(df[cols])
  apply(m, 1, function(r) {
    r <- trimws(r)
    r <- r[!is.na(r) & r != ""]
    if (length(r) == 0) return(NA_character_)
    ux <- unique(r)
    if (length(ux) == 1) return(ux)
    tab <- sort(table(r), decreasing = TRUE)
    names(tab)[1]
  })
}

cat("Deriving submission-level Response / roundNumber (first/majority across households)...\n")
data <- data %>%
  mutate(
    Response_sub = first_non_blank(., resp_cols),
    roundNumber_sub = first_non_blank(., round_cols),
    date_monitored_parsed = suppressWarnings(as.Date(date_monitored))
  )

summary_tab <- data %>%
  filter(!is.na(Response_sub)) %>%
  group_by(Response_sub, roundNumber_sub) %>%
  summarise(
    n_submissions = n(),
    min_date = suppressWarnings(min(date_monitored_parsed, na.rm = TRUE)),
    max_date = suppressWarnings(max(date_monitored_parsed, na.rm = TRUE)),
    n_distinct_region = n_distinct(Region),
    top_regions = paste(utils::head(names(sort(table(Region), decreasing = TRUE)), 5), collapse = " | "),
    n_distinct_district = n_distinct(District),
    .groups = "drop"
  ) %>%
  arrange(desc(n_submissions))

cat("\n=== Per (Response, roundNumber) submission-level summary ===\n")
print(as.data.frame(summary_tab), row.names = FALSE)

out_file <- file.path(out_dir, "6839_response_round_context.csv")
write_csv(summary_tab, out_file)
cat("\nWrote:", out_file, "\n")
