# fetch_sharepoint_csvs.py
"""
Standalone, on-demand utility: pull every CSV currently sitting in the
SharePoint raw_state folder down to this PC, saving each one both as-is
(.csv) and converted to .xlsx, so someone can open the data directly in
Excel without touching the pipeline or Posit Connect Cloud at all. A CSV
too large for one .xlsx sheet is split into one .xlsx per calendar year
instead of being skipped -- see _write_xlsx_year_partitions()'s docstring.

This is deliberately separate from Fetch_im_data.py's own SharePoint sync
(sync_missing_raw_from_sharepoint() / upload_raw_to_sharepoint() there) --
those exist to keep the *pipeline's own* working state in sync across
ephemeral Connect Cloud runs. This script has a different job: a manual,
read-only "give me a local copy I can look at" export, run whenever
someone wants one, targeting a plain folder on this machine rather than
data/raw.

Reuses the same Graph app-only client-credentials helpers as the rest of
the workflow (_sharepoint_client.py) and the same config/secrets.env
loading (_env_loader.py) -- no new credentials or setup needed if the
pipeline already works on this machine.

Usage (from the repo's scripts/ folder, or anywhere with python on PATH):

    python fetch_sharepoint_csvs.py
    python fetch_sharepoint_csvs.py --match 4498
    python fetch_sharepoint_csvs.py --folder "7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/raw_state/partitions/4498"
    python fetch_sharepoint_csvs.py --output-dir "D:/exports" --skip-xlsx

Run `python fetch_sharepoint_csvs.py --help` for the full option list.
"""

import os
import sys
import time
import argparse
from pathlib import Path
from typing import List, Dict


# ============================================================
# WINDOWS CONSOLE ENCODING FIX (same as Fetch_im_data.py)
# ============================================================

if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


# ============================================================
# PATHS / CREDENTIALS (same conventions as Fetch_im_data.py)
# ============================================================

def _cli_base_dir():
    argv = sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--base-dir" and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith("--base-dir="):
            return a.split("=", 1)[1]
    return None


BASE_DIR = Path(_cli_base_dir() or os.environ.get("IM_WORKFLOW_HOME", r"C:/Users/TOURE/Documents/im_workflow"))

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _env_loader import load_secrets_env
load_secrets_env(BASE_DIR)

import _sharepoint_client as sp

# Same raw_state root every other script in this workflow already talks to.
SP_RAW_FOLDER = "7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/raw_state"

# The user's requested default drop location. Only used as a *default* --
# --output-dir always overrides it, and on a non-Windows machine (e.g. a
# quick dry run here in this sandbox) there is no sensible default at all,
# so it's left unset there and the flag becomes required.
_DEFAULT_OUTPUT_DIR = r"C:\Users\TOURE\Documents\SharePoint_im_raw_data" if sys.platform == "win32" else None


def _human_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024:
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}TB"


def _list_csvs(token: str, drive_id: str, folder: str, match: str) -> List[Dict]:
    """Every item in `folder` whose name ends in .csv, optionally narrowed
    to names containing `match` (case-insensitive substring, e.g. a form
    id like "4498"). Does not recurse into subfolders -- point --folder at
    a partitions/{form_id} subfolder directly if that's what's wanted."""
    items = sp.list_folder(token, drive_id, folder)
    csvs = [it for it in items if it.get("name", "").lower().endswith(".csv")]
    if match:
        needle = match.lower()
        csvs = [it for it in csvs if needle in it["name"].lower()]
    return sorted(csvs, key=lambda it: it["name"])


def _download_with_retry(token: str, drive_id: str, remote_path: str, local_path: Path,
                          max_attempts: int = 3, delay: int = 5) -> bool:
    """sp.download_file(), retrying a few times on a transient *local*
    file-lock error. sp.download_file() only guards against network-side
    failures (it catches requests.exceptions.RequestException internally);
    the open(local_path, "wb") call inside it is not wrapped there, so a
    PermissionError/OSError from the local filesystem -- OneDrive syncing a
    newly-created large file, an antivirus scan, or a leftover process from
    a previous run still holding the file open are all common causes on
    Windows, and all usually clear within a few seconds -- would otherwise
    propagate straight out and crash the whole batch on one file. Returns
    False (never raises) after exhausting retries, exactly like every other
    function in _sharepoint_client.py."""
    last_exc: Exception = None
    for attempt in range(1, max_attempts + 1):
        try:
            return sp.download_file(token, drive_id, remote_path, local_path)
        except (PermissionError, OSError) as e:
            last_exc = e
            if attempt < max_attempts:
                print(f"    Local file busy ({type(e).__name__}) -- retrying in {delay}s "
                      f"(attempt {attempt}/{max_attempts - 1})...", flush=True)
                time.sleep(delay)
    print(f"    FAILED: could not write {local_path.name} locally after {max_attempts} attempts "
          f"({type(last_exc).__name__}: {last_exc}). This usually means another program has it "
          f"open -- OneDrive syncing it, an antivirus scan, a leftover python process from an "
          f"earlier run, or the file open in Excel. Close whatever has it open and re-run.",
          flush=True)
    return False


