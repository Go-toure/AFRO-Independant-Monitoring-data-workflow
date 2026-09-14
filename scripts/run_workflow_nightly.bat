@echo off
:: ============================================================
:: NIGHTLY IM WORKFLOW RUNNER (unattended, Mon-Fri)
:: ============================================================
:: This is the file Windows Task Scheduler runs every night -- you should
:: not normally need to double-click this yourself (use run_workflow.bat
:: for that, which shows live output in a window).
::
:: What it does:
::   1) Runs the full pipeline via run_workflow.R, logging everything to
::      logs\nightly_run.log (in addition to run_workflow.R's own
::      logs\workflow_<date>.log).
::   2) If Rscript exits with an error AND run_workflow.R did not already
::      send its own failure email (see send_failure_alert() inside
::      run_workflow.R), sends a generic fallback alert here instead --
::      this catches a crash severe enough that run_workflow.R never
::      reached its own alert code (e.g. a missing R package at startup,
::      or Rscript failing to launch at all).
::
:: One-time setup: run setup_nightly_schedule.bat once to register this
:: file with Windows Task Scheduler for 11:00 PM, Monday-Friday. See that
:: file for what to check afterward (sleep/wake behavior, email setup).

set "IM_WORKFLOW_HOME=C:\Users\TOURE\Documents\im_workflow"
set "SCRIPTS_DIR=%IM_WORKFLOW_HOME%\scripts"
set "LOGS_DIR=%IM_WORKFLOW_HOME%\logs"
set "ALERT_MARKER=%LOGS_DIR%\last_alert_sent.flag"
set "NIGHTLY_LOG=%LOGS_DIR%\nightly_run.log"

if not exist "%LOGS_DIR%" mkdir "%LOGS_DIR%"

echo ============================================================ >> "%NIGHTLY_LOG%"
echo Nightly run started: %DATE% %TIME% >> "%NIGHTLY_LOG%"

cd /d "%IM_WORKFLOW_HOME%"
Rscript "%SCRIPTS_DIR%\run_workflow.R" >> "%NIGHTLY_LOG%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"

echo Nightly run finished: %DATE% %TIME% (exit code %EXIT_CODE%) >> "%NIGHTLY_LOG%"

if not "%EXIT_CODE%"=="0" (
    if not exist "%ALERT_MARKER%" (
        echo Rscript exited with an error and did not send its own alert - sending fallback alert. >> "%NIGHTLY_LOG%"
        python "%SCRIPTS_DIR%\send_failure_alert.py" --base-dir "%IM_WORKFLOW_HOME%" --subject "[IM Workflow] Nightly run FAILED (unreported error)" --body "The nightly run exited with code %EXIT_CODE% and did not report a specific reason - it may have crashed before reaching a normal failure point (e.g. a missing R package, or Rscript failing to start). Check %NIGHTLY_LOG% and today's logs\workflow_*.log for details."
    ) else (
        echo Rscript exited with an error but already sent its own alert - skipping the fallback alert. >> "%NIGHTLY_LOG%"
    )
)
