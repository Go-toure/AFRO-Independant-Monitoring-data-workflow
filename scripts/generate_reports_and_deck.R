#!/usr/bin/env Rscript
# ============================================================
# Combined step: Advocacy Intelligence Report -> PowerPoint Deck
# ============================================================
# Exists so the Shiny dashboard's "Generate Reports" button/pill can run
# both AFRO_Advocacy_Intelligence_Report.R and
# afro_region_im_deck_generation.R as ONE step instead of two -- these
# used to be separate STEPS entries (and briefly, separate pills), but
# the deck is really just a rendering of the report that was just built,
# so one pill/click for both is the right shape.
#
# Sourcing both here (rather than launching them as two separate Rscript
# subprocesses) also means afro_region_im_deck_generation.R's own
# `if (exists("BASE_DIR"))` reuse branch picks up the BASE_DIR that
# AFRO_Advocacy_Intelligence_Report.R already resolved via
# find_workflow_home() a moment earlier in this same R session, instead
# of re-resolving it from scratch.

.grd_this_dir <- dirname(normalizePath(sub("^--file=", "",
  grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))))

source(file.path(.grd_this_dir, "AFRO_Advocacy_Intelligence_Report.R"))
source(file.path(.grd_this_dir, "afro_region_im_deck_generation.R"))
