@echo off
echo ============================================================
echo IM WORKFLOW EXECUTION
echo ============================================================

cd C:\Users\TOURE\Documents\im_workflow

echo.
echo Running the full IM workflow (fetch, build, clean, upload,
echo intelligence engine, reports)...
echo See run_the_im_workflow.txt for flags (--skip-fetch,
echo --skip-upload, --upload-only, --skip-reports, etc.)
echo.
Rscript scripts\run_workflow.R

echo.
echo ============================================================
echo WORKFLOW COMPLETED
echo ============================================================
echo Check outputs in: data\final\ and outputs\
echo Check logs in: logs\
echo ============================================================

pause
