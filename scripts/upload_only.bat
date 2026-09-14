@echo off
echo ============================================================
echo SHAREPOINT UPLOAD ONLY
echo ============================================================
echo.
cd /d C:\Users\TOURE\Documents\im_workflow
echo Uploading files to SharePoint...
echo.
Rscript scripts/run_workflow.R --upload-only
echo.
if %errorlevel% equ 0 (
    echo ============================================================
    echo UPLOAD COMPLETED SUCCESSFULLY
    echo ============================================================
) else (
    echo ============================================================
    echo UPLOAD FAILED - Check errors above
    echo ============================================================
)
pause