#!/usr/bin/env bash

# ============================================================
# AFRO IM AUTOMATED PIPELINE RUNNER - BASH
# Modes:
#   full
#   fetch
#   process
#   clean
#   fetch_process
#   process_clean
# ============================================================

set -e

BASE_DIR="/c/Users/TOURE/Documents/im_workflow"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGS_DIR="$BASE_DIR/logs"
FINAL_DIR="$BASE_DIR/data/final"

mkdir -p "$LOGS_DIR" "$FINAL_DIR"

MODE="${1:-full}"

run_step() {
  STEP_NAME="$1"
  COMMAND="$2"
  LOG_FILE="$3"

  echo "------------------------------------------------------------"
  echo "RUNNING STEP: $STEP_NAME"
  echo "Log file: $LOG_FILE"
  echo "------------------------------------------------------------"

  eval "$COMMAND" > "$LOG_FILE" 2>&1

  echo "COMPLETED STEP: $STEP_NAME"
  echo
}

run_fetch() {
  run_step \
    "FETCH IM DATA" \
    "python \"$SCRIPTS_DIR/Fetch_im_data.py\" --force-full" \
    "$LOGS_DIR/01_fetch_im_data.log"
}

run_process() {
  run_step \
    "BUILD REGIONAL IM REPOSITORY" \
    "Rscript \"$SCRIPTS_DIR/regional_im_repository_builder.R\"" \
    "$LOGS_DIR/02_regional_im_repository_builder.log"
}

run_clean() {
  run_step \
    "CLEAN GEONAMES" \
    "Rscript \"$SCRIPTS_DIR/clean_geonames.R\"" \
    "$LOGS_DIR/03_clean_geonames.log"
}

echo "============================================================"
echo "RUNNING AFRO IM AUTOMATED PIPELINE"
echo "MODE: $MODE"
echo "============================================================"

case "$MODE" in
  full)
    run_fetch
    run_process
    run_clean
    ;;
  fetch)
    run_fetch
    ;;
  process)
    run_process
    ;;
  clean)
    run_clean
    ;;
  fetch_process)
    run_fetch
    run_process
    ;;
  process_clean)
    run_process
    run_clean
    ;;
  *)
    echo "Invalid mode: $MODE"
    echo "Allowed modes: full, fetch, process, clean, fetch_process, process_clean"
    exit 1
    ;;
esac

echo "============================================================"
echo "AFRO IM PIPELINE COMPLETED SUCCESSFULLY"
echo "Outputs: $FINAL_DIR"
echo "Logs: $LOGS_DIR"
echo "============================================================"