# Excel's hard per-sheet row limit (including the header row) -- same
# constant Fetch_im_data.py's own CSV-export code is built around
# (_CSV_EXPORT_MAX_ROWS there). One data row less, since the header takes
# the first slot.
_EXCEL_ROW_LIMIT = 1_048_575


def _submission_year(value) -> str:
    """Extract a 4-digit calendar-year string from a _submission_time
    value. Copied verbatim (same logic, same "0000" fallback) from
    Fetch_im_data.py's own _submission_year(), which is what the pipeline
    uses to decide a record's year partition on the SharePoint/Parquet
    side -- reusing it here means a year boundary drawn by this script
    always lines up with the pipeline's own, instead of quietly using a
    different rule. ONA/WHONgHub submission timestamps are ISO-8601
    strings (e.g. "2024-05-01T12:34:56"), so the first 4 characters are
    the year -- no full datetime parse needed."""
    if value is None:
        return "0000"
    text = str(value).strip()
    if len(text) >= 4 and text[:4].isdigit():
        return text[:4]
    return "0000"


# How often the row-streaming loop below prints a progress line. A wide
# form (hundreds of columns) can genuinely take several minutes to write
# out even though it's memory-safe -- writing tens of millions of
# individual cells is just real work -- and with zero feedback that's
# indistinguishable from a hang. Benchmarked at ~300 rows/sec for a
# 629-column form, so 25,000 rows is roughly a print every 1-2 minutes:
# frequent enough to prove it's alive, not so frequent it spams the console.
_XLSX_PROGRESS_EVERY = 25_000


