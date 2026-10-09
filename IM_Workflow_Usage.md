# AFRO IM Workflow — Usage Guide

One place for every command used to run, test, share and maintain the workflow.
Built from the scripts' real argument parsing (not from memory); last updated 2026-10-09.

---

## 0. Before you start

**Repository folder (run everything from here, in PowerShell):**

```powershell
cd C:\Users\TOURE\Documents\Gith_repositories\AFRO-Independant-Monitoring-data-workflow
```

- `Rscript` and `python` commands are identical in PowerShell, Command Prompt and Git Bash. Only the `cd` line
  differs (Git Bash: `cd /c/Users/TOURE/Documents/Gith_repositories/AFRO-Independant-Monitoring-data-workflow`).
- The scripts find the workflow folder themselves (they look for `scripts/run_workflow.R` upward from where you
  are). To force a location: `setx IM_WORKFLOW_HOME "D:/new/path"` (then open a new terminal).
- On Linux (Posit Connect Cloud) the command is `python3`; locally on Windows it is `python`.

**Secrets** live in `config/secrets.env` (git-ignored; template: `config/secrets.env.example`). Nothing needs to be
passed on the command line for authentication.

| Variable | Used for |
|---|---|
| `ONA_API_TOKEN` | Fetching form data (ONA) |
| `SHAREPOINT_TENANT_ID`, `SHAREPOINT_CLIENT_ID`, `SHAREPOINT_CLIENT_SECRET` | SharePoint read/write (Microsoft Graph) |
| `GPEI_API_TOKEN` | Refreshing the campaign calendar (`lookup.xlsx`) |
| `ANTHROPIC_API_KEY` | AI assistant in the dashboard |
| `ALERT_EMAIL_FROM`, `ALERT_EMAIL_TO`, `ALERT_EMAIL_APP_PASSWORD`, `ALERT_SMTP_HOST`, `ALERT_SMTP_PORT` | Failure alert e-mails |

---

## 1. Quick reference

| I want to… | Command |
|---|---|
| Run the whole pipeline | `Rscript scripts\run_workflow.R` |
| Refresh data, no reports | `Rscript scripts\run_workflow.R --skip-reports` |
| Reports only (data untouched) | `Rscript scripts\run_workflow.R --skip-lookup-refresh --skip-fetch --skip-build --skip-clean --skip-upload` |
| Push existing files to SharePoint | `Rscript scripts\run_workflow.R --upload-only` |
| Open the dashboard locally | `Rscript -e "shiny::runApp('shiny_app', launch.browser=TRUE)"` |
| Create the country access codes | `python scripts\generate_access_codes.py --regenerate` |
| Change one country's code | `python scripts\generate_access_codes.py --rotate NGA` |
| Publish a change to the live app | `git add <files>` → `git commit -m "…"` → `git push` |

---

## 2. The full pipeline — `scripts/run_workflow.R`

Steps, in order: **0** refresh campaign calendar → **1** fetch data → **2** build repository →
**3** clean geonames → **4** reports (intelligence engine + advocacy report + deck) → **5** upload to SharePoint.

```powershell
Rscript scripts\run_workflow.R
```

### Flags (combine freely)

