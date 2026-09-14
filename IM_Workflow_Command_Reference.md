# IM Workflow — Command Reference

Every command below assumes you're either in `C:\Users\TOURE\Documents\im_workflow`
(for the `.bat` launchers) or in `C:\Users\TOURE\Documents\im_workflow\scripts`
(for the `Rscript` / `python` commands — otherwise use the full path,
e.g. `Rscript C:\Users\TOURE\Documents\im_workflow\scripts\run_workflow.R`).

This list was built by reading the actual argument-parsing code in each
script, not from old notes, so it reflects exactly what each flag does today.

---

## 1. Full pipeline — `run_workflow.R`

Base command (all 5 steps: Fetch → Build Repository → Clean Geonames →
Upload SharePoint → Reports):

```
Rscript run_workflow.R
```

### Flags (combine freely)

| Flag | Effect |
|---|---|
| `--skip-fetch` | Skip Step 1, reuse whatever raw data is already on disk |
| `--force-fetch` | Force a full re-fetch (only matters if fetch isn't skipped) |
| `--skip-build` | Skip Step 2 (repository build) |
| `--skip-clean` | Skip Step 3 (geonames cleaning) |
| `--skip-upload` | Skip Step 4 (SharePoint upload) |
| `--force-upload` | Upload anyway even if Step 3 failed this run (pushes the previous, stale final file) |
| `--skip-reports` | Skip Step 5 — Intelligence Engine + Advocacy Report + Deck run together, can't skip just one of the three |
| `--upload-only` | Standalone mode: skips everything else, runs just the SharePoint upload, then exits |

### Common combinations

```
# Full run
Rscript run_workflow.R

# Reuse today's raw data, skip re-fetching
Rscript run_workflow.R --skip-fetch

# Fast data refresh, no reports
Rscript run_workflow.R --skip-fetch --skip-reports

# Regenerate reports only — data untouched
Rscript run_workflow.R --skip-fetch --skip-build --skip-clean --skip-upload

# Push existing final files to SharePoint, nothing else
Rscript run_workflow.R --upload-only

# Force a full re-fetch from source
Rscript run_workflow.R --force-fetch

# Clean step failed earlier — push the stale file anyway
Rscript run_workflow.R --skip-fetch --force-upload
```

---

## 2. Individual scripts, run directly

Useful for debugging one step in isolation. None of the five R scripts
below take command-line flags — they always process whatever is
currently in `data/`. The Intelligence Engine must run before the
Advocacy Report (it reads the engine's output tables) — `run_workflow.R`
already handles that order for you.

```
Rscript regional_im_repository_builder.R
Rscript clean_geonames.R
Rscript afro_im_intilligence_analysis_engine.R
Rscript AFRO_Advocacy_Intelligence_Report.R
Rscript afro_region_im_deck_generation.R
```

### `Fetch_im_data.py`

```
python Fetch_im_data.py                      # normal incremental fetch
python Fetch_im_data.py --force-full         # overwrite existing Parquet files
python Fetch_im_data.py --test               # test the ONA API connection only
python Fetch_im_data.py --form-ids 8587,7178 # fetch only specific form IDs
python Fetch_im_data.py --page-size 5000     # override API page size (default 10000)
python Fetch_im_data.py --config path\to\config.yaml   # optional form-ID config file
```

### `upload_to_sharepoint.py`

```
python upload_to_sharepoint.py --test            # test SharePoint connection only
python upload_to_sharepoint.py --check            # list which local files exist, don't upload
python upload_to_sharepoint.py --all              # upload everything (default if no flag given)
python upload_to_sharepoint.py --folder "Some/Other/Folder"   # override the target SharePoint folder
```
(`--file` is accepted by the parser but not implemented yet — it just prints a message.)

---

## 3. Dashboard

```
Rscript -e "shiny::runApp('C:/Users/TOURE/Documents/im_workflow/shiny_app', launch.browser=TRUE)"
```

---

## 4. Double-click launchers (`.bat` files, no terminal needed)

| File | What it runs |
|---|---|
| `run_workflow.bat` | Full pipeline — same as `Rscript run_workflow.R` |
| `upload_only.bat` | SharePoint upload only — same as `Rscript run_workflow.R --upload-only` |
| `run_dashboard.bat` | Opens the Shiny dashboard in your browser |

---

## Credentials note

`Fetch_im_data.py` and `upload_to_sharepoint.py` both read their secrets
(`ONA_API_TOKEN`, `SHAREPOINT_TENANT_ID`, `SHAREPOINT_CLIENT_ID`,
`SHAREPOINT_CLIENT_SECRET`) from `config/secrets.env` automatically. You
don't need to pass anything extra on the command line for auth — just make
sure `config/secrets.env` has real values (see `config/secrets.env.example`).
