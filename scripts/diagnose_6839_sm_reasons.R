#!/usr/bin/env Rscript
# ============================================================
# DIAGNOSTIC: check SM (source-of-information) and reasons-for-
# non-vaccination harmonization for form 6839, empirically.
#
# Rather than tracing the ~4000 lines of shared regex/pattern
# matching by eye (error-prone), this runs the REAL process_im_file()
# end-to-end (writing only to a TEMP folder -- your real data/final
# and data/processed/qc are untouched) and inspects the actual
# computed sm_* / r_abs_* / r_nc_* columns plus their QC
# reconciliation flags, to see whether these are being populated
# with real data or coming out blank/zero for 6839.
#
# Also independently profiles the RAW HH[n]/HH/Source_Info_SIA_HH
# and HH[n]/HH/Other_Source_Info text fields, and the raw
# household-level absence/non-compliance detail fields, so we have
# ground truth to compare the pipeline's output against.
#
# Run with:  Rscript scripts\diagnose_6839_sm_reasons.R
# ============================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(tibble)
  library(arrow)
})

BASE_DIR <- "C:/Users/TOURE/Documents/im_workflow"
builder_script <- file.path(BASE_DIR, "scripts", "regional_im_repository_builder.R")
input_file <- file.path(BASE_DIR, "data", "raw", "6839.parquet")

# ------------------------------------------------------------
# 1) Ground truth from the RAW data.
# ------------------------------------------------------------
cat("=== RAW DATA: Source_Info_SIA_HH / Other_Source_Info sample ===\n")
raw <- arrow::read_parquet(input_file) %>% as_tibble()

sm_cols <- sprintf("HH[%d]/HH/Source_Info_SIA_HH", 1:10)
other_sm_cols <- sprintf("HH[%d]/HH/Other_Source_Info", 1:10)

non_blank_sm <- sum(!is.na(raw[[sm_cols[1]]]) & trimws(raw[[sm_cols[1]]]) != "")
cat("HH[1]/HH/Source_Info_SIA_HH -- non-blank values:", non_blank_sm, "out of", nrow(raw), "\n")
cat("Sample values:\n")
print(utils::head(unique(raw[[sm_cols[1]]][trimws(raw[[sm_cols[1]]]) != ""]), 10))

non_blank_other <- sum(!is.na(raw[[other_sm_cols[1]]]) & trimws(raw[[other_sm_cols[1]]]) != "")
cat("\nHH[1]/HH/Other_Source_Info -- non-blank values:", non_blank_other, "out of", nrow(raw), "\n")

# Raw form-level (top-level) absence / non-compliance totals -- these
# were already confirmed present by name in the earlier structure dump.
raw_reason_cols <- c(
  "Tot_child_Abs_Farm_T", "Tot_child_Abs_Other_T", "Tot_child_Abs_Market_T",
  "Tot_child_Abs_School_T", "Sum_child_Abs_Travelling", "Tot_child_Abs_SocialEvent",
  "Tot_child_Abs_Play_areas_T", "Sum_child_Abs_Parent_Absent",
  "Tot_child_NC_Religious_beliefs_T", "Tot_child_NC_sideEffects",
  "Sum_Too_many_doses", "Sum_Child_sick", "Sum_NC_COVID", "Sum_NC_Others"
)
cat("\n=== RAW top-level reason-for-non-vaccination fields: non-zero counts ===\n")
for (cc in raw_reason_cols) {
  if (cc %in% names(raw)) {
    v <- suppressWarnings(as.numeric(as.character(raw[[cc]])))
    cat(sprintf("  %-32s sum=%s | non-zero rows=%d\n", cc, format(sum(v, na.rm = TRUE), big.mark=","), sum(!is.na(v) & v > 0)))
  } else {
    cat(sprintf("  %-32s MISSING\n", cc))
  }
}

# ------------------------------------------------------------
# 2) Real pipeline output via process_im_file() (temp folder only).
# ------------------------------------------------------------
cat("\n=== Running real process_im_file() (temp folder only) ===\n")
lines <- readLines(builder_script, warn = FALSE, encoding = "UTF-8")
cut_idx <- grep("^batch_run <- process_all_im_files", lines)[1]
def_lines <- lines[seq_len(cut_idx - 1)]
env <- new.env()
eval(parse(text = def_lines), envir = env)