| Flag | Effect |
|---|---|
| `--skip-lookup-refresh` | Skip step 0 (keep the current `lookup.xlsx`) |
| `--skip-fetch` | Skip step 1; reuse the raw data already on disk |
| `--force-fetch` | Force a full re-fetch of every form |
| `--skip-build` | Skip step 2 (repository build) |
| `--skip-clean` | Skip step 3 (geonames cleaning) |
| `--skip-reports` | Skip step 4 (engine + report + deck run together; they can't be skipped one by one) |
| `--skip-upload` | Skip step 5 (SharePoint upload) |
| `--force-upload` | Upload even if step 3 failed this run (pushes the previous, possibly stale, final file) |
| `--upload-only` | Only run the SharePoint upload, then exit |

### Common recipes

```powershell
# Full run
Rscript scripts\run_workflow.R

# Reuse the raw data already downloaded
Rscript scripts\run_workflow.R --skip-fetch

# Fast refresh, no reports, no calendar refresh
Rscript scripts\run_workflow.R --skip-lookup-refresh --skip-reports

# Rebuild + clean from existing raw data, nothing else
Rscript scripts\run_workflow.R --skip-lookup-refresh --skip-fetch --skip-reports --skip-upload

# Regenerate the reports only
Rscript scripts\run_workflow.R --skip-lookup-refresh --skip-fetch --skip-build --skip-clean --skip-upload

# Upload what is already in data\final to SharePoint
Rscript scripts\run_workflow.R --upload-only

# Full re-fetch from the source
Rscript scripts\run_workflow.R --force-fetch

# The clean step failed earlier; push the previous file anyway
Rscript scripts\run_workflow.R --skip-fetch --force-upload
```

Where to look afterwards: `data\final\` (repository and cleaned files), `outputs\` (reports, deck, dashboards),
`logs\` (`workflow_*.log`, `run_history.csv`, `fetch_form_history.csv`).

---

## 3. Individual R scripts (debug one step on its own)

None take flags of their own; they process whatever is currently in `data\`.

```powershell
Rscript scripts\regional_im_repository_builder.R        # step 2
Rscript scripts\clean_geonames.R                        # step 3
Rscript scripts\afro_im_intilligence_analysis_engine.R  # step 4a (must run before 4b)
Rscript scripts\AFRO_Advocacy_Intelligence_Report.R     # step 4b
Rscript scripts\afro_region_im_deck_generation.R        # step 4c
Rscript scripts\generate_reports_and_deck.R             # 4b + 4c together (what the dashboard button runs)
```

### Scoping the reports (optional environment variables)

```powershell
# One country / several countries, last 6 months (PowerShell syntax; applies to this window only)
$env:AI_REPORT_COUNTRIES = "NIGERIA,GHANA"
$env:AI_REPORT_MONTHS    = "6"
Rscript scripts\generate_reports_and_deck.R
Remove-Item Env:AI_REPORT_COUNTRIES, Env:AI_REPORT_MONTHS      # back to the full region, 12 months
```

---

## 4. Python scripts

### `Fetch_im_data.py` — fetch forms from ONA

```powershell
python scripts\Fetch_im_data.py                        # normal incremental fetch
python scripts\Fetch_im_data.py --test                 # test the ONA connection only
python scripts\Fetch_im_data.py --form-ids 8587,7178   # only these forms
python scripts\Fetch_im_data.py --force-full           # full re-download, overwrite existing files
python scripts\Fetch_im_data.py --full-refresh-days 14 # a form not fully re-fetched for 14 days gets a full fetch (default 30)
python scripts\Fetch_im_data.py --page-size 5000       # records per API page (default 10000)
python scripts\Fetch_im_data.py --config path\to\config.yaml
python scripts\Fetch_im_data.py --base-dir D:\other\workflow
```

### `upload_to_sharepoint.py` — publish results to SharePoint

```powershell
python scripts\upload_to_sharepoint.py --test                   # test the connection only
python scripts\upload_to_sharepoint.py --check                  # list which local files exist, upload nothing
python scripts\upload_to_sharepoint.py --all                    # upload everything (default)
python scripts\upload_to_sharepoint.py --folder "Some/Other/Folder"   # override the target folder
python scripts\upload_to_sharepoint.py --base-dir D:\other\workflow
```

(`--file` is accepted but not implemented yet.)

### `fetch_sharepoint_csvs.py` — download raw CSVs from SharePoint (and make .xlsx copies)

```powershell
python scripts\fetch_sharepoint_csvs.py                             # every CSV in raw_state
python scripts\fetch_sharepoint_csvs.py --match 4498                # only files whose name contains 4498
python scripts\fetch_sharepoint_csvs.py --folder "7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/raw_state/partitions/4498"
python scripts\fetch_sharepoint_csvs.py --output-dir "D:\exports" --skip-xlsx
python scripts\fetch_sharepoint_csvs.py --xlsx-max-mb 150           # keep one .xlsx per file up to 150 MB (default 75; larger = one per year)
```

### Campaign calendar / lookup refresh

```powershell
python scripts\refresh_preparedness_lookup.py            # refresh data\lookup\lookup.xlsx from the GPEI API
python scripts\refresh_preparedness_lookup.py --debug    # also save a fetch summary to data\lookup\refresh_debug\
python scripts\refresh_scope_lookup.py                   # refresh the scope lookup
python scripts\refresh_scope_lookup.py --discover        # inspect the API's real shape first
python scripts\refresh_scope_lookup.py --all-statuses    # don't filter to Finished / In Progress
python scripts\refresh_scope_lookup.py --debug
```

### SharePoint housekeeping

```powershell
python scripts\sharepoint_bin_report.py                  # read-only: measure the recycle bin (deletes nothing)

python scripts\sharepoint_recyclebin_purge.py            # DRY RUN: shows what it would purge
python scripts\sharepoint_recyclebin_purge.py --path-contains "Cloud-Independant-Monitoring/raw_state" --older-than-days 60
python scripts\sharepoint_recyclebin_purge.py --execute                      # really purges (asks to confirm)
python scripts\sharepoint_recyclebin_purge.py --execute --yes --older-than-days 30   # no confirmation prompt
```

`sharepoint_recyclebin_purge.py` is destructive with `--execute`; always run the dry run first. Extra options:
`--stage first|second|all`, `--exclude-path`, `--max-items`, `--log-dir`.

### Failure alert e-mail (normally called by the nightly job)

```powershell
python scripts\send_failure_alert.py --subject "Test alert" --body "This is a test"
python scripts\send_failure_alert.py --subject "Run failed" --body-file logs\alert.txt
```

---

## 5. The dashboard

### Run it on your PC

```powershell
Rscript -e "shiny::runApp('shiny_app', launch.browser=TRUE)"
```

Or double-click `run_dashboard.bat`.

On Windows with **no access-code secrets set**, the dashboard opens as admin (no sign-in), as before.
With `IM_ADMIN_CODES` / `IM_COUNTRY_CODES` set (even locally), a sign-in is required.

### Environment variables for the shared (Connect Cloud) dashboard

| Variable | Meaning |
|---|---|
| `IM_ADMIN_CODES` | Regional-office codes, separated by `;` |
| `IM_COUNTRY_CODES` | `KEY=CODE` pairs separated by `;` (e.g. `AGO=AGO-2026-Z6X2MQ;NGA=…`) |
| `IM_ACCESS_MODE` | `open` = no sign-in (only honoured when no codes are set; never use on a shared server) |
| `IM_COUNTRY_MAX_RUNS` | Country "Fetch & clean" runs allowed at once (default 2) |
| `IM_COUNTRY_RUNS_DIR` | Where country runs keep their temporary folders (default: system temp) |

Without codes on a Linux server the app refuses everyone ("Access has not been configured").

### Country "My data" run, from the command line (debugging only)

```powershell
mkdir C:\Temp\country_test
Rscript scripts\run_country_workflow.R --home C:\Temp\country_test --form-id 10267
```

`--home` must be an empty scratch folder (never the repository). Nothing is written to SharePoint in this mode.

---

## 6. Access codes — `scripts/generate_access_codes.py`

The master list is `config\access_codes.private.csv` (git-ignored, **back it up**, send each country only its own code).

```powershell
python scripts\generate_access_codes.py                      # keep existing codes, add any missing country
python scripts\generate_access_codes.py --regenerate         # replace EVERY code
python scripts\generate_access_codes.py --rotate NGA         # new code for Nigeria only
python scripts\generate_access_codes.py --rotate NGA,AGO,GHA # several countries
python scripts\generate_access_codes.py --rotate ADMIN       # new admin codes
python scripts\generate_access_codes.py --style random       # hard 12-character codes (default style: AGO-2026-K7M2QX)
python scripts\generate_access_codes.py --style words        # three-word codes (lake-tiger-moon-47)
python scripts\generate_access_codes.py --admin 3            # create 3 admin codes (default 2)
python scripts\generate_access_codes.py --admin-code "YOUR-OWN-LONG-CODE-2026-X7K2"   # set the admin code yourself (12+ chars; keep a random tail)
```

After any change: copy the two printed values into **Connect Cloud → app → Settings → Variables**
(`IM_ADMIN_CODES`, `IM_COUNTRY_CODES`; replace the whole value), save, then **restart the content**.
The old code stops working after the restart. Codes are case-sensitive.

---

## 7. Publish a change to the live app (Posit Connect Cloud)

Connect Cloud redeploys automatically when `main` changes.

```powershell
git status
git add shiny_app/app.R scripts/run_workflow.R          # list the exact files you changed
git commit -m "Describe the change"
git push
```

- Never commit `config/secrets.env` or `config/access_codes.private.csv` (both are git-ignored).
- `git add .` also picks up backup files (`*.bak`) and scratch patches; prefer naming files.
- Check the result at the app's Connect Cloud page (logs are under the app's log icon).

---

## 8. Tests

Run from the repository folder. (R packages needed: shiny, testthat, bslib, shinyjs, processx, jsonlite,
arrow, readr, writexl, readxl, httr2.)

```powershell
# Access control + sign-in
Rscript tests\test_access_control.R
Rscript tests\test_access_session.R
Rscript tests\test_app_guards.R

# Raw-download request validation / path guard
Rscript tests\test_rawdl_guard.R

# Country "My data" runs
Rscript tests\test_country_run_app.R
python tests\test_country_run.py

# Read-only SharePoint mode
python tests\test_sharepoint_readonly.py
Rscript tests\test_sharepoint_readonly_r.R
```

Each prints "ok"/"Test passed" lines and stops with an error on the first failure.

---

## 9. Scheduled nightly run (Windows)

```powershell
scripts\setup_nightly_schedule.bat      # one-time: creates "IM Workflow Nightly" (Mon–Fri, 23:00)
scripts\run_workflow_nightly.bat        # what the schedule runs (writes logs\nightly_run.log, e-mails on failure)
schtasks /run /tn "IM Workflow Nightly" # run it now
schtasks /query /tn "IM Workflow Nightly"   # check it
schtasks /delete /tn "IM Workflow Nightly" /f   # remove it
```

The laptop must be on and you must be logged in at 23:00. Fill the `ALERT_*` values in `config\secrets.env`
to receive failure e-mails.

Double-click launchers: `scripts\run_workflow.bat` (full pipeline), `scripts\upload_only.bat` (upload only),
`run_dashboard.bat` (dashboard).

---

## 10. Troubleshooting

| Symptom | Try |
|---|---|
| `python` not recognised | `py scripts\<name>.py` |
| A command seems to hang | A Windows dialog may be open behind the terminal window |
| "Access has not been configured" on the live app | Set `IM_ADMIN_CODES` / `IM_COUNTRY_CODES` in Variables and restart the content |
| A country says "code not recognised" | Codes are case-sensitive and written exactly as in `access_codes.private.csv`; rotate if in doubt |
| Upload says credentials missing | Check `config\secrets.env` has the three `SHAREPOINT_*` values |
| Reports/step failed | Open the newest `logs\workflow_*.log`; `logs\run_history.csv` has one row per run |
| Country run says the server is busy | Wait a few minutes, or raise `IM_COUNTRY_MAX_RUNS` |
