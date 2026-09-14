@echo off
:: ============================================================
:: ONE-TIME SETUP: registers the nightly IM workflow run with
:: Windows Task Scheduler (11:00 PM, Monday-Friday).
:: ============================================================
:: Run this file once (double-click it). You do not need to run it again
:: unless you want to change the schedule, or you move the project to a
:: different folder (in which case also update IM_WORKFLOW_HOME at the top
:: of run_workflow_nightly.bat).
::
:: This registers the task to run as YOU, only while you are logged in
:: (no Windows password is stored or needed for this). That means:
::   - Locking your screen at night is fine, the task still runs.
::   - Fully logging off or shutting down the laptop means it will NOT
::     run. See the notes printed below for what to check if you want it
::     to survive a sleeping laptop too.

schtasks /create /tn "IM Workflow Nightly" /tr "\"C:\Users\TOURE\Documents\im_workflow\scripts\run_workflow_nightly.bat\"" /sc weekly /d MON,TUE,WED,THU,FRI /st 23:00 /f

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================================
    echo  Scheduled: IM Workflow Nightly, 11:00 PM, Monday-Friday
    echo ============================================================
    echo.
    echo Before this actually helps you overnight, please check:
    echo.
    echo   1. EMAIL ALERTS - open config\secrets.env and fill in
    echo      ALERT_EMAIL_FROM, ALERT_EMAIL_TO and ALERT_EMAIL_APP_PASSWORD
    echo      (see config\secrets.env.example for what each one means and
    echo      how to get a Gmail App Password). Without these, a failed
    echo      run will NOT email you - the pipeline itself is unaffected
    echo      either way, you just will not be notified until you next
    echo      open the dashboard.
    echo.
    echo   2. SLEEP - this task only runs while the laptop is powered on
    echo      and you are logged in (screen can be locked). If the laptop
    echo      sleeps or is shut down at 11 PM, it will NOT run. Either
    echo      change your Windows power settings so it stays awake in the
    echo      evening, or open Task Scheduler yourself (Win+R, type:
    echo      taskschd.msc), find "IM Workflow Nightly" under Task
    echo      Scheduler Library, open its Properties, go to the
    echo      Conditions tab, and enable "Wake the computer to run this
    echo      task" - this is not something this script can safely turn
    echo      on for you automatically.
    echo.
    echo   3. FIRST RUN - the task will not actually run until tonight
    echo      at 11 PM. To check the whole thing works without waiting,
    echo      right-click "IM Workflow Nightly" in Task Scheduler and
    echo      choose Run - then check logs\nightly_run.log afterward.
    echo.
    echo To change the time or days later, just re-run this file with a
    echo different /st or /d value, or edit the task directly in Task
    echo Scheduler.
) else (
    echo.
    echo Something went wrong creating the scheduled task. Try running
    echo this file as Administrator (right-click it, then "Run as
    echo administrator"^).
)

pause