file_name <- tools::file_path_sans_ext(basename(input_file))
tmp_out <- file.path(tempdir(), "diagnose_6839_sm_out")
tmp_qc <- file.path(tempdir(), "diagnose_6839_sm_qc")
dir.create(tmp_out, showWarnings = FALSE, recursive = TRUE)
dir.create(tmp_qc, showWarnings = FALSE, recursive = TRUE)

res <- env$process_im_file(
  input_file = input_file,
  output_folder = tmp_out,
  qc_output_folder = tmp_qc,
  lookup_table = env$lookup_table
)

if (is.null(res$data)) {
  stop("process_im_file() returned NULL data -- something upstream is broken; run diagnose_6839_verify.R first.")
}

FE <- res$data
cat("Output rows (aggregated groups):", nrow(FE), "\n\n")

sm_out_cols <- c(
  "sm_info_tv", "sm_info_radio", "sm_info_others", "sm_info_hworker",
  "sm_info_mob_vanpa", "sm_info_town_crier", "sm_info_volunteers",
  "sm_info_com_infocentre", "sm_info_community_leader", "sm_info_religious_leader",
  "sm_info_mobile_social_media", "sm_total_sources", "care_Giver_Informed_SIA",
  "percent_care_Giver_Informed_SIA"
)
cat("=== OUTPUT: SM (source-of-information) columns ===\n")
for (cc in sm_out_cols) {
  if (cc %in% names(FE)) {
    v <- suppressWarnings(as.numeric(FE[[cc]]))
    cat(sprintf("  %-32s sum=%-12s mean=%-10s non-zero rows=%d/%d\n",
                cc, format(sum(v, na.rm = TRUE), big.mark=","),
                round(mean(v, na.rm = TRUE), 3), sum(!is.na(v) & v > 0), nrow(FE)))
  } else {
    cat(sprintf("  %-32s MISSING FROM OUTPUT\n", cc))
  }
}

reason_out_cols <- c(
  "r_abs_sick", "r_abs_play_areas", "r_abs_market", "r_abs_school", "r_abs_farm",
  "r_abs_social_event", "r_abs_travelling", "r_abs_parent_absent", "r_abs_other_detail",
  "r_nc_religious_beliefs", "r_nc_side_effects", "r_nc_too_many_doses", "r_nc_child_sick",
  "r_nc_covid", "r_nc_other_detail", "r_nc_not_decided", "r_nc_polio_free", "r_nc_nopv",
  "abs_detail_total", "nc_detail_total", "reasons_total",
  "r_non_FM_Absent", "r_non_FM_NC", "r_non_FM_hh_notvisited", "r_non_FM_hh_notrevisited",
  "r_non_FM_sleep", "r_non_FM_vaccinatedRoutine", "r_non_FM_other"
)
cat("\n=== OUTPUT: reasons-for-non-vaccination columns ===\n")
for (cc in reason_out_cols) {
  if (cc %in% names(FE)) {
    v <- suppressWarnings(as.numeric(FE[[cc]]))
    cat(sprintf("  %-32s sum=%-12s mean=%-10s non-zero rows=%d/%d\n",
                cc, format(sum(v, na.rm = TRUE), big.mark=","),
                round(mean(v, na.rm = TRUE), 3), sum(!is.na(v) & v > 0), nrow(FE)))
  } else {
    cat(sprintf("  %-32s MISSING FROM OUTPUT\n", cc))
  }
}

cat("\n=== QC reconciliation flags ===\n")
for (cc in c("reconciliation_flag", "abs_detail_flag", "nc_detail_flag", "sm_reconciliation_flag", "denominator_qc_flag", "qc_flag")) {
  if (cc %in% names(FE)) {
    cat("--", cc, "--\n")
    print(table(FE[[cc]], useNA = "always"))
  }
}

cat("\nDone.\n")
