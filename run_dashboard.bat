@echo off
:: AFRO IM Dashboard Launcher
:: Double-click this file to open the dashboard in your browser

echo ============================================================
echo  AFRO IM Dashboard
echo  WHO AFRO Independent Monitoring
echo ============================================================
echo.

:: Check if Rscript is available
where Rscript >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Rscript not found. Please install R from https://cran.r-project.org/
    pause
    exit /b 1
)

echo Starting dashboard... (a browser window will open automatically)
echo To stop the dashboard, close this window.
echo.

Rscript -e "shiny::runApp('C:/Users/TOURE/Documents/im_workflow/shiny_app', launch.browser=TRUE)"

pause