def _write_xlsx_year_partitions(csv_path: Path, output_dir: Path, base_name: str) -> Dict[str, object]:
    """Split csv_path into one {base_name}_{year}.xlsx per calendar year in
    its _submission_time column -- the .xlsx counterpart to how
    Fetch_im_data.py already splits this same form's Parquet/CSV into
    yearly partitions once it's too big for one file (see that script's
    _export_csv_year_partitions()). Used here for a CSV too large to
    safely become one .xlsx sheet: each year's slice is a fraction of the
    total, so it both fits comfortably under Excel's row limit and avoids
    ever holding the whole file in memory at once the way loading it into
    a single pandas DataFrame would.

    Streams csv_path with Python's own csv module one row at a time --
    never via pandas -- and writes each year's slice straight to its own
    file as it goes, via xlsxwriter's constant_memory mode when xlsxwriter
    is installed (~40% faster than openpyxl in this script's own
    benchmarking on a wide, ~630-column form: xlsxwriter's write_row()
    writes a whole row in one call instead of openpyxl's per-cell object
    creation), falling back to openpyxl's write-only mode otherwise so this
    still works with just the dependencies main() already requires. Either
    way, peak memory stays proportional to one row, not the file. Field
    values are written exactly as read from the CSV (plain strings, no
    dtype inference), which also means ids/phone numbers/leading zeros
    survive into the .xlsx unchanged, same as the small-file path in
    main() gets via dtype=str there.

    A wide form is genuinely slow to write this way -- there is no way
    around producing every cell -- so a progress line is printed every
    _XLSX_PROGRESS_EVERY rows (with elapsed time and rows/sec) purely so a
    long run is visibly alive instead of looking hung with zero output.

    Returns {"row_count": int, "skipped_no_column": bool, "engine": str,
    "elapsed_seconds": float, "years": {year_str: Path or None}} -- a year
    maps to None if its own row count still exceeds Excel's per-sheet
    limit (should not happen in practice; see Fetch_im_data.py's own
    reasoning that new submissions almost always land in the current
    year) or if writing that year's file failed. Never raises -- any
    failure here must not affect the .csv, which is already saved by the
    time this is called."""
    import csv as csv_mod

    try:
        import xlsxwriter
        engine = "xlsxwriter"
    except ImportError:
        xlsxwriter = None
        try:
            from openpyxl import Workbook
            engine = "openpyxl"
        except ImportError:
            return {"row_count": 0, "skipped_no_column": False, "engine": None,
                     "elapsed_seconds": 0.0, "years": {}, "no_engine": True}

    result: Dict[str, object] = {"row_count": 0, "skipped_no_column": False, "engine": engine, "years": {}}
    year_states: Dict[str, Dict] = {}
    start = time.time()

    try:
        with open(csv_path, "r", encoding="utf-8", newline="") as f:
            reader = csv_mod.reader(f)
            try:
                header = next(reader)
            except StopIteration:
                result["elapsed_seconds"] = time.time() - start
                return result  # empty file -- nothing to partition

            if "_submission_time" not in header:
                result["skipped_no_column"] = True
                result["elapsed_seconds"] = time.time() - start
                return result
            ts_idx = header.index("_submission_time")

            for row in reader:
                result["row_count"] += 1
                if result["row_count"] % _XLSX_PROGRESS_EVERY == 0:
                    elapsed = time.time() - start
                    rate = result["row_count"] / elapsed if elapsed > 0 else 0
                    print(f"      ...{result['row_count']:,} rows processed "
                          f"({rate:.0f} rows/sec, {elapsed:.0f}s elapsed)", flush=True)

                ts_value = row[ts_idx] if ts_idx < len(row) else None
                year = _submission_year(ts_value)

                state = year_states.get(year)
                if state is None:
                    tmp_path = output_dir / f"{base_name}_{year}.xlsx.tmp"
                    if engine == "xlsxwriter":
                        wb = xlsxwriter.Workbook(str(tmp_path), {"constant_memory": True})
                        ws = wb.add_worksheet()
                        ws.write_row(0, 0, header)
                    else:
                        wb = Workbook(write_only=True)
                        ws = wb.create_sheet()
                        ws.append(header)
                    state = {"wb": wb, "ws": ws, "rows": 0, "overflowed": False, "tmp_path": tmp_path}
                    year_states[year] = state

                if state["rows"] >= _EXCEL_ROW_LIMIT:
                    state["overflowed"] = True
                    continue

                if engine == "xlsxwriter":
                    state["ws"].write_row(state["rows"] + 1, 0, row)
                else:
                    state["ws"].append(row)
                state["rows"] += 1
    except Exception:
        # A read-side failure partway through (bad encoding, disk error, ...)
        # -- whatever years already got fully read are still worth writing
        # out below rather than losing everything.
        pass

    for year, state in sorted(year_states.items()):
        tmp_path = state["tmp_path"]
        final_path = output_dir / f"{base_name}_{year}.xlsx"
        try:
            if engine == "xlsxwriter":
                state["wb"].close()  # flushes/finalizes the file regardless of outcome below
            if state["overflowed"]:
                result["years"][year] = None
                continue
            if engine == "openpyxl":
                state["wb"].save(tmp_path)
            tmp_path.replace(final_path)
            result["years"][year] = final_path
        except Exception:
            result["years"][year] = None
        finally:
            try:
                tmp_path.unlink(missing_ok=True)
            except OSError:
                pass

    result["elapsed_seconds"] = time.time() - start
    return result

    return result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch CSV files from the SharePoint raw_state folder and save them "
                     "locally as both .csv and .xlsx."
    )
    parser.add_argument(
        "--folder", default=SP_RAW_FOLDER,
        help="SharePoint folder to list (relative to the library root). "
             f"Defaults to raw_state itself: {SP_RAW_FOLDER}",
    )
    parser.add_argument(
        "--output-dir", default=_DEFAULT_OUTPUT_DIR,
        help="Local folder to save into (created if missing)." +
             (f" Defaults to {_DEFAULT_OUTPUT_DIR}" if _DEFAULT_OUTPUT_DIR else " Required on this platform."),
    )
    parser.add_argument(
        "--match", default="",
        help='Only fetch CSVs whose filename contains this text, e.g. --match 4498. '
             "Leave unset to fetch every CSV in --folder.",
    )
    parser.add_argument(
        "--skip-xlsx", action="store_true",
        help="Only download the .csv files -- skip the .xlsx conversion.",
    )
    parser.add_argument(
        "--xlsx-max-mb", type=float, default=75.0,
        help="Above this many MB (default: 75), a CSV is split into one .xlsx per calendar year "
             "(by _submission_time) instead of one single-sheet .xlsx. Loading a huge CSV into "
             "pandas with dtype=str to write it back out as one .xlsx sheet can use several times "
             "the file's size in memory and has been seen to hang/crash the process on this "
             "workflow's largest forms -- the .csv itself is always saved either way. Raise this "
             "(or pass a very large number) to force a single-sheet .xlsx attempt instead.",
    )
    parser.add_argument("--base-dir", default=None, help=argparse.SUPPRESS)
    args = parser.parse_args()

    if not args.output_dir:
        parser.error("--output-dir is required on this platform (no Windows default available).")

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if not sp.credentials_available():
        print(
            "ERROR: SHAREPOINT_TENANT_ID / SHAREPOINT_CLIENT_ID / SHAREPOINT_CLIENT_SECRET "
            "are not set. Fill in config/secrets.env (see config/secrets.env.example) or set "
            "them as environment variables, same as the rest of the pipeline."
        )
        return 1

    print("Authenticating with SharePoint...", flush=True)
    token = sp.get_token()
    if not token:
        print("ERROR: Could not get a Graph access token -- check the SharePoint credentials.")
        return 1

    drive_id = sp.get_drive_id(token)
    if not drive_id:
        print("ERROR: Could not resolve the SharePoint document library.")
        return 1

    print(f"Listing CSVs in: {args.folder}" + (f"  (filter: '{args.match}')" if args.match else ""), flush=True)
    csvs = _list_csvs(token, drive_id, args.folder, args.match)

    if not csvs:
        print("No matching CSV files found.")
        return 0

    print(f"Found {len(csvs)} CSV file(s). Saving to: {output_dir}\n", flush=True)

    try:
        import pandas as pd
    except ImportError:
        pd = None
        if not args.skip_xlsx:
            print("WARNING: pandas is not installed -- .xlsx conversion will be skipped for every "
                  "file. Run: pip install pandas openpyxl\n")

    xlsx_max_bytes = args.xlsx_max_mb * 1024 * 1024

    downloaded, download_failed = 0, []
    converted, convert_failed, convert_skipped = 0, [], []
    xlsx_written = 0  # total individual .xlsx files written (a year-split source counts >1)

    for item in csvs:
        name = item["name"]
        size = item.get("size", 0)
        remote_path = f"{args.folder}/{name}"
        local_csv = output_dir / name
        local_xlsx = local_csv.with_suffix(".xlsx")

        # Everything for this one file is wrapped in a catch-all so an
        # unexpected error here (disk full, an odd filename, ...) skips to
        # the next file instead of taking down the whole batch -- matching
        # the never-raises contract every _sharepoint_client.py function
        # already follows.
        try:
            # A previous interrupted run's half-written xlsx (or the .tmp it
            # was staged under) must never be left sitting there looking
            # like a finished file -- clear both out before this file is
            # redone. Also clears any year-partition .xlsx files from a
            # previous run (e.g. {name}_2020.xlsx) -- which path this run
            # takes (single-sheet vs. year-split) depends on the file's
            # current size, so a stale file from the *other* path must not
            # survive alongside this run's fresh output.
            stem = local_csv.stem
            stale_paths = [local_xlsx, local_xlsx.with_suffix(".xlsx.tmp")]
            stale_paths.extend(output_dir.glob(f"{stem}_*.xlsx"))
            stale_paths.extend(output_dir.glob(f"{stem}_*.xlsx.tmp"))
            for stale in stale_paths:
                try:
                    stale.unlink(missing_ok=True)
                except OSError:
                    pass

            print(f"  {name}  ({_human_size(size)})", flush=True)
            ok = _download_with_retry(token, drive_id, remote_path, local_csv)
            if not ok:
                download_failed.append(name)
                continue
            downloaded += 1
            print(f"    saved -> {local_csv}", flush=True)

            if args.skip_xlsx or pd is None:
                continue

            # Check the size actually on disk (not the remote listing's
            # number) before ever loading it into pandas. dtype=str can
            # balloon a CSV to several times its file size in memory, and
            # openpyxl has no streaming write path for that -- on this
            # workflow's heaviest raw forms (hundreds of MB) that
            # combination has been seen to hang or get killed partway
            # through, leaving a broken 0-byte .xlsx behind. The .csv above
            # is already saved regardless of what happens here.
            try:
                local_size = local_csv.stat().st_size
            except OSError:
                local_size = size

            if local_size > xlsx_max_bytes:
                print(f"    {_human_size(local_size)} exceeds the {args.xlsx_max_mb:g}MB "
                      f"single-sheet limit -- splitting into one .xlsx per year instead. A wide "
                      f"form can genuinely take several minutes; progress prints every "
                      f"{_XLSX_PROGRESS_EVERY:,} rows so this doesn't look stuck.", flush=True)
                year_result = _write_xlsx_year_partitions(local_csv, output_dir, local_csv.stem)
                elapsed = year_result.get("elapsed_seconds", 0.0)
                if year_result.get("no_engine"):
                    print("    SKIPPED .xlsx: neither xlsxwriter nor openpyxl is installed. "
                          "Run: pip install xlsxwriter", flush=True)
                    convert_skipped.append(name)
                elif year_result["skipped_no_column"]:
                    print("    SKIPPED .xlsx: no _submission_time column to partition by year "
                          "-- .csv is saved, open that instead.", flush=True)
                    convert_skipped.append(name)
                elif not year_result["years"]:
                    print("    SKIPPED .xlsx: file has no data rows.", flush=True)
                    convert_skipped.append(name)
                else:
                    ok_years = {y: p for y, p in year_result["years"].items() if p}
                    bad_years = [y for y, p in year_result["years"].items() if not p]
                    for y, p in ok_years.items():
                        xlsx_written += 1
                        print(f"    saved -> {p}", flush=True)
                    if ok_years:
                        converted += 1
                    print(f"    ({year_result['row_count']:,} rows, {elapsed:.0f}s, "
                          f"engine={year_result['engine']})", flush=True)
                    if bad_years:
                        print(f"    WARNING: year(s) {', '.join(bad_years)} still exceed Excel's "
                              f"per-sheet row limit even split out on their own -- .csv is saved, "
                              f"open that instead for those years.", flush=True)
                        convert_failed.append(f"{name} ({', '.join(bad_years)})")
                continue

            tmp_xlsx = local_xlsx.with_suffix(".xlsx.tmp")
            try:
                # dtype=str + keep_default_na=False preserves the CSV's
                # exact text (ids, phone numbers, GPS strings, leading
                # zeros, ...) instead of letting pandas/Excel silently
                # reinterpret them as numbers -- this file is for someone
                # to read, not to compute on, so round-tripping the raw
                # values as-is matters more than inferred dtypes.
                df = pd.read_csv(local_csv, dtype=str, keep_default_na=False, low_memory=False)
                if len(df) > 1_048_575:  # Excel's row limit, header row aside
                    print(f"    SKIPPED .xlsx: {len(df):,} rows exceeds Excel's ~1,048,575-row "
                          f"limit -- .csv is saved, open that instead.", flush=True)
                    convert_skipped.append(name)
                    continue
                # Written to a .tmp path and only renamed into place on
                # success, so a crash or kill mid-write can never leave a
                # half-written file sitting at the real .xlsx name looking
                # like it finished.
                df.to_excel(tmp_xlsx, index=False, engine="openpyxl")
                tmp_xlsx.replace(local_xlsx)
                converted += 1
                xlsx_written += 1
                print(f"    saved -> {local_xlsx}", flush=True)
            except ImportError:
                print("    SKIPPED .xlsx: openpyxl is not installed. Run: pip install openpyxl",
                      flush=True)
                convert_skipped.append(name)
            except Exception as e:
                print(f"    FAILED to convert to .xlsx: {type(e).__name__}: {e}", flush=True)
                convert_failed.append(name)
            finally:
                try:
                    tmp_xlsx.unlink(missing_ok=True)
                except OSError:
                    pass
        except Exception as e:
            print(f"    UNEXPECTED ERROR on {name}: {type(e).__name__}: {e} -- skipping to next "
                  f"file.", flush=True)
            if name not in download_failed:
                download_failed.append(name)
            continue

    print("\n" + "=" * 60)
    print(f"Downloaded: {downloaded}/{len(csvs)} CSV file(s)")
    if download_failed:
        print(f"  Failed to download: {', '.join(download_failed)}")
    if not args.skip_xlsx and pd is not None:
        print(f"Converted to .xlsx: {converted}/{downloaded} CSV file(s) ({xlsx_written} .xlsx file(s) written)")
        if convert_skipped:
            print(f"  Skipped (no _submission_time / empty / missing openpyxl): {', '.join(convert_skipped)}")
        if convert_failed:
            print(f"  Failed / incomplete: {', '.join(convert_failed)}")
    print(f"Output folder: {output_dir}")

    return 1 if download_failed else 0


if __name__ == "__main__":
    sys.exit(main())
