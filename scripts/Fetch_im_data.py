#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Independent Monitoring (IM) Data Fetcher
Optimized for large ONA / WHONgHub datasets.

Clean Git Bash console version:
- Compact live progress per form
- Detailed page-level logs saved to logs/fetch_log.txt
- Uses ONA_API_TOKEN from environment if available
- Falls back to the provided API token if ONA_API_TOKEN is not set
- Saves raw data as compressed Parquet in data/raw
- Saves metadata and fetch summary JSON
- Uses centralized workflow folder:

  C:/Users/TOURE/Documents/im_workflow

Fetch modes (per form, decided automatically each run):
- FULL   : no local file yet, --force-full was passed, or the local copy's
           last full fetch is older than --full-refresh-days (default 30).
           Downloads every record and overwrites the local Parquet file.
- INCREMENTAL : local file is present and "fresh enough". Only records
           submitted after the locally stored last-submission cursor are
           requested (ONA "query" filter on _submission_time), then merged
           into the existing Parquet file and de-duplicated by _id.
- CHECK  : incremental fetch that finds 0 new records. The Parquet file is
           left untouched; only the metadata's "last_fetch" timestamp is
           updated so the log clearly shows the form was checked.

A periodic full refresh (--full-refresh-days) exists because a pure
"only new records" filter can never see edits/corrections made to
submissions that were already fetched in a previous run.
"""

import os
import re
import sys
import csv
import json
import time
import argparse
import subprocess
import tempfile
import requests
import pandas as pd
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq
import pyarrow.csv as pa_csv
import shutil
import gc

try:
    import resource

    def _peak_rss_mb():
        """Peak resident-set size for this process so far, in MB. Linux/
        macOS only (POSIX rusage) -- returns None on Windows so this is
        always safe to call unconditionally."""
        return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
except ImportError:
    def _peak_rss_mb():
        return None


# Column-name substrings (case-insensitive) marking a column as inherently
# high-cardinality: submission/record identifiers, timestamps, and
# GPS/geolocation fields are effectively unique per row, so encoding them
# as a pandas 'category' would need nearly as many distinct categories as
# there are rows -- no memory benefit. Every other column is treated as a
# survey answer field (select_one/select_multiple/short text), which in
# real IM form data is overwhelmingly repetitive across rows -- form
# 4498's real data measured 761 of its 822 columns as repetitive enough
# to qualify.
_HIGH_CARDINALITY_NAME_HINTS = (
    "id", "uuid", "time", "date", "edited", "gps", "geolocation",
    "latitude", "longitude", "altitude", "precision", "duration",
)


def _is_high_cardinality_field(col_name) -> bool:
    lowered = str(col_name).lower()
    return any(hint in lowered for hint in _HIGH_CARDINALITY_NAME_HINTS)


def _read_parquet_low_memory(path, filters=None) -> pd.DataFrame:
    """Read a form's existing Parquet file column-by-column instead of in
    one pd.read_parquet() call.

    ``filters`` (optional) is the same row-filter format pq.read_table()
    accepts, e.g. [("_submission_time", ">=", "2024-01-01")] -- when
    given, every per-column read below is filtered the same way, so the
    resulting DataFrame only has the matching rows.

    NOTE: this is NOT used by the year-partitioning migration
    (_split_into_year_partitions()), despite that being the original
    motivation for adding it. Parquet's predicate pushdown can only skip
    whole ROW GROUPS whose min/max stats don't overlap the filter -- it
    cannot avoid decoding a row group that PARTIALLY overlaps the filter,
    even when the matching output within it is tiny. Form 4498's file has
    only 2 row groups, so most year filters overlap its huge first row
    group and require fully decoding it per column regardless of filter
    selectivity -- confirmed directly to take 90+ seconds for a filter
    that should return under 1,000 rows. The migration instead reads
    each column once, unfiltered, and buckets rows into years in memory
    (see _split_into_year_partitions()). This parameter is kept because
    it is correct and fast for filters that align with a file's
    row-group boundaries -- just not this use case.

    Why: pd.read_parquet() decodes every column for every row at once.
    For a form as wide and long as form 4498 (822 columns x 1.12M rows),
    that single call needs on the order of 44 GiB -- enough on its own to
    trigger a hard OOM-kill (exit 137, uncatchable by any try/except)
    before this function or build_dataframe_from_records() ever gets a
    chance to shrink anything.

    Reading one column at a time instead lets Parquet's own column
    pruning do the work: only that column's compressed data is decoded,
    not the other 821. Columns that aren't a known high-cardinality
    system field (see _is_high_cardinality_field) are additionally
    decoded straight into a dictionary-encoded Arrow array
    (read_dictionary=[col]) and cast to pandas 'category', matching what
    build_dataframe_from_records() now does for newly-fetched data --
    most columns are repetitive survey answers, so this stores each
    distinct value once instead of once per row.

    Verified directly against form 4498's real 1.12M-row Parquet file:
    this brought peak process memory for a full read down from ~44 GiB
    (crashes) to ~3.3 GB (succeeds), producing an equivalent DataFrame.

    Columns are assigned one at a time into an already-sized DataFrame,
    not collected into a dict and handed to pd.DataFrame() at the end --
    that constructor re-aligns every column at once, which briefly needs
    a second full copy alongside the dict and can itself OOM even after
    the column-by-column read above has already succeeded (this was
    confirmed while testing this fix: the dict-based version crashed at
    that exact step).
    """
    pf = pq.ParquetFile(path)
    columns = [f.name for f in pf.schema_arrow]

    if filters is None:
        n_rows = pf.metadata.num_rows
    else:
        # pf.metadata.num_rows is the UNFILTERED row count -- when a
        # filter is given, get the real (filtered) row count from a
        # cheap single-column read instead of guessing.
        probe_col = columns[0]
        n_rows = pq.read_table(
            path, columns=[probe_col], filters=filters, use_threads=False
        ).num_rows

    df = pd.DataFrame(index=pd.RangeIndex(n_rows))

    for col in columns:
        low_cardinality = not _is_high_cardinality_field(col)
        read_dictionary = [col] if low_cardinality else None

        table = pq.read_table(
            path, columns=[col], read_dictionary=read_dictionary,
            filters=filters, use_threads=False
        )

        if low_cardinality:
            series = table.column(0).to_pandas()
            series = series.astype("category")
        else:
            # Arrow-backed dtype instead of plain to_pandas() (which would
            # box every value as a separate Python string object) -- see
            # the comment above this function's read_dictionary branch for
            # the measured 5.6x reduction this gives on form 4498's real
            # high-cardinality columns.
            series = table.column(0).to_pandas(types_mapper=pd.ArrowDtype)

        series.index = df.index

        df[col] = series
        del table, series

    return df

from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Union


# ============================================================
# WINDOWS CONSOLE ENCODING FIX
# ============================================================

if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


# ============================================================
# CENTRALIZED IM WORKFLOW PATHS
# ============================================================

# Resolved from --base-dir if the caller passed one (run_workflow.R always
# does, using its own already-validated BASE_DIR -- see find_workflow_home()
# in scripts/find_workflow_home.R), falling back to IM_WORKFLOW_HOME for
# anyone running this script standalone without the flag. Read manually,
# ahead of the argparse block in main() below, because these path constants
# are needed immediately at import time -- long before argparse would
# normally run.
def _cli_base_dir():
    argv = sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--base-dir" and i + 1 < len(argv):
            return argv[i + 1]
        if a.startswith("--base-dir="):
            return a.split("=", 1)[1]
    return None

BASE_DIR = Path(_cli_base_dir() or os.environ.get("IM_WORKFLOW_HOME", r"C:/Users/TOURE/Documents/im_workflow"))

DATA_DIR = BASE_DIR / "data"
RAW_DIR = DATA_DIR / "raw"
PROCESSED_DIR = DATA_DIR / "processed"
FINAL_DIR = DATA_DIR / "final"
LOOKUP_DIR = DATA_DIR / "lookup"

LOGS_DIR = BASE_DIR / "logs"
CONFIG_DIR = BASE_DIR / "config"
OUTPUTS_DIR = BASE_DIR / "outputs"

# Shared with run_workflow.R via the IM_RUN_ID environment variable when this
# script is launched as part of a full pipeline run, so the fetch history
# rows below can be matched up with that run's row in logs/run_history.csv.
# Falls back to generating its own id when run standalone.
RUN_ID = os.environ.get("IM_RUN_ID") or datetime.now().strftime("%Y%m%d_%H%M%S")

REPORTS_DIR = OUTPUTS_DIR / "reports"
DASHBOARDS_DIR = OUTPUTS_DIR / "dashboards"
EXPORTS_DIR = OUTPUTS_DIR / "exports"


def create_workflow_folders() -> None:
    """Create all required workflow folders if missing."""
    folders = [
        BASE_DIR,
        DATA_DIR,
        RAW_DIR,
        PROCESSED_DIR,
        FINAL_DIR,
        LOOKUP_DIR,
        LOGS_DIR,
        CONFIG_DIR,
        OUTPUTS_DIR,
        REPORTS_DIR,
        DASHBOARDS_DIR,
        EXPORTS_DIR,
        PROCESSED_DIR / "country",
        PROCESSED_DIR / "qc",
        PROCESSED_DIR / "logs",
    ]

    for folder in folders:
        folder.mkdir(parents=True, exist_ok=True)


# ============================================================
# API CONFIGURATION
# ============================================================
# Set ONA_API_TOKEN once via a local, git-ignored config/secrets.env file
# (copy config/secrets.env.example to get started), or via your shell:
#   Windows CMD:      setx ONA_API_TOKEN your_token_here
#   Git Bash session:  export ONA_API_TOKEN="your_token_here"
#
# No hardcoded fallback token here on purpose — this file is tracked in
# git, so a fallback secret here would end up in the repo's history.

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _env_loader import load_secrets_env
load_secrets_env(BASE_DIR)

ONA_API_TOKEN = os.environ.get("ONA_API_TOKEN", "")

if not ONA_API_TOKEN:
    raise RuntimeError(
        "Missing ONA_API_TOKEN. Set it as an environment variable, or fill in "
        "config/secrets.env (copy config/secrets.env.example to get started)."
    )

BASE_URL = "https://api.whonghub.org/api/v1/data"
USER_URL = "https://api.whonghub.org/api/v1/user.json"


# ============================================================
# SHAREPOINT RAW-STATE SYNC (Posit Connect Cloud decoupling)
# ============================================================
# Posit Connect Cloud runs this script in a fresh, throwaway container
# every time -- there is no local disk history like there is on this
# laptop. Without help, every cloud run would look like "no local copy
# yet" for all ~35 forms and do a full re-fetch of everything, every run.
#
# To avoid that, SharePoint doubles as the shared state store for
# data/raw (in addition to being the final-output destination that
# upload_to_sharepoint.py already pushes to): before deciding fetch modes,
# sync_missing_raw_from_sharepoint() pulls down whatever {form_id}.parquet
# + {form_id}_metadata.json this machine doesn't already have locally, and
# after a successful write, write_parquet_and_metadata() pushes that form's
# updated files back up via upload_raw_to_sharepoint(). This keeps a local
# PC run and a Connect Cloud run both reading/writing the same underlying
# state instead of silently diverging.
#
# Uses the same Graph app-only credentials as upload_to_sharepoint.py
# (SHAREPOINT_TENANT_ID / SHAREPOINT_CLIENT_ID / SHAREPOINT_CLIENT_SECRET),
# already loaded above via _env_loader. Soft-fails throughout: if
# credentials are missing or SharePoint is unreachable, sync is skipped
# and the script behaves exactly as it always has (local-disk-only).
import _sharepoint_client as sp

SP_RAW_FOLDER = "7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/raw_state"

_sp_session = {"tried": False, "token": None, "drive_id": None, "folder_ready": False}


def _get_sp_session():
    """Resolve and cache (token, drive_id) for the SharePoint raw-state
    sync, once per run. Returns (None, None) if credentials are missing or
    the site/drive can't be resolved -- callers just skip the sync then."""
    if _sp_session["tried"]:
        return _sp_session["token"], _sp_session["drive_id"]

    _sp_session["tried"] = True

    if not sp.credentials_available():
        detail("[sharepoint] Credentials not set -- skipping raw-state sync.")
        return None, None

    token = sp.get_token()
    if not token:
        detail("[sharepoint] Could not acquire Graph token -- skipping raw-state sync.")
        return None, None

    drive_id = sp.get_drive_id(token)
    if not drive_id:
        detail("[sharepoint] Could not resolve SharePoint drive -- skipping raw-state sync.")
        return None, None

    _sp_session["token"] = token
    _sp_session["drive_id"] = drive_id
    return token, drive_id


def sync_missing_raw_from_sharepoint(form_ids) -> None:
    """Before deciding fetch modes, pull down any {form_id}.parquet /
    {form_id}_metadata.json this machine doesn't have locally yet, from the
    shared SharePoint raw-state folder. This is what lets a fresh Posit
    Connect Cloud container resume from the last INCREMENTAL cursor
    instead of doing a full re-fetch of every form on every single run --
    and, symmetrically, lets a local run pick up whatever the cloud
    fetched since the last local run.

    Only fills in files that are missing locally -- never overwrites a
    local file that's already there, so this can never clobber
    still-in-progress local data with an older SharePoint copy.
    """
    token, drive_id = _get_sp_session()
    if not token:
        return

    missing_forms = [
        fid for fid in form_ids if not (RAW_DIR / f"{fid}.parquet").exists()
    ]

    if not missing_forms:
        return

    console(f"   Checking SharePoint for {len(missing_forms)} form(s) with no local copy...")
    remote_items = sp.list_folder(token, drive_id, SP_RAW_FOLDER)
    remote_names = {item["name"] for item in remote_items}

    recovered = 0
    for fid in missing_forms:
        parquet_name = f"{fid}.parquet"
        meta_name = f"{fid}_metadata.json"

        if parquet_name not in remote_names:
            continue

        parquet_ok = sp.download_file(
            token, drive_id, f"{SP_RAW_FOLDER}/{parquet_name}", RAW_DIR / parquet_name
        )
        if parquet_ok and meta_name in remote_names:
            sp.download_file(
                token, drive_id, f"{SP_RAW_FOLDER}/{meta_name}", RAW_DIR / meta_name
            )

        if parquet_ok:
            recovered += 1
            detail(f"[sharepoint] Recovered {parquet_name} from SharePoint raw-state folder.")

    if recovered:
        console(f"   Recovered {recovered} form(s) from SharePoint (no full re-fetch needed).")
    detail(f"[sharepoint] Raw-state sync: recovered {recovered}/{len(missing_forms)} missing form(s).")


def _export_csv(form_id: int) -> Optional[Path]:
    """Write a CSV twin of this form's just-finalized combined Parquet
    file, for anyone who wants to open a form's raw data directly
    without a Parquet-aware tool (Excel, a text editor, etc).

    Streams the Parquet file ONE ROW GROUP AT A TIME via
    pq.ParquetFile.read_row_group() straight into pyarrow's own
    CSVWriter -- never loads the whole form into a pandas DataFrame --
    so this is safe to run unconditionally for every form, including
    form 4498's 800+-column, 1M+-row combined file, without
    reintroducing the exact memory blowup the rest of this file's
    history is about (see _merge_and_dedup() / _recombine_year_
    partitions()'s own docstrings). A combined file written by
    _recombine_year_partitions() already has many small
    (_PARTITION_ROW_GROUP_SIZE-sized) row groups for exactly this
    reason; a plain (non-partitioned) form's file has only one or two
    larger ones, which is the same size of data this pipeline already
    safely handles elsewhere for those smaller forms.

    Returns the CSV's path on success, or None on any failure (never
    raises) -- a CSV export failing must not fail the fetch it happened
    alongside; the Parquet file (this pipeline's real source of truth)
    is unaffected either way."""
    source_path = RAW_DIR / f"{form_id}.parquet"
    if not source_path.exists():
        return None

    # Written to a SUBFOLDER of RAW_DIR, never RAW_DIR itself. The R
    # repository builder (regional_im_repository_builder.R) globs every
    # file directly inside data/raw/ whose extension is on its supported
    # list -- which includes both "csv" and "parquet" -- and that glob is
    # NOT recursive. A CSV twin written next to {form_id}.parquet at the
    # top level therefore got picked up as a *second*, redundant input
    # file for every form (34 forms -> 68 files processed), doubling that
    # step's memory churn with no benefit and no dedup logic on the R
    # side -- this is what caused Build Repository's OOM kill (exit 137)
    # on 2026-09-16. A subfolder is invisible to that non-recursive scan,
    # so the CSV twin can no longer collide with it no matter how many
    # times this fetch step runs before the build step does.
    csv_export_dir = RAW_DIR / "csv_export"
    csv_export_dir.mkdir(parents=True, exist_ok=True)
    csv_path = csv_export_dir / f"{form_id}.csv"
    writer = None
    try:
        pf = pq.ParquetFile(source_path)
        for rg_idx in range(pf.num_row_groups):
            table = pf.read_row_group(rg_idx)
            if writer is None:
                writer = pa_csv.CSVWriter(str(csv_path), table.schema)
            writer.write_table(table)
            del table

        if writer is None:
            # No row groups at all (an empty form) -- still produce a
            # header-only CSV rather than no file.
            writer = pa_csv.CSVWriter(str(csv_path), pf.schema_arrow)

        writer.close()
        writer = None
        return csv_path
    except Exception as e:
        if writer is not None:
            try:
                writer.close()
            except Exception:
                pass
        detail(f"[WARNING] Form {form_id} | CSV export failed: {e}")
        return None
    finally:
        gc.collect()
        pa.default_memory_pool().release_unused()


def upload_raw_to_sharepoint(form_id: int) -> None:
    """Push this form's freshly written Parquet + metadata (and a CSV
    twin -- see _export_csv()) to the shared SharePoint raw-state
    folder, right after a successful full or incremental save. Never
    raises -- a SharePoint hiccup here must not fail an otherwise-
    successful fetch; the next run's sync step will just catch it up
    from local disk (if this machine still has it) or retry the upload
    next time this form changes."""
    token, drive_id = _get_sp_session()
    if not token:
        return

    if not _sp_session["folder_ready"]:
        sp.ensure_folder(token, drive_id, SP_RAW_FOLDER)
        _sp_session["folder_ready"] = True

    parquet_path = RAW_DIR / f"{form_id}.parquet"
    meta_path = RAW_DIR / f"{form_id}_metadata.json"

    ok = True
    if parquet_path.exists():
        ok = sp.upload_file(token, drive_id, parquet_path, f"{SP_RAW_FOLDER}/{parquet_path.name}") and ok
    if meta_path.exists():
        ok = sp.upload_file(token, drive_id, meta_path, f"{SP_RAW_FOLDER}/{meta_path.name}") and ok

    if ok:
        detail(f"[sharepoint] Form {form_id} | raw state synced to SharePoint.")
    else:
        detail(f"[sharepoint] Form {form_id} | WARNING: raw state sync to SharePoint failed (kept local copy only).")

    csv_path = _export_csv(form_id)
    if csv_path is not None:
        csv_ok = sp.upload_file(token, drive_id, csv_path, f"{SP_RAW_FOLDER}/{csv_path.name}")
        if csv_ok:
            detail(f"[sharepoint] Form {form_id} | CSV twin synced to SharePoint.")
        else:
            detail(f"[sharepoint] Form {form_id} | WARNING: CSV twin upload to SharePoint failed.")


# ============================================================
# DEFAULT IM FORM IDS
# ============================================================
# Nigeria special form: 7178
# Algeria special form: 8587

DEFAULT_IM_FORM_IDS = [
    8587, 10267, 4385, 8832, 4459, 9597, 4434, 5710,
    4445, 4997, 4479, 4498, 8089, 6839, 3550, 5297,
    7585, 6418, 5887, 8279, 7600, 6427, 7621, 15780,
    5212, 9793, 6348, 6102, 5772, 7612, 4413, 6767,
    4344, 7980, 7178
]


# ============================================================
# LOGGING
# ============================================================

def log_to_file(message: str = "") -> None:
    """Append detailed message to fetch log."""
    try:
        create_workflow_folders()
        log_file = LOGS_DIR / "fetch_log.txt"

        with open(log_file, "a", encoding="utf-8") as f:
            f.write(f"{datetime.now().isoformat()} | {message}\n")

    except Exception:
        pass


# Emoji that carry actual status meaning are kept, just swapped for a plain
# ASCII tag -- this output is streamed live into the Shiny app's Pipeline
# console (a plain-text panel, not HTML), where a wall of colourful glyphs
# reads as clutter rather than a signal.
#
# NOTE: every non-ASCII character below is written as an explicit \u escape
# (never a literal emoji byte) on purpose -- this file gets copied around
# (zipped, emailed, re-saved by whatever editor touches it on Windows), and
# a literal multi-byte glyph is one bad re-save away from becoming invalid
# UTF-8, which would crash the script at import time with zero console
# output (before main() even runs) rather than fail loudly and obviously.
# Escapes are plain ASCII in the source, so they can't be corrupted this way.
_STATUS_TAGS = {
    "\u2705": "[OK]",        # check mark button (was printed as an emoji)
    "\u274c": "[ERROR]",     # cross mark
    "\u26a0\ufe0f": "[WARN]",  # warning sign + variation selector
    "\u26a0": "[WARN]",      # warning sign, no variation selector
}

# Everything else here is a purely decorative bullet (section-header icons
# like a package/rocket/chart/hourglass/checkmark) and is just dropped,
# along with one trailing space, so the line reads as plain text instead of
# an emoji + text mashup.
_DECORATIVE_EMOJI_RE = re.compile(
    "[\U0001F300-\U0001FAFF\u2600-\u27bf\u2190-\u21ff\u2300-\u23ff]\ufe0f? *"
)


def _declutter(message: str) -> str:
    """Strip decorative emoji from console/log text; keep status emoji as a
    plain-text tag ([OK]/[ERROR]/[WARN]) so the meaning survives as text."""
    for glyph, tag in _STATUS_TAGS.items():
        message = message.replace(glyph, tag)
    return _DECORATIVE_EMOJI_RE.sub("", message)


def console(message: str = "") -> None:
    """Print compact console message and save it to log."""
    message = _declutter(message)
    print(message, flush=True)
    log_to_file(message)


def detail(message: str = "") -> None:
    """Write detailed message to log only."""
    log_to_file(_declutter(message))


def live_line(message: str) -> None:
    """Print a single refreshing console line."""
    print(f"\r{_declutter(message)}", end="", flush=True)


def clear_live_line() -> None:
    """Move to next line after live progress."""
    print("", flush=True)


# ============================================================
# HELPERS
# ============================================================

def flatten_dict(data: Dict, parent_key: str = "", sep: str = "/") -> Dict:
    """Flatten nested ONA/ODK dictionary structure."""
    flattened = {}

    for key, value in data.items():

        if parent_key and not parent_key.endswith("Count_HH"):
            new_key = f"{parent_key}{sep}{key}"
        else:
            new_key = f"{parent_key}{key}" if parent_key else key

        if isinstance(value, dict):
            flattened.update(flatten_dict(value, new_key, sep=sep))

        elif isinstance(value, list):
            for i, item in enumerate(value, 1):
                if isinstance(item, dict):
                    flattened.update(
                        flatten_dict(item, f"{new_key}[{i}]", sep=sep)
                    )
                else:
                    flattened[f"{new_key}[{i}]"] = (
                        str(item) if item is not None else ""
                    )

        else:
            flattened[new_key] = str(value) if value is not None else ""

    return flattened


def get_auth_headers() -> Dict[str, str]:
    """Return API authorization headers."""
    if not ONA_API_TOKEN:
        return {}

    return {"Authorization": f"Token {ONA_API_TOKEN}"}


class IncrementalFetchError(Exception):
    """Raised when a strict (incremental) page fetch cannot be trusted.

    Any of these means we cannot safely assume "no new records" — the
    caller should fall back to a full fetch for this form instead of
    silently treating the failure as zero-new-records.
    """
    pass


def fetch_page(
    form_id: int,
    page: int,
    page_size: int = 10000,
    query: Optional[Dict] = None,
    strict: bool = False,
    max_attempts: int = 3,
    retry_delays: Optional[List[int]] = None
) -> Optional[List[Dict]]:
    """Fetch one page of data for a form, retrying transient failures.

    ``query`` is an optional Mongo-style filter dict, sent as ONA's
    ``query`` parameter (JSON-encoded). Used for incremental fetches, e.g.
    ``{"_submission_time": {"$gte": "2026-08-01T00:00:00"}}``.

    Transient-looking failures (timeout, connection errors, 500/502/503/504,
    and a malformed/truncated JSON body) are retried up to ``max_attempts``
    times with a short backoff before being treated as a real failure — a
    single dropped connection or a momentary 502 from the API used to be
    enough to permanently corrupt a form's data (see below), so it's worth
    a couple of retries before giving up.

    ``strict`` controls error handling on final failure: when False
    (default, used for full fetches), the failure is logged and ``None`` is
    returned. When True (used for incremental fetches), it's raised as
    ``IncrementalFetchError`` instead — an incremental fetch that silently
    returns [] on a real failure would be wrongly recorded as "0 new
    records", corrupting the cursor. The caller is expected to catch this
    and fall back to a full fetch for the form.

    IMPORTANT: on non-strict final failure this returns ``None``, NOT ``[]``.
    An empty list means "the API confirms there is nothing more here" (a
    safe, legitimate end of pagination). ``None`` means "we could not get a
    trustworthy answer for this page" — callers must NOT treat the two the
    same. This distinction exists because form 4498's full fetches used to
    stop early (truncating hundreds of thousands of already-fetched rows,
    and rewinding its incremental cursor to a stale 2023 date) whenever a
    single page hit a transient error: the old code returned [] either way,
    so a network hiccup on page 19 looked identical to "that was the last
    page", and the run happily saved the truncated result as if it were
    complete.
    """
    if retry_delays is None:
        retry_delays = [30, 90]

    headers = get_auth_headers()

    params = {
        "page": page,
        "page_size": page_size
    }

    if query:
        params["query"] = json.dumps(query, separators=(",", ":"))

    last_error = "unknown error"

    for attempt in range(1, max_attempts + 1):
        try:
            response = requests.get(
                f"{BASE_URL}/{form_id}.json",
                params=params,
                headers=headers,
                timeout=180
            )

            if response.status_code == 200:
                try:
                    return response.json()
                except ValueError as e:
                    last_error = f"malformed/truncated JSON response ({e})"
                    detail(
                        f"Form {form_id} | Page {page} | Attempt {attempt}/{max_attempts} | "
                        f"{last_error}"
                    )

            elif response.status_code == 429:
                detail(f"Form {form_id} | Page {page} | Rate limited. Waiting 30 seconds.")
                time.sleep(30)
                continue

            elif response.status_code in (401, 403):
                last_error = f"auth failed (HTTP {response.status_code})"
                detail(f"Form {form_id} | {last_error}.")
                if strict:
                    raise IncrementalFetchError(
                        f"Form {form_id} | {last_error} on incremental query"
                    )
                return None

            elif response.status_code == 404:
                # A genuine 404 means there is nothing to fetch here — this is
                # a real, trustworthy "no data", not a transient failure.
                detail(f"Form {form_id} | Not found.")
                return []

            elif response.status_code in (500, 502, 503, 504):
                last_error = f"HTTP {response.status_code} (server-side, likely transient)"
                detail(
                    f"Form {form_id} | Page {page} | Attempt {attempt}/{max_attempts} | {last_error}"
                )

            else:
                last_error = f"HTTP {response.status_code}"
                detail(f"Form {form_id} | Page {page} | {last_error}.")
                if strict:
                    raise IncrementalFetchError(
                        f"Form {form_id} | {last_error} on incremental query"
                    )
                return None

        except IncrementalFetchError:
            raise

        except requests.exceptions.Timeout:
            last_error = "timeout"
            detail(f"Form {form_id} | Page {page} | Attempt {attempt}/{max_attempts} | Timeout.")

        except requests.exceptions.RequestException as e:
            last_error = f"connection error: {e}"
            detail(
                f"Form {form_id} | Page {page} | Attempt {attempt}/{max_attempts} | {last_error}"
            )

        except Exception as e:
            last_error = f"error: {e}"
            detail(
                f"Form {form_id} | Page {page} | Attempt {attempt}/{max_attempts} | {last_error}"
            )

        if attempt < max_attempts:
            delay = retry_delays[min(attempt - 1, len(retry_delays) - 1)]
            detail(f"Form {form_id} | Page {page} | Retrying in {delay}s...")
            time.sleep(delay)

    detail(
        f"Form {form_id} | Page {page} | Giving up after {max_attempts} attempt(s) | "
        f"Last error: {last_error}"
    )

    if strict:
        raise IncrementalFetchError(
            f"Form {form_id} | {last_error} on incremental query (after {max_attempts} attempts)"
        )

    return None


def fetch_all_data(
    form_id: int,
    form_index: int,
    total_forms: int,
    page_size: int = 10000
):
    """Fetch ALL records for one form (full fetch) with compact live console progress.

    Returns ``(combined_df, fetch_complete)`` -- an object-dtype DataFrame,
    not a list of records (see below for why this changed).
    ``fetch_complete`` is False if a page had to be given up on after
    retries (see ``fetch_page``) — in that case ``combined_df`` is only a
    PARTIAL, untrustworthy result and callers must not save it over
    existing data or treat its max submission time as a safe incremental
    cursor.

    Used to accumulate every page's raw flattened record dicts into one
    Python list (``all_data``) for the ENTIRE fetch, only converting to a
    DataFrame once every page was in. For a wide form that's enormously
    wasteful: each row-dict repeats all of that form's field names as its
    own keys and carries its own dict/hash-table overhead, on top of the
    actual values. Measured directly against form 5710's real data
    (694 columns): building its full 106,079-record list this way costs
    ~4.8 GB, BEFORE build_dataframe_from_records() ever runs -- and the
    2026-09-21 and 2026-09-22 production runs both died (exit 137) while
    STILL PAGING (page 8-11 of 11), i.e. accumulating this same list, not
    during the later DataFrame-build/save step. An object-dtype DataFrame
    of one page needs only a 2D array of pointers (no per-row key
    duplication) -- roughly two orders of magnitude smaller for a page
    this wide. Building one small DataFrame per page and dropping that
    page's raw JSON/dict records immediately (rather than keeping them
    around until the very end) keeps the peak to whatever the largest
    single page plus the running concatenated total costs, instead of the
    full multi-hundred-thousand-record list all at once.

    Every page's DataFrame stays plain 'object' dtype (no categorical
    conversion yet), so concatenating them at the end is a plain-dtype
    concat with nothing to reconcile -- contrast this with what
    _merge_and_dedup() has to do when combining DataFrames whose
    categorical dtypes actually differ. The result is the same shape
    pd.DataFrame(all_data) used to build from the full flat record list,
    just without ever materializing that list in full.
    """
    page_frames: List[pd.DataFrame] = []
    total_records = 0
    page = 1
    fetch_complete = True

    console(f"📦 Form {form_id} ({form_index}/{total_forms}) | FULL fetch")
    detail(f"[FETCH:FULL] Form {form_id}")

    while True:
        live_line(
            f"   ⏳ Fetching page {page} | Records so far: {total_records:,}"
        )

        page_records = fetch_page(form_id, page, page_size)

        if page_records is None:
            clear_live_line()
            detail(f"Form {form_id} | Page {page} | Giving up -- fetch marked INCOMPLETE.")
            fetch_complete = False
            break

        if not page_records:
            clear_live_line()
            detail(f"Form {form_id} | Page {page} | No data returned.")
            break

        flattened_page = [flatten_dict(record) for record in page_records]
        page_df = pd.DataFrame(flattened_page)
        del page_records, flattened_page

        page_frames.append(page_df)
        total_records += len(page_df)

        detail(
            f"Form {form_id} | Page {page} | Retrieved {len(page_df):,} records | "
            f"Running total: {total_records:,}"
        )

        live_line(
            f"   ⏳ Page {page} complete | Records so far: {total_records:,}"
        )

        if len(page_df) < page_size:
            clear_live_line()
            break

        page += 1
        time.sleep(0.5)

    if page_frames:
        combined_df = pd.concat(page_frames, ignore_index=True, sort=False)
        del page_frames
        gc.collect()
    else:
        combined_df = pd.DataFrame()

    if fetch_complete:
        console(f"   ✅ Fetch complete: {len(combined_df):,} records across {page} page(s)")
    else:
        console(
            f"   ⚠️  Fetch INCOMPLETE: page {page} failed after retries — only "
            f"{len(combined_df):,} record(s) retrieved. Existing data will NOT be "
            f"overwritten with this partial result."
        )

    detail(f"[DONE] Form {form_id}: {len(combined_df):,} total records | complete={fetch_complete}")

    return combined_df, fetch_complete


def fetch_new_data(
    form_id: int,
    since_iso: str,
    form_index: int,
    total_forms: int,
    page_size: int = 10000
) -> List[Dict]:
    """Fetch only records submitted at/after ``since_iso`` (incremental fetch).

    Uses ONA's Mongo-style ``query`` filter on ``_submission_time``. Raises
    ``IncrementalFetchError`` (via the underlying strict ``fetch_page``
    calls) if the API doesn't answer this the way we expect — the caller
    must catch that and fall back to a full fetch rather than assume zero
    new records.
    """
    all_data = []
    page = 1
    query = {"_submission_time": {"$gte": since_iso}}

    console(
        f"🔄 Form {form_id} ({form_index}/{total_forms}) | "
        f"INCREMENTAL fetch since {since_iso}"
    )
    detail(f"[FETCH:INCREMENTAL] Form {form_id} | since {since_iso}")

    while True:
        live_line(
            f"   ⏳ Fetching new page {page} | New records so far: {len(all_data):,}"
        )

        data = fetch_page(form_id, page, page_size, query=query, strict=True)

        if not data:
            clear_live_line()
            detail(f"Form {form_id} | Incremental page {page} | No new data returned.")
            break

        flattened_data = [flatten_dict(record) for record in data]
        all_data.extend(flattened_data)

        detail(
            f"Form {form_id} | Incremental page {page} | Retrieved {len(data):,} records | "
            f"Running total: {len(all_data):,}"
        )

        live_line(
            f"   ⏳ New page {page} complete | New records so far: {len(all_data):,}"
        )

        if len(data) < page_size:
            clear_live_line()
            break

        page += 1
        time.sleep(0.5)

    console(f"   ✅ Incremental fetch complete: {len(all_data):,} new record(s)")
    detail(f"[DONE:INCREMENTAL] Form {form_id}: {len(all_data):,} new records")

    return all_data


def extract_gps_components(df: pd.DataFrame) -> pd.DataFrame:
    """Extract GPS latitude, longitude, altitude, and precision if fields exist.

    Collects every derived column first and adds them to the DataFrame in a
    single ``pd.concat`` instead of one ``df[new_col] = ...`` assignment at a
    time. Inserting several new columns one by one is exactly what pandas'
    "DataFrame is highly fragmented" PerformanceWarning is about -- on a
    35-form fetch run that was firing dozens of times, burying the actual
    per-form progress log under noise. Same result, quiet console.
    """
    gps_fields = {
        "GPS_hh": "_GPS_hh",
        "GPS_hh_end": "_GPS_hh_end",
        "gps": "_gps",
        "_geolocation": "_geolocation"
    }

    new_columns = {}

    for source_col, prefix in gps_fields.items():
        if source_col in df.columns:
            gps_parts = df[source_col].astype(str).str.split(" ", expand=True)

            if len(gps_parts.columns) >= 2:
                new_columns[f"{prefix}_latitude"] = gps_parts[0]
                new_columns[f"{prefix}_longitude"] = gps_parts[1]

            if len(gps_parts.columns) >= 3:
                new_columns[f"{prefix}_altitude"] = gps_parts[2]

            if len(gps_parts.columns) >= 4:
                new_columns[f"{prefix}_precision"] = gps_parts[3]

    if new_columns:
        df = pd.concat([df, pd.DataFrame(new_columns, index=df.index)], axis=1)

    return df


def build_dataframe_from_records(data: Union[List[Dict], pd.DataFrame]) -> pd.DataFrame:
    """Turn flattened records into the standard IM DataFrame (all-string
    columns, GPS components split out). Shared by full and incremental
    fetches so both produce identical column shapes.

    ``data`` is normally a List[Dict] (the small incremental-merge batches
    still build one this way), but fetch_all_data() now hands this an
    already-concatenated object-dtype DataFrame instead -- see its own
    docstring for why. When it's already a DataFrame, it's used directly
    (no ``pd.DataFrame(data)`` copy) and every column below is cast IN
    PLACE on that same object: there is no separate "raw records" form
    left over afterward to free, unlike the List[Dict] path, where `data`
    and the newly-built `df` really are two distinct objects until the
    caller drops its own reference to `data`.

    Fills/casts one column at a time instead of calling
    ``df.fillna("").astype(str)`` on the whole table in one shot. pandas'
    whole-table ``fillna`` makes an internal defensive copy of the ENTIRE
    block before it can fill anything in it -- for a very wide, very long
    form (form 4498: 814 columns x 1,120,817 rows) that single extra copy
    needs ~6.8 GiB on top of the DataFrame that already exists in memory,
    which is enough on its own to raise a MemoryError before any real work
    happens (this is exactly what crashed the 2026-08-22 run, right after
    the fetch itself had completed cleanly). Doing it column by column
    keeps the extra allocation to one column's worth of data at a time.
    """
    df = data if isinstance(data, pd.DataFrame) else pd.DataFrame(data)

    for col in df.columns:
        series = df[col]
        if series.isna().any():
            series = series.fillna("")
        df[col] = series.astype(str)

    df = extract_gps_components(df)

    # Cast every column that isn't a known high-cardinality system field
    # (see _is_high_cardinality_field) to pandas' 'category' dtype. See
    # _read_parquet_low_memory()'s docstring for the full rationale and
    # the measured ~13x memory reduction on form 4498's real data -- the
    # short version is that most columns here are repetitive survey
    # answers, and category dtype stores each distinct value once instead
    # of once per row.
    for col in df.columns:
        if not _is_high_cardinality_field(col):
            df[col] = df[col].astype("category")
        else:
            df[col] = df[col].astype(pd.ArrowDtype(pa.string()))

    return df


def _max_submission_time(df: pd.DataFrame) -> Optional[str]:
    """Return the max ``_submission_time`` value in df as a string, or None
    if the column is missing/empty. Relies on ISO-8601 strings sorting
    correctly as plain strings."""
    if "_submission_time" not in df.columns or df.empty:
        return None

    values = [v for v in df["_submission_time"].tolist() if v]

    if not values:
        return None

    return max(values)


def _parse_iso_datetime(value: str) -> Optional[datetime]:
    """Best-effort ISO-8601 parse. Returns None (rather than raising) on
    anything unexpected, so callers can safely fall back to a full fetch."""
    if not value:
        return None

    try:
        cleaned = value.strip()

        if cleaned.endswith("Z"):
            cleaned = cleaned[:-1] + "+00:00"

        return datetime.fromisoformat(cleaned)

    except Exception:
        return None


def compute_since_iso(last_submission_time: Optional[str], overlap_minutes: int = 5) -> Optional[str]:
    """Compute the "_submission_time >= X" cursor for an incremental fetch,
    stepping back a few minutes from the stored cursor as a safety overlap
    (duplicates this may reintroduce are removed later by de-duplicating on
    _id). Returns None if the stored cursor can't be parsed — callers must
    treat that as "incremental fetch is not safe, do a full fetch"."""
    parsed = _parse_iso_datetime(last_submission_time) if last_submission_time else None

    if parsed is None:
        return None

    since = parsed - timedelta(minutes=overlap_minutes)
    return since.isoformat()


def write_parquet_and_metadata(
    df: pd.DataFrame,
    form_id: int,
    meta_extra: Dict
) -> Optional[Dict]:
    """Write ``df`` as the form's Parquet file and write/merge its metadata
    JSON. ``meta_extra`` supplies the fields that differ between a full and
    an incremental save (fetch_mode, last_full_fetch, last_submission_time,
    etc.) and is merged on top of the computed base fields."""
    try:
        create_workflow_folders()

        output_path = RAW_DIR / f"{form_id}.parquet"
        parquet_engine = None

        try:
            df.to_parquet(
                output_path,
                engine="pyarrow",
                compression="snappy",
                index=False
            )
            parquet_engine = "pyarrow"

        except ImportError:
            try:
                df.to_parquet(
                    output_path,
                    engine="fastparquet",
                    compression="snappy",
                    index=False
                )
                parquet_engine = "fastparquet"

            except ImportError:
                console("   ❌ No Parquet engine available. Install with: pip install pyarrow")
                return None

        file_size_mb = output_path.stat().st_size / (1024 * 1024)
        memory_size_mb = df.memory_usage(deep=True).sum() / (1024 * 1024)

        compression_ratio = (
            memory_size_mb / file_size_mb if file_size_mb > 0 else None
        )

        metadata = {
            "workflow": "Independent Monitoring IM",
            "form_id": form_id,
            "records": int(len(df)),
            "columns": int(len(df.columns)),
            "parquet_size_mb": round(file_size_mb, 2),
            "estimated_memory_size_mb": round(memory_size_mb, 2),
            "compression_ratio": round(compression_ratio, 1) if compression_ratio else None,
            "last_fetch": datetime.now().isoformat(),
            "shape": f"{df.shape[0]}x{df.shape[1]}",
            "format": "parquet",
            "engine": parquet_engine,
            "output_path": str(output_path)
        }

        metadata.update(meta_extra or {})

        metadata_path = RAW_DIR / f"{form_id}_metadata.json"

        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        detail(
            f"[SAVED] Form {form_id}: {len(df):,} rows | "
            f"{file_size_mb:.2f} MB | {len(df.columns):,} columns | "
            f"mode={metadata.get('fetch_mode', 'full')}"
        )

        upload_raw_to_sharepoint(form_id)

        return metadata

    except Exception as e:
        console(f"   ❌ Failed to save form {form_id}: {e}")

        import traceback
        traceback.print_exc()

        return None


def save_to_parquet(data: List[Dict], form_id: int) -> Optional[Dict]:
    """Save form data as Parquet and write metadata (FULL fetch — always
    overwrites). Used for the first fetch of a form, --force-full, and
    periodic full refreshes."""
    if not data:
        detail(f"[WARNING] No data to save for form {form_id}")
        return None

    df = build_dataframe_from_records(data)
    now_iso = datetime.now().isoformat()

    meta_extra = {
        "fetch_mode": "full",
        "last_full_fetch": now_iso,
        "last_submission_time": _max_submission_time(df),
        "fetch_complete": True,
    }

    result = write_parquet_and_metadata(df, form_id, meta_extra)

    if result is not None:
        # This full fetch just overwrote the combined file directly --
        # any year-partition files left over from before it are now
        # stale (see this patch's own history / _clear_stale_partitions()
        # docstring for why that matters).
        _clear_stale_partitions(form_id)

    return result


def save_incremental(
    form_id: int,
    new_data: List[Dict],
    previous_metadata: Dict
) -> Optional[Dict]:
    """Merge newly-fetched records into the existing Parquet file for a
    form and write updated metadata (INCREMENTAL fetch — de-duplicates by
    _id, keeping the newly-fetched copy of any record seen in both).

    Returns None if the merge can't be done safely (missing local file,
    unreadable Parquet, or no _id column to de-duplicate on) — the caller
    should treat that as a signal to fall back to a full fetch.

    Forms that have grown past _PARTITION_ROW_THRESHOLD (or have already
    been migrated) are handed off to _save_incremental_partitioned()
    instead of the plain single-file path below -- see that function's
    docstring for why (concatenating a very large form's full history
    against new data can still exceed available memory even alone in an
    isolated subprocess; year-partitioning keeps an ordinary run's
    concat to just the current year's data).
    """
    if not new_data:
        return None

    if _is_form_partitioned(form_id) or previous_metadata.get("records", 0) > _PARTITION_ROW_THRESHOLD:
        return _save_incremental_partitioned(form_id, new_data, previous_metadata)

    existing_path = RAW_DIR / f"{form_id}.parquet"

    if not existing_path.exists():
        detail(f"[WARNING] Form {form_id} | Incremental merge requested but no existing Parquet file.")
        return None

    try:
        existing_df = _read_parquet_low_memory(existing_path)
    except Exception as e:
        detail(f"[WARNING] Form {form_id} | Could not read existing Parquet for merge: {e}")
        return None

    new_df = build_dataframe_from_records(new_data)

    if "_id" not in existing_df.columns or "_id" not in new_df.columns:
        detail(f"[WARNING] Form {form_id} | No _id column available — cannot safely de-duplicate merge.")
        return None

    try:
        # See _merge_and_dedup()'s own docstring for the full history of
        # why this concat/fillna/dedup sequence is shaped the way it is
        # (the 2026-08-22 form-4498 OOM crash and its root causes) -- it
        # is now shared with the per-year-partition merge path in
        # _save_incremental_partitioned() so both get identical handling.
        combined = _merge_and_dedup(existing_df, new_df)
    except Exception as e:
        detail(f"[WARNING] Form {form_id} | Merge/de-duplication failed: {e}")
        return None

    new_submission_time = _max_submission_time(new_df)
    prev_submission_time = previous_metadata.get("last_submission_time")
    candidates = [t for t in [new_submission_time, prev_submission_time] if t]
    last_submission_time = max(candidates) if candidates else None

    meta_extra = {
        "fetch_mode": "incremental",
        "last_full_fetch": previous_metadata.get("last_full_fetch"),
        "last_submission_time": last_submission_time,
        "new_records_this_run": int(len(new_df)),
        "fetch_complete": True,
    }

    return write_parquet_and_metadata(combined, form_id, meta_extra)


# A form whose existing local copy has at least this many rows gets its
# incremental merge run in an isolated child process instead of in this
# one (see _merge_incremental_isolated() below). Every memory
# optimization in save_incremental() / build_dataframe_from_records() /
# _read_parquet_low_memory() above still applies inside that child --
# this is a SECOND, independent layer of defense: if a form is so large
# that even those optimizations aren't enough and the merge gets
# OOM-killed anyway, isolating it in its own process means only that
# child dies. Without this, the OS SIGKILL takes down this entire fetch
# process -- uncatchable by any try/except, see the module-level notes
# on that -- and every form still queued behind the huge one (form 4498
# is #12 of 35) never even gets attempted for the rest of that run.
_ISOLATE_MERGE_ROW_THRESHOLD = 500_000


def _merge_incremental_isolated(
    form_id: int,
    new_data: List[Dict],
    previous_metadata: Dict
) -> Optional[Dict]:
    """Run save_incremental() for one form in a fresh child process and
    report a clean failure (returning None) if that child gets
    OOM-killed, instead of letting the kill take this whole fetch run
    down with it.

    Talks to the child through three small temp JSON files (new data,
    previous metadata, result) rather than the child's stdout, since this
    script's stdout doubles as the live progress log Connect Cloud shows
    while the run is in progress.
    """
    with tempfile.TemporaryDirectory(prefix=f"im_merge_{form_id}_") as tmp_dir:
        tmp_path = Path(tmp_dir)
        new_data_path = tmp_path / "new_data.json"
        metadata_path = tmp_path / "previous_metadata.json"
        result_path = tmp_path / "result.json"

        with open(new_data_path, "w", encoding="utf-8") as f:
            json.dump(new_data, f, ensure_ascii=False)
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(previous_metadata, f, ensure_ascii=False)

        cmd = [
            sys.executable, str(Path(__file__).resolve()),
            "--base-dir", str(BASE_DIR),
            "--internal-merge-form", str(form_id),
            "--new-data-file", str(new_data_path),
            "--previous-metadata-file", str(metadata_path),
            "--result-file", str(result_path),
        ]

        detail(f"Form {form_id} | Launching isolated merge subprocess: {cmd}")

        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=1200)
        except subprocess.TimeoutExpired:
            console(f"   \u26a0\ufe0f  Form {form_id} | Isolated merge subprocess timed out after 20 minutes.")
            detail(f"Form {form_id} | Isolated merge subprocess timed out.")
            return None

        if proc.returncode != 0:
            if proc.returncode < 0:
                console(
                    f"   \u26a0\ufe0f  Form {form_id} | Isolated merge subprocess was killed "
                    f"(signal {-proc.returncode}, almost certainly an out-of-memory kill) -- "
                    f"this form's existing data is untouched and the {len(new_data):,} new "
                    f"record(s) will be retried next run. The rest of this fetch continues normally."
                )
            else:
                console(
                    f"   \u26a0\ufe0f  Form {form_id} | Isolated merge subprocess failed "
                    f"(exit {proc.returncode}) -- see logs/fetch_log.txt for its output."
                )
            detail(
                f"Form {form_id} | Isolated merge subprocess returncode={proc.returncode}\n"
                f"--- child stdout (last 4000 chars) ---\n{proc.stdout[-4000:]}\n"
                f"--- child stderr (last 4000 chars) ---\n{proc.stderr[-4000:]}"
            )
            return None

        if not result_path.exists():
            detail(f"Form {form_id} | Isolated merge subprocess exited 0 but wrote no result file.")
            return None

        with open(result_path, "r", encoding="utf-8") as f:
            return json.load(f)


# A form whose existing local copy has at least this many rows gets
# migrated to per-calendar-year partitioned storage instead of one big
# Parquet file -- see _is_form_partitioned() / _save_incremental_
# partitioned() below. Reuses _ISOLATE_MERGE_ROW_THRESHOLD's value: a
# form this large already runs its merge in an isolated subprocess, and
# partitioning is the fix for what that isolation only CONTAINS rather
# than solves -- form 4498's merge was still getting OOM-killed even
# alone in its own process, because concatenating ~1.12M existing rows
# with new data is itself too much regardless of process isolation.
# Splitting stored data by year means an ordinary incremental run only
# ever concatenates new records against ONE year's worth of existing
# data (well under this threshold), because new submissions almost
# always land in the current year.
_PARTITION_ROW_THRESHOLD = _ISOLATE_MERGE_ROW_THRESHOLD


def _partition_dir(form_id: int) -> Path:
    return RAW_DIR / f"{form_id}_partitions"


def _partition_path(form_id: int, year: str) -> Path:
    return _partition_dir(form_id) / f"{form_id}_{year}.parquet"


# Row-group size used when writing partition files -- see
# _recombine_year_partitions()'s docstring for why keeping this small
# matters for that function's own memory footprint.
_PARTITION_ROW_GROUP_SIZE = 20_000


def _migration_marker_path(form_id: int) -> Path:
    return _partition_dir(form_id) / "_MIGRATION_COMPLETE"


def _is_form_partitioned(form_id: int) -> bool:
    """True once a form has been FULLY migrated to year-partitioned
    storage. Detected via an explicit completion marker file
    (_MIGRATION_COMPLETE) written by _split_into_year_partitions() only
    as its very last step -- NOT by checking whether any partition file
    happens to exist. This matters: if a migration attempt gets
    OOM-killed partway through writing partition files (as happened on
    Connect Cloud with form 4498), an "any file exists" check could see
    a PARTIAL set of year files (e.g. 2020-2022 written, 2023-2026
    missing) and wrongly conclude the form is fully partitioned -- the
    next run would then merge and recombine from that incomplete set,
    silently losing every year that never got written. Requiring an
    explicit marker written only after every year succeeds means a
    crash at any point during migration is safely treated as "not yet
    partitioned," and the whole thing retries cleanly from scratch next
    time (see _split_into_year_partitions(), which also wipes the
    partition directory before writing anything, for the other half of
    this safety net)."""
    return _migration_marker_path(form_id).exists()


def _sp_partition_folder(form_id: int) -> str:
    """SharePoint subfolder holding one form's year-partition files and
    completion marker -- kept separate from SP_RAW_FOLDER's own root
    (where only the single combined {form_id}.parquet + metadata live)
    so a plain listing of the raw-state folder doesn't get cluttered
    with per-year files for every partitioned form."""
    return f"{SP_RAW_FOLDER}/partitions/{form_id}"


def _upload_partitions_to_sharepoint(form_id: int) -> None:
    """Push this form's year-partition files and completion marker to
    SharePoint, right after a successful recombine -- mirrors
    upload_raw_to_sharepoint()'s existing pattern for the combined file,
    but for the partition files themselves.

    Without this, a completed migration only ever lived on the one
    container's local disk that happened to run it. Every other
    container (which on Connect Cloud means practically every run --
    see _recover_partitions_from_sharepoint()'s docstring) would see no
    local partition directory, conclude the form isn't partitioned yet,
    and redo the full multi-minute local migration from scratch every
    single time -- which is exactly what caused form 4498's isolated
    merge subprocess to time out at 10 minutes on a fresh container
    despite the exact same migration finishing comfortably inside that
    budget once before. Persisting the partition files here is what
    makes "migration only really happens once" actually true across
    container restarts, not just true on one person's laptop.

    Uploads the completion marker LAST, and only once every partition
    file has already uploaded successfully -- same crash-safety
    ordering as the local write side (see _is_form_partitioned()'s
    docstring): a SharePoint listing that shows the marker must be able
    to trust that every partition file behind it is actually there too.
    Never raises -- same best-effort contract as the rest of this
    SharePoint layer; a failure here just means the next fresh
    container redoes the local migration instead of recovering it,
    exactly as if this function didn't exist."""
    token, drive_id = _get_sp_session()
    if not token:
        return

    if not _is_form_partitioned(form_id):
        return

    partition_dir = _partition_dir(form_id)
    remote_folder = _sp_partition_folder(form_id)
    sp.ensure_folder(token, drive_id, remote_folder)

    partition_files = sorted(partition_dir.glob(f"{form_id}_*.parquet"))
    ok = True
    for p in partition_files:
        ok = sp.upload_file(token, drive_id, p, f"{remote_folder}/{p.name}") and ok

    marker_path = _migration_marker_path(form_id)
    if ok and marker_path.exists():
        ok = sp.upload_file(token, drive_id, marker_path, f"{remote_folder}/{marker_path.name}") and ok

    if ok:
        detail(f"[sharepoint] Form {form_id} | {len(partition_files)} year partition(s) + completion marker synced to SharePoint.")
    else:
        detail(f"[sharepoint] Form {form_id} | WARNING: partition sync to SharePoint failed (kept local copy only; a future run will retry).")


def _recover_partitions_from_sharepoint(form_id: int) -> bool:
    """Best-effort attempt to restore an already-completed year-partition
    migration from SharePoint instead of redoing the expensive local
    migration from scratch -- the read-side counterpart to
    _upload_partitions_to_sharepoint(). See that function's docstring
    for why this matters: on Connect Cloud, a fresh container's local
    disk never has this form's partition directory on its own, only
    whatever sync_missing_forms_from_sharepoint() already recovered (the
    single combined {form_id}.parquet), so without this, every run pays
    the full migration cost forever, not just once.

    Returns True only if a complete set (the completion marker AND every
    partition file behind it) was found on SharePoint and downloaded
    successfully. Checks for the marker FIRST and bails out immediately
    if it's missing, without downloading any partition files -- an
    interrupted upload that never got as far as writing the marker (see
    _upload_partitions_to_sharepoint()) must never be mistaken for a
    complete one. Returns False in every other case (nothing there yet,
    a partial/failed upload from some earlier run, or any download
    failure here), leaving the caller to redo the full local migration
    exactly as if this function didn't exist. Never raises."""
    token, drive_id = _get_sp_session()
    if not token:
        return False

    remote_folder = _sp_partition_folder(form_id)
    remote_items = sp.list_folder(token, drive_id, remote_folder)
    remote_names = {item["name"] for item in remote_items}

    marker_name = "_MIGRATION_COMPLETE"
    if marker_name not in remote_names:
        return False

    partition_names = sorted(
        n for n in remote_names if n.startswith(f"{form_id}_") and n.endswith(".parquet")
    )
    if not partition_names:
        return False

    partition_dir = _partition_dir(form_id)
    partition_dir.mkdir(parents=True, exist_ok=True)

    for name in partition_names:
        ok = sp.download_file(token, drive_id, f"{remote_folder}/{name}", partition_dir / name)
        if not ok:
            detail(
                f"[sharepoint] Form {form_id} | Partition recovery failed downloading "
                f"{name} -- falling back to full local migration."
            )
            return False

    marker_ok = sp.download_file(
        token, drive_id, f"{remote_folder}/{marker_name}", partition_dir / marker_name
    )
    if not marker_ok:
        detail(
            f"[sharepoint] Form {form_id} | Partition recovery failed downloading the "
            f"completion marker -- falling back to full local migration."
        )
        return False

    detail(
        f"[sharepoint] Form {form_id} | Recovered {len(partition_names)} year partition(s) "
        f"+ completion marker from SharePoint -- skipping local migration."
    )
    return True


def _clear_stale_partitions(form_id: int) -> None:
    """Remove a form's entire year-partition directory (including the
    completion marker), both locally AND on SharePoint, after a FULL
    fetch has just overwritten its combined Parquet file directly (see
    save_to_parquet()). A full fetch bypasses save_incremental() /
    _save_incremental_partitioned() entirely, so any partition files
    left over from before it now describe data that no longer matches
    the fresh combined file -- if left in place, the next incremental
    run would see _is_form_partitioned() return True (locally) or
    _recover_partitions_from_sharepoint() succeed (from SharePoint), and
    merge new data into (then recombine from) those now-STALE
    partitions, silently overwriting the fresh full-fetch data with an
    outdated reconstruction.

    The SharePoint half of this matters just as much as the local half:
    a full fetch commonly runs on a container with no local partition
    directory to begin with (nothing to clean up there), while
    SharePoint still has the last container's completed migration sitting
    in _sp_partition_folder(form_id) -- if only the local copy were
    cleared, the very next incremental run would happily "recover" that
    stale SharePoint copy right back, defeating the point entirely. Both
    sides are cleared unconditionally (not gated on the other existing)
    so either one being stale on its own still gets caught.

    Removing the whole directory/folder (not just the marker) on both
    sides means the next incremental run (if the form is still over
    _PARTITION_ROW_THRESHOLD) correctly re-migrates from the fresh
    combined file instead."""
    partition_dir = _partition_dir(form_id)
    if partition_dir.is_dir():
        try:
            shutil.rmtree(partition_dir)
        except Exception as e:
            detail(f"[WARNING] Form {form_id} | Could not remove stale local partition directory: {e}")

    token, drive_id = _get_sp_session()
    if token:
        if sp.delete_item(token, drive_id, _sp_partition_folder(form_id)):
            detail(f"[sharepoint] Form {form_id} | Cleared stale partition folder on SharePoint (if any existed).")
        else:
            detail(f"[sharepoint] Form {form_id} | WARNING: could not clear stale partition folder on SharePoint.")


def _submission_year(value) -> str:
    """Extract a 4-digit calendar-year string from a _submission_time
    value, for use as a year-partition key. ONA/WHONgHub submission
    timestamps are ISO-8601 strings (e.g. "2024-05-01T12:34:56"), so the
    first 4 characters are the year -- no need for a full datetime parse.

    Returns "0000" as a defensive fallback for missing/malformed values
    (None, blank, or anything that doesn't start with 4 digits) instead
    of raising, so partitioning stays safe to apply to any form, not
    just ones known to always have a clean, complete timestamp."""
    if value is None:
        return "0000"
    text = str(value).strip()
    if len(text) >= 4 and text[:4].isdigit():
        return text[:4]
    return "0000"


def _write_partition_file(
    path: Path,
    df: pd.DataFrame,
    row_group_size: int = _PARTITION_ROW_GROUP_SIZE
) -> None:
    """Write one year-partition's DataFrame straight to Parquet, in
    small row groups (see _PARTITION_ROW_GROUP_SIZE) rather than
    whatever default row-group size pandas/pyarrow would otherwise
    pick. This matters for _recombine_year_partitions(), which reads
    each partition back ONE ROW GROUP AT A TIME to keep its own memory
    bounded -- Parquet can only skip decoding a row group it doesn't
    need, never decode PART of one, so a partition written as one giant
    row group would force recombine to hold the whole partition in
    memory anyway, defeating the point.

    No metadata JSON and no SharePoint upload here -- those only happen
    once, for the recombined whole-form file (see
    _recombine_year_partitions()); partition files are this pipeline's
    own internal storage detail, never read by the R scripts or anything
    else downstream."""
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(
        path, engine="pyarrow", compression="snappy", index=False,
        row_group_size=row_group_size
    )


def _merge_and_dedup(existing_df: pd.DataFrame, new_df: pd.DataFrame) -> pd.DataFrame:
    """Concatenate ``existing_df`` with newly-fetched records and
    de-duplicate by ``_id``, keeping the newly-fetched copy of any
    record seen in both. Shared by the plain single-file incremental
    merge (save_incremental()) and the per-year-partition merge
    (_save_incremental_partitioned()) so both get identical
    dtype-preserving fillna handling and the identical memory-safe
    drop-then-never-reset-index ordering that form 4498's original OOM
    crash was root-caused to.

    Raises (rather than returning None) on failure -- what "the merge
    failed" should mean is different for each caller (fall back to a
    full fetch for the single-file path; treat one year's partition as
    failed for the partitioned path), so this leaves that decision to
    the caller instead of swallowing the exception itself.
    """
    if "_id" not in existing_df.columns or "_id" not in new_df.columns:
        raise ValueError("No _id column available -- cannot safely de-duplicate merge.")

    # Reconcile categorical columns to a SHARED set of categories before
    # concatenating. pd.concat() only keeps a column as Categorical dtype
    # when both sides' CategoricalDtype are EXACTLY equal (same categories,
    # same order) -- otherwise it silently falls back to plain 'object'
    # dtype for that column. new_df is built from just the newly-fetched
    # handful of records, so its per-column category set is almost never
    # identical to existing_df's (which has accumulated every distinct
    # value ever seen for that column) -- meaning, before this fix, EVERY
    # incremental merge silently expanded nearly every categorical column
    # in existing_df back to full per-row Python strings for the duration
    # of this function, undoing build_dataframe_from_records()'s /
    # _read_parquet_low_memory()'s categorical compression entirely.
    #
    # Measured directly against form 5710's real data (694 columns,
    # 106,079 rows): existing_df is ~157 MB deep-memory as read, but the
    # concat below (unpatched) produced a ~3.7 GB combined DataFrame -- 619
    # of 694 columns silently degraded from category to object, landing
    # almost exactly on what a fully un-optimized DataFrame of this shape
    # needs (see build_dataframe_from_records()'s own docstring on form
    # 4498's ~44 GB unoptimized figure, scaled down to this form's
    # column/row count). This is very likely what has been OOM-killing
    # form 5710's fetch step (exit 137) on Connect Cloud's tighter memory
    # ceiling: not the full fetch, but every single incremental merge --
    # and the same silent blowup happens for every other form's
    # incremental merges too, just usually staying under whatever memory
    # ceiling is available.
    #
    # union_categoricals() computes the union of both sides' categories
    # once, cheaply; giving both existing_df and new_df that SAME
    # CategoricalDtype before pd.concat() means pd.concat() sees matching
    # dtypes and keeps the result Categorical directly, without ever
    # materializing an expanded object array in the first place -- this
    # avoids the transient memory spike entirely, not just the combined
    # DataFrame's final resting size.
    for col in existing_df.columns:
        if col not in new_df.columns:
            continue
        if isinstance(existing_df[col].dtype, pd.CategoricalDtype) and isinstance(new_df[col].dtype, pd.CategoricalDtype):
            unioned = pd.api.types.union_categoricals(
                [existing_df[col].values, new_df[col].values], sort_categories=False
            )
            shared_categories = unioned.categories
            existing_df[col] = existing_df[col].cat.set_categories(shared_categories)
            new_df[col] = new_df[col].cat.set_categories(shared_categories)

    combined = pd.concat([existing_df, new_df], ignore_index=True, sort=False)
    # existing_df can be tens of MB on disk and several times that once
    # loaded as a DataFrame -- free it now rather than holding it (plus
    # new_df, plus combined) all alive at once through what comes next.
    del existing_df

    # Column-by-column, NOT combined.fillna("").astype(str) on the whole
    # table: that whole-table version is exactly what crashed the
    # 2026-08-22 run on form 4498 (see build_dataframe_from_records()'s
    # own comment on this) -- pandas' whole-table fillna makes a
    # defensive copy of the ENTIRE block before filling anything in it,
    # which for a wide, long form needs gigabytes on top of what's
    # already resident.
    for col in combined.columns:
        series = combined[col]
        if isinstance(series.dtype, pd.CategoricalDtype):
            if series.isna().any():
                if "" not in series.cat.categories:
                    series = series.cat.add_categories([""])
                series = series.fillna("")
            combined[col] = series
        elif isinstance(series.dtype, pd.ArrowDtype):
            if series.isna().any():
                series = series.fillna("")
            combined[col] = series
        else:
            if series.isna().any():
                series = series.fillna("")
            combined[col] = series.astype(str)

    # NOT chained as .drop_duplicates(...).reset_index(...) -- in that
    # form, Python has to finish evaluating the whole right-hand side
    # before the assignment takes effect, so the pre-dedup `combined`,
    # the deduplicated copy, AND the reset-index copy can all be alive
    # at once (up to 3x a wide form's memory). Assigning after
    # drop_duplicates alone lets the pre-dedup copy be freed
    # immediately. reset_index(drop=True) is skipped entirely: every
    # caller of this function eventually writes its result via
    # to_parquet(..., index=False), which never reads the index's
    # values.
    combined = combined.drop_duplicates(subset=["_id"], keep="last")

    return combined


def _split_into_year_partitions(form_id: int, source_path: Path) -> Dict[str, int]:
    """One-time migration: split an existing single-file form Parquet
    into per-calendar-year partition files under _partition_dir(form_id).

    Processes ONE YEAR AT A TIME: for each year, reads every column of
    the SOURCE file fully, keeps only that year's rows, writes them out,
    then discards everything before moving to the next year. This
    re-reads the source file once per year (N years x every column,
    instead of every column once) -- trading extra TIME for a much
    lower memory ceiling, since the data retained in memory at any
    moment is bounded to the LARGEST SINGLE YEAR's rows, not the form's
    entire history.

    That trade matters in practice, not just in theory: an earlier
    version of this function built ALL years' DataFrames simultaneously
    in a single pass (bounded time, ~2.2-2.4GB peak on its own) and that
    peak, stacked on top of an already-busy parent process that had just
    handled 11 other forms before reaching this one, was enough to get
    this migration OOM-killed on Connect Cloud even running alone in an
    isolated subprocess -- the isolated subprocess shares the SAME
    memory cgroup as its parent, so "isolated" bounds the BLAST RADIUS
    of a crash, not the actual memory ceiling available to it. A
    migration only has to happen once per form, so paying a few extra
    minutes here to stay well under memory pressure is the right trade.

    Why not filters=[("_submission_time", ...)] to only read one year's
    rows per pass, instead of reading everything and masking in memory?
    See the NOTE in _read_parquet_low_memory()'s own docstring --
    Parquet's predicate pushdown can only skip whole row groups, and
    form 4498's file has only 2 of them, one holding almost all the
    data, so a filtered read still decodes nearly everything anyway.
    Masking in memory after an unfiltered read at least bounds the cost
    to one column at a time, regardless of which year it ends up in.

    The partition directory is wiped clean before writing anything, in
    case a previous attempt crashed partway through and left stale or
    partial files behind, and a completion marker is written only after
    EVERY year has been written successfully -- see
    _is_form_partitioned()'s docstring for why that matters.
    """
    pf = pq.ParquetFile(source_path)
    columns = [f.name for f in pf.schema_arrow]

    if "_submission_time" not in columns:
        raise ValueError(
            f"Form {form_id}: source Parquet has no _submission_time column -- cannot partition by year."
        )

    partition_dir = _partition_dir(form_id)
    if partition_dir.exists():
        shutil.rmtree(partition_dir)
    partition_dir.mkdir(parents=True, exist_ok=True)

    # Single read of the year key column; every per-year pass below
    # reuses this SAME precomputed Series rather than re-deriving years
    # from a fresh read each time.
    year_table = pq.read_table(source_path, columns=["_submission_time"], use_threads=False)
    submission_times = year_table.column(0).to_pylist()
    del year_table

    years = pd.Series([_submission_year(v) for v in submission_times], dtype="object")
    del submission_times

    unique_years = sorted(years.unique().tolist())
    row_counts: Dict[str, int] = {}

    for yr in unique_years:
        mask = (years == yr).to_numpy()
        n_rows_yr = int(mask.sum())
        row_counts[yr] = n_rows_yr

        part_df = pd.DataFrame(index=pd.RangeIndex(n_rows_yr))

        for col in columns:
            low_cardinality = not _is_high_cardinality_field(col)
            read_dictionary = [col] if low_cardinality else None

            table = pq.read_table(
                source_path, columns=[col], read_dictionary=read_dictionary, use_threads=False
            )

            if low_cardinality:
                series = table.column(0).to_pandas()
                series = series.astype("category")
            else:
                series = table.column(0).to_pandas(types_mapper=pd.ArrowDtype)

            year_series = series[mask]
            year_series.index = part_df.index
            part_df[col] = year_series
            del table, series, year_series

        _write_partition_file(_partition_path(form_id, yr), part_df)
        del part_df
        gc.collect()
        pa.default_memory_pool().release_unused()

    _migration_marker_path(form_id).write_text(datetime.now().isoformat())

    return row_counts


def _recombine_year_partitions(
    form_id: int,
    previous_metadata: Dict,
    new_records_this_run: int = 0
) -> Optional[Dict]:
    """Stream every year-partition file for a form back into one combined
    {form_id}.parquet -- the file every other consumer of this pipeline
    (the R scripts, SharePoint, decide_fetch_mode() on the next run)
    expects to find; partitioning is an internal storage detail, not a
    change to this pipeline's external contract.

    Reads each partition ONE ROW GROUP AT A TIME via
    pq.ParquetFile.read_row_group() -- never the whole partition file at
    once -- and casts each row group's columns to plain pa.string() at
    the Arrow level via ``.cast()``, through a shared pq.ParquetWriter.
    This bounds peak memory here to roughly one row group's worth of
    data (see _PARTITION_ROW_GROUP_SIZE / _write_partition_file(), which
    is what keeps partition files' row groups small enough for this to
    actually work), regardless of how large any individual partition or
    the form's total history grows.

    Two earlier versions of this function both got this wrong in ways
    worth remembering: the first read each partition via
    _read_parquet_low_memory() into a pandas DataFrame and called
    pandas' ``.astype(str)`` on every column, which re-triggered the
    exact memory blowup this whole file's history is about (pandas'
    plain string/object dtype boxes every value as its own Python
    object). The second fixed that by casting at the Arrow level instead
    -- correct, but still read each partition's ENTIRE file as one
    pa.Table before casting, so its peak scaled with the largest
    partition's total size (~2.7GB for form 4498's ~400k-row 2024
    partition) rather than with a fixed row-group size; combined with
    the one-time migration's own peak in the same process, that was
    still enough to get OOM-killed on Connect Cloud. Reading row group
    by row group removes that scaling entirely.

    Every partition's columns are reindexed onto the union of all
    partitions' columns (filling any column absent from a given
    partition with an empty-string array) and unconditionally cast to
    pa.string(), because pq.ParquetWriter requires every write_table()
    call to share one identical schema, while partitions can
    legitimately drift in schema over time (a form gains a new
    question, or one year's column ends up dictionary-encoded with a
    different index width than another's). This costs the same "no
    compact dtype in the combined file" trade the pipeline already
    makes everywhere the combined file is read back in via
    _read_parquet_low_memory(), which re-derives category/ArrowDtype
    from the plain Parquet values on its own anyway.
    """
    partition_dir = _partition_dir(form_id)
    partition_paths = sorted(partition_dir.glob(f"{form_id}_*.parquet"))

    if not partition_paths:
        detail(f"[WARNING] Form {form_id} | No partition files found to recombine.")
        return None

    all_columns: List[str] = []
    seen = set()
    for p in partition_paths:
        for name in pq.ParquetFile(p).schema_arrow.names:
            if name not in seen:
                seen.add(name)
                all_columns.append(name)

    output_path = RAW_DIR / f"{form_id}.parquet"
    tmp_output_path = RAW_DIR / f"{form_id}.parquet.tmp"
    arrow_schema = pa.schema([(name, pa.string()) for name in all_columns])

    total_rows = 0
    last_submission_time = previous_metadata.get("last_submission_time")
    writer = None

    try:
        writer = pq.ParquetWriter(tmp_output_path, arrow_schema, compression="snappy")

        for p in partition_paths:
            pf = pq.ParquetFile(p)

            for rg_idx in range(pf.num_row_groups):
                table = pf.read_row_group(rg_idx)
                n_rows = table.num_rows

                arrays = []
                for col in all_columns:
                    if col in table.column_names:
                        arr = table.column(col)
                        if not (pa.types.is_string(arr.type) or pa.types.is_large_string(arr.type)):
                            arr = arr.cast(pa.string())
                        arr = pc.fill_null(arr, "")
                    else:
                        arr = pa.chunked_array([pa.array([""] * n_rows, type=pa.string())])
                    arrays.append(arr)

                out_table = pa.Table.from_arrays(arrays, schema=arrow_schema)
                writer.write_table(out_table)

                total_rows += n_rows

                if "_submission_time" in table.column_names:
                    st_column = table.column("_submission_time")
                    st_values = [v for v in st_column.to_pylist() if v]
                    if st_values:
                        part_max = max(str(v) for v in st_values)
                        candidates = [t for t in [part_max, last_submission_time] if t]
                        last_submission_time = max(candidates) if candidates else last_submission_time

                del table, arrays, out_table

            gc.collect()
            pa.default_memory_pool().release_unused()

        writer.close()
        writer = None

        tmp_output_path.replace(output_path)

    except Exception as e:
        if writer is not None:
            try:
                writer.close()
            except Exception:
                pass
        detail(f"[WARNING] Form {form_id} | Recombine of year partitions failed: {e}")
        return None

    file_size_mb = output_path.stat().st_size / (1024 * 1024)

    metadata = {
        "workflow": "Independent Monitoring IM",
        "form_id": form_id,
        "records": int(total_rows),
        "columns": int(len(all_columns)),
        "parquet_size_mb": round(file_size_mb, 2),
        "estimated_memory_size_mb": None,
        "compression_ratio": None,
        "last_fetch": datetime.now().isoformat(),
        "shape": f"{total_rows}x{len(all_columns)}",
        "format": "parquet",
        "engine": "pyarrow",
        "output_path": str(output_path),
        "fetch_mode": "incremental_partitioned",
        "last_full_fetch": previous_metadata.get("last_full_fetch"),
        "last_submission_time": last_submission_time,
        "new_records_this_run": int(new_records_this_run),
        "fetch_complete": True,
        "partitioned": True,
        "partition_years": [p.stem.split("_")[-1] for p in partition_paths],
    }

    metadata_path = RAW_DIR / f"{form_id}_metadata.json"
    with open(metadata_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)

    detail(
        f"[SAVED] Form {form_id}: {total_rows:,} rows | {file_size_mb:.2f} MB | "
        f"{len(all_columns):,} columns | mode=incremental_partitioned "
        f"({len(partition_paths)} year partition(s))"
    )

    upload_raw_to_sharepoint(form_id)
    _upload_partitions_to_sharepoint(form_id)

    return metadata


def _save_incremental_partitioned(
    form_id: int,
    new_data: List[Dict],
    previous_metadata: Dict
) -> Optional[Dict]:
    """Incremental-merge path for a form stored as per-year partitions
    instead of one combined Parquet file (see _is_form_partitioned() /
    _PARTITION_ROW_THRESHOLD).

    Migrates the form to partitioned storage the first time it's called
    for a form that has grown past the threshold but isn't partitioned
    yet, then merges each year's worth of ``new_data`` into just that
    year's (small) partition file -- an ordinary run only ever holds one
    year's data in memory, never the form's full history, because new
    submissions almost always land in the current year's partition.
    Finally streams every partition back into one combined
    {form_id}.parquet (see _recombine_year_partitions()) so this
    pipeline's external file layout never changes.
    """
    existing_path = RAW_DIR / f"{form_id}.parquet"

    if not _is_form_partitioned(form_id) and not _recover_partitions_from_sharepoint(form_id):
        detail(
            f"Form {form_id} | Existing data has grown past the "
            f"{_PARTITION_ROW_THRESHOLD:,}-row safety threshold -- migrating "
            f"to year-partitioned storage before merging this run's new data."
        )
        try:
            row_counts = _split_into_year_partitions(form_id, existing_path)
        except Exception as e:
            detail(f"[WARNING] Form {form_id} | Year-partition migration failed: {e}")
            return None
        detail(f"Form {form_id} | Migrated to year partitions: {row_counts}")

    new_df = build_dataframe_from_records(new_data)

    if "_id" not in new_df.columns:
        detail(f"[WARNING] Form {form_id} | No _id column available in new data -- cannot safely de-duplicate merge.")
        return None

    if "_submission_time" not in new_df.columns:
        detail(f"[WARNING] Form {form_id} | No _submission_time column in new data -- cannot route to a year partition.")
        return None

    new_df["_partition_year"] = new_df["_submission_time"].astype(str).map(_submission_year)

    for year, year_new_df in new_df.groupby("_partition_year", observed=True):
        year_new_df = year_new_df.drop(columns=["_partition_year"])
        partition_path = _partition_path(form_id, year)

        if partition_path.exists():
            try:
                partition_existing_df = _read_parquet_low_memory(partition_path)
            except Exception as e:
                detail(f"[WARNING] Form {form_id} | Could not read partition {partition_path.name} for merge: {e}")
                return None

            try:
                merged = _merge_and_dedup(partition_existing_df, year_new_df)
            except Exception as e:
                detail(f"[WARNING] Form {form_id} | Merge/de-duplication failed for partition {partition_path.name}: {e}")
                return None
        else:
            merged = year_new_df

        try:
            _write_partition_file(partition_path, merged)
        except Exception as e:
            detail(f"[WARNING] Form {form_id} | Could not write partition {partition_path.name}: {e}")
            return None

        del merged
        gc.collect()

    return _recombine_year_partitions(form_id, previous_metadata, new_records_this_run=len(new_data))


def touch_metadata_checked(form_id: int, previous_metadata: Dict) -> Dict:
    """Incremental fetch found 0 new records — leave the Parquet file
    untouched and just update the metadata's last_fetch timestamp so the
    log/UI can show the form was checked, not skipped outright."""
    metadata = dict(previous_metadata)
    metadata["last_fetch"] = datetime.now().isoformat()
    metadata["fetch_mode"] = "incremental_no_new_records"
    metadata.setdefault("new_records_this_run", 0)
    metadata["new_records_this_run"] = 0

    metadata_path = RAW_DIR / f"{form_id}_metadata.json"

    try:
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)
    except Exception as e:
        detail(f"[WARNING] Form {form_id} | Could not update metadata after incremental check: {e}")

    return metadata


def load_form_ids(config_path: str = None) -> List[int]:
    """
    Load IM form IDs from a YAML/JSON config file if provided.
    Otherwise use DEFAULT_IM_FORM_IDS.
    """
    if config_path:
        config_file = Path(config_path)

        if config_file.exists():
            try:
                if config_file.suffix.lower() in [".yaml", ".yml"]:
                    import yaml

                    with open(config_file, "r", encoding="utf-8") as f:
                        config = yaml.safe_load(f)

                elif config_file.suffix.lower() == ".json":
                    with open(config_file, "r", encoding="utf-8") as f:
                        config = json.load(f)

                else:
                    detail(f"[WARNING] Unsupported config format: {config_file.suffix}")
                    return DEFAULT_IM_FORM_IDS

                form_ids = (
                    config.get("im", {}).get("form_ids", [])
                    or config.get("ona", {}).get("forms", {}).get("im", [])
                    or config.get("ona", {}).get("form_ids", [])
                    or config.get("form_ids", [])
                )

                if form_ids:
                    return [int(x) for x in form_ids]

                detail("[WARNING] No IM form IDs found in config file.")

            except Exception as e:
                detail(f"[WARNING] Error loading config: {e}")

    return DEFAULT_IM_FORM_IDS


def test_api_connection() -> bool:
    """Test API connection and authentication."""
    headers = get_auth_headers()

    if not headers:
        console("❌ Missing ONA_API_TOKEN.")
        return False

    try:
        response = requests.get(
            USER_URL,
            headers=headers,
            timeout=30
        )

        if response.status_code == 200:
            console("✅ API connection successful")
            return True

        console(f"❌ API connection failed: HTTP {response.status_code}")
        return False

    except Exception as e:
        console(f"❌ API connection error: {e}")
        return False


def write_fetch_summary(summary: Dict) -> None:
    """Write fetch summary to JSON."""
    create_workflow_folders()

    summary_path = RAW_DIR / "fetch_summary.json"

    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    detail(f"Summary saved to: {summary_path}")


def _append_csv_row(csv_path: Path, fieldnames: List[str], row: Dict) -> None:
    """Append one row to a CSV file, writing the header only if the file is
    new. Never raises -- a logging problem must not fail the actual fetch."""
    try:
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        write_header = not csv_path.exists()
        with open(csv_path, "a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            if write_header:
                writer.writeheader()
            writer.writerow(row)
    except Exception as e:
        detail(f"Could not append to {csv_path}: {e!r}")


def append_fetch_history(summary: Dict) -> None:
    """Append this run's summary to logs/fetch_run_history.csv (one row per
    fetch run) and logs/fetch_form_history.csv (one row per form per run).

    write_fetch_summary() above overwrites data/raw/fetch_summary.json every
    run, so only the LAST run is ever visible there -- these two CSVs
    accumulate instead, so trends across runs (a form that's been stuck at
    0 records for weeks, or keeps coming back "incomplete") are visible
    without digging through old console logs.
    """
    run_history_path = LOGS_DIR / "fetch_run_history.csv"
    run_fields = [
        "run_id", "timestamp", "forms_total", "full_fetches",
        "incremental_fetches", "checked_no_new", "successful", "failed",
        "incomplete", "exceptions", "total_records_fetched_this_run",
        "total_records_available_or_fetched", "total_size_mb_this_run",
    ]
    _append_csv_row(run_history_path, run_fields, {
        "run_id": RUN_ID,
        "timestamp": summary["timestamp"],
        "forms_total": summary["forms_total"],
        "full_fetches": summary["full_fetches"],
        "incremental_fetches": summary["incremental_fetches"],
        "checked_no_new": summary["checked_no_new"],
        "successful": summary["successful"],
        "failed": summary["failed"],
        "incomplete": sum(1 for r in summary["results"] if r["status"] == "failed_incomplete"),
        "exceptions": sum(1 for r in summary["results"] if r["status"] == "failed_exception"),
        "total_records_fetched_this_run": summary["total_records_fetched_this_run"],
        "total_records_available_or_fetched": summary["total_records_available_or_fetched"],
        "total_size_mb_this_run": summary["total_size_mb_this_run"],
    })

    form_history_path = LOGS_DIR / "fetch_form_history.csv"
    form_fields = ["run_id", "timestamp", "form_id", "status", "records", "new_records", "size_mb"]
    for r in summary["results"]:
        _append_csv_row(form_history_path, form_fields, {
            "run_id": RUN_ID,
            "timestamp": summary["timestamp"],
            "form_id": r.get("form_id", ""),
            "status": r.get("status", ""),
            "records": r.get("records", 0),
            "new_records": r.get("new_records", 0),
            "size_mb": r.get("size_mb", 0),
        })

    detail(f"Run history appended to: {run_history_path} and {form_history_path}")


def print_created_files_preview() -> None:
    """Print compact preview of available Parquet files."""
    parquet_files = sorted(list(RAW_DIR.glob("*.parquet")))

    if not parquet_files:
        return

    console("")
    console(f"📁 Available Parquet files: {len(parquet_files)}")

    for file in parquet_files[:8]:
        size_mb = file.stat().st_size / (1024 * 1024)
        console(f"   - {file.name} ({size_mb:.2f} MB)")

    if len(parquet_files) > 8:
        console(f"   ... and {len(parquet_files) - 8} more")


# ============================================================
# MAIN
# ============================================================

def decide_fetch_mode(
    form_id: int,
    output_path: Path,
    force_full: bool,
    full_refresh_days: float
):
    """Decide whether a form should get a FULL or INCREMENTAL fetch this run.

    Returns (mode, previous_metadata_or_None, reason_str). ``mode`` is
    "full" or "incremental". ``previous_metadata`` is the parsed metadata
    JSON when it exists and mode is "incremental" (or when mode is "full"
    because the metadata was legacy/stale rather than missing).
    """
    if force_full:
        return "full", None, "--force-full requested"

    if not output_path.exists():
        return "full", None, "no local copy yet"

    metadata_path = RAW_DIR / f"{form_id}_metadata.json"
    previous_metadata = None

    if metadata_path.exists():
        try:
            with open(metadata_path, "r", encoding="utf-8") as f:
                previous_metadata = json.load(f)
        except Exception:
            previous_metadata = None

    if not previous_metadata:
        return "full", None, "metadata file missing or unreadable"

    if previous_metadata.get("fetch_complete") is False:
        # A previous full fetch gave up mid-way after a page kept failing
        # (see fetch_page's retry/None handling). Its last_submission_time
        # cannot be trusted as an incremental cursor -- keep retrying a full
        # fetch until one completes cleanly.
        return (
            "full",
            previous_metadata,
            "previous full fetch was INCOMPLETE (page error after retries) -- "
            "retrying full fetch rather than trusting its cursor"
        )

    last_full_fetch = previous_metadata.get("last_full_fetch")
    last_submission_time = previous_metadata.get("last_submission_time")

    if not last_full_fetch or not last_submission_time:
        # Local copy predates the incremental-fetch feature — do one full
        # refresh so we have a trustworthy cursor to work from afterwards.
        return "full", previous_metadata, "legacy metadata (pre-incremental format)"

    parsed_full = _parse_iso_datetime(last_full_fetch)

    if parsed_full is None:
        return "full", previous_metadata, "last_full_fetch could not be parsed"

    age_days = (datetime.now() - parsed_full).total_seconds() / 86400.0

    if age_days > full_refresh_days:
        return (
            "full",
            previous_metadata,
            f"local copy's last full refresh was {age_days:.1f}d ago "
            f"(> --full-refresh-days {full_refresh_days})"
        )

    return (
        "incremental",
        previous_metadata,
        f"last full refresh {age_days:.1f}d ago, using cursor {last_submission_time}"
    )


def _fetch_parts_dir(form_id: int) -> Path:
    return RAW_DIR / f"{form_id}_fetch_parts"


def _fetch_part_path(form_id: int, page: int) -> Path:
    return _fetch_parts_dir(form_id) / f"{form_id}_page{page:05d}.parquet"


def _clear_stale_fetch_parts(form_id: int) -> None:
    """Remove any leftover per-page part files from a previous full-fetch
    attempt for this form that was killed partway through (OOM, network
    failure, container restart) before run_full_fetch() starts fetching
    fresh pages. Without this, a retry could combine this run's pages
    together with a previous, unrelated attempt's leftover pages (or
    stale pages from before the form's column set changed), producing a
    corrupted combined file. Never raises -- a part file that can't be
    removed is harmless leftover, not a reason to abort the fetch."""
    parts_dir = _fetch_parts_dir(form_id)

    if not parts_dir.exists():
        return

    for p in parts_dir.glob(f"{form_id}_page*.parquet"):
        try:
            p.unlink()
        except Exception:
            pass


def _write_fetch_page_part(form_id: int, page: int, page_df: pd.DataFrame, page_size: int) -> Path:
    """Cast one fetched page to the pipeline's standard all-string shape
    (GPS fields split out via extract_gps_components(), same as
    build_dataframe_from_records()) and write it immediately as its own
    small Parquet part file, deliberately WITHOUT category/dictionary
    encoding -- see _combine_fetch_parts_streaming()'s docstring for why
    the final combine also stays plain-string, matching the precedent
    _recombine_year_partitions() already established.

    Writing with a row-group size no larger than this page's own row
    count means every part file this run produces is exactly one row
    group, which is what keeps _combine_fetch_parts_streaming()'s own
    memory bounded to one page at a time regardless of how large
    --page-size is set to.
    """
    for col in page_df.columns:
        series = page_df[col]
        if series.isna().any():
            series = series.fillna("")
        page_df[col] = series.astype(str)

    page_df = extract_gps_components(page_df)

    path = _fetch_part_path(form_id, page)
    _write_partition_file(path, page_df, row_group_size=min(page_size, _PARTITION_ROW_GROUP_SIZE))
    return path


def _combine_fetch_parts_streaming(form_id: int, part_paths: List[Path]) -> Optional[Dict]:
    """Stream every per-page part file a full fetch just wrote (see
    _write_fetch_page_part()) into one combined {form_id}.parquet -- the
    file every other consumer of this pipeline (the R scripts,
    SharePoint, decide_fetch_mode() on the next run) expects to find.

    This is the SAME row-group-bounded streaming pattern
    _recombine_year_partitions() already uses for incremental-partitioned
    forms (see that function's docstring for the full history of why it's
    shaped this way): read each part ONE ROW GROUP AT A TIME via
    pq.ParquetFile.read_row_group(), reindex onto the union of every
    part's columns (filling any column absent from a given part with an
    empty-string array), cast everything to plain pa.string() through a
    single shared pq.ParquetWriter, and rename into place atomically only
    on full success. Peak memory here scales with one row group (one
    page), never with the form's total size -- this is what lets a form
    as large as 4498 (822 columns x ~1.15M rows) complete a full fetch at
    all, where accumulating one combined in-memory DataFrame across every
    page (the previous approach) could not.

    Plain string output (no dictionary/category encoding) is the same
    trade _recombine_year_partitions() makes and for the same reason:
    pq.ParquetWriter requires one identical schema across every
    write_table() call, while different pages can legitimately end up
    with differently-sized dictionaries (or, for a rarely-answered
    question, be entirely missing a column another page has) --
    downstream consumers (_read_parquet_low_memory()) already re-derive
    category/ArrowDtype from plain Parquet values on read, so nothing is
    lost by writing plain strings here.
    """
    if not part_paths:
        detail(f"[WARNING] Form {form_id} | No fetch part files found to combine.")
        return None

    all_columns: List[str] = []
    seen = set()
    for p in part_paths:
        for name in pq.ParquetFile(p).schema_arrow.names:
            if name not in seen:
                seen.add(name)
                all_columns.append(name)

    output_path = RAW_DIR / f"{form_id}.parquet"
    tmp_output_path = RAW_DIR / f"{form_id}.parquet.tmp"
    arrow_schema = pa.schema([(name, pa.string()) for name in all_columns])

    total_rows = 0
    last_submission_time = None
    writer = None

    try:
        writer = pq.ParquetWriter(tmp_output_path, arrow_schema, compression="snappy")

        for p in part_paths:
            pf = pq.ParquetFile(p)

            for rg_idx in range(pf.num_row_groups):
                table = pf.read_row_group(rg_idx)
                n_rows = table.num_rows

                arrays = []
                for col in all_columns:
                    if col in table.column_names:
                        arr = table.column(col)
                        if not (pa.types.is_string(arr.type) or pa.types.is_large_string(arr.type)):
                            arr = arr.cast(pa.string())
                        arr = pc.fill_null(arr, "")
                    else:
                        arr = pa.chunked_array([pa.array([""] * n_rows, type=pa.string())])
                    arrays.append(arr)

                out_table = pa.Table.from_arrays(arrays, schema=arrow_schema)
                writer.write_table(out_table)

                total_rows += n_rows

                if "_submission_time" in table.column_names:
                    st_column = table.column("_submission_time")
                    st_values = [v for v in st_column.to_pylist() if v]
                    if st_values:
                        part_max = max(str(v) for v in st_values)
                        candidates = [t for t in [part_max, last_submission_time] if t]
                        last_submission_time = max(candidates) if candidates else last_submission_time

                del table, arrays, out_table

            gc.collect()
            pa.default_memory_pool().release_unused()

        writer.close()
        writer = None

        tmp_output_path.replace(output_path)

    except Exception as e:
        if writer is not None:
            try:
                writer.close()
            except Exception:
                pass
        detail(f"[WARNING] Form {form_id} | Combine of fetch page parts failed: {e}")
        return None

    file_size_mb = output_path.stat().st_size / (1024 * 1024)
    now_iso = datetime.now().isoformat()

    metadata = {
        "workflow": "Independent Monitoring IM",
        "form_id": form_id,
        "records": int(total_rows),
        "columns": int(len(all_columns)),
        "parquet_size_mb": round(file_size_mb, 2),
        "estimated_memory_size_mb": None,
        "compression_ratio": None,
        "last_fetch": now_iso,
        "shape": f"{total_rows}x{len(all_columns)}",
        "format": "parquet",
        "engine": "pyarrow",
        "output_path": str(output_path),
        "fetch_mode": "full",
        "last_full_fetch": now_iso,
        "last_submission_time": last_submission_time,
        "fetch_complete": True,
    }

    metadata_path = RAW_DIR / f"{form_id}_metadata.json"
    with open(metadata_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)

    detail(
        f"[SAVED] Form {form_id}: {total_rows:,} rows | {file_size_mb:.2f} MB | "
        f"{len(all_columns):,} columns | mode=full ({len(part_paths)} page part(s))"
    )

    upload_raw_to_sharepoint(form_id)

    return metadata


def run_full_fetch(form_id: int, i: int, total_forms: int, page_size: int) -> Dict:
    """Perform a full fetch + full overwrite save for one form. Returns a
    results-row dict for the run summary.

    Fetches and writes one page at a time straight to its own small
    Parquet part file (see _write_fetch_page_part()), then combines all
    parts into the final {form_id}.parquet via a row-group-bounded
    streaming combine (see _combine_fetch_parts_streaming()) -- never
    accumulating more than one page's DataFrame in memory at once.

    This replaces the previous fetch_all_data()-based path (accumulate
    every page's DataFrame, pd.concat() them all once, then
    build_dataframe_from_records() casts/category-encodes the WHOLE
    combined DataFrame). That fix was a real, confirmed improvement for
    most forms (form 5710: peak RSS fell from ~4.8-5.3 GB to 1,554 MB in
    production), but still peaks in the multi-GB range for the
    pipeline's widest/largest forms, because it still builds one
    in-memory DataFrame covering the form's ENTIRE row/column extent
    before it can be written or category-encoded. Confirmed in
    production: form 4498 (822 columns x ~1.15M rows historically) was
    still OOM-killed (exit 137) at page 55 of ~113 needed even with that
    fix in place. Writing straight to disk page-by-page removes that
    ceiling entirely -- peak memory here scales with one page, never
    with the form's total size.

    fetch_all_data() and the List[Dict]/DataFrame-input branch of
    build_dataframe_from_records() are left defined but unused by this
    function (matching the precedent of save_to_parquet() being left
    unused after the very first fix in this file's history) -- nothing
    else in the repo calls fetch_all_data().
    """
    output_path = RAW_DIR / f"{form_id}.parquet"
    parts_dir = _fetch_parts_dir(form_id)

    # A previous full-fetch attempt for this form may have been killed
    # partway through (OOM, network failure, container restart), leaving
    # stale page parts behind -- never combine those together with this
    # attempt's fresh pages.
    _clear_stale_fetch_parts(form_id)

    part_paths: List[Path] = []
    total_records = 0
    page = 1
    fetch_complete = True

    console(f"📦 Form {form_id} ({i}/{total_forms}) | FULL fetch")
    detail(f"[FETCH:FULL] Form {form_id}")

    while True:
        live_line(
            f"   ⏳ Fetching page {page} | Records so far: {total_records:,}"
        )

        page_records = fetch_page(form_id, page, page_size)

        if page_records is None:
            clear_live_line()
            detail(f"Form {form_id} | Page {page} | Giving up -- fetch marked INCOMPLETE.")
            fetch_complete = False
            break

        if not page_records:
            clear_live_line()
            detail(f"Form {form_id} | Page {page} | No data returned.")
            break

        flattened_page = [flatten_dict(record) for record in page_records]
        page_df = pd.DataFrame(flattened_page)
        del page_records, flattened_page

        page_len = len(page_df)
        part_path = _write_fetch_page_part(form_id, page, page_df, page_size)
        del page_df
        part_paths.append(part_path)
        total_records += page_len

        detail(
            f"Form {form_id} | Page {page} | Retrieved {page_len:,} records | "
            f"Running total: {total_records:,}"
        )

        live_line(
            f"   ⏳ Page {page} complete | Records so far: {total_records:,}"
        )

        if page_len < page_size:
            clear_live_line()
            break

        page += 1
        gc.collect()
        pa.default_memory_pool().release_unused()
        time.sleep(0.5)

    detail(f"[DONE] Form {form_id}: {total_records:,} total records | complete={fetch_complete}")

    if not fetch_complete:
        # A page failed after retries partway through the fetch. Never
        # overwrite the existing (possibly larger, definitely more trusted)
        # Parquet file with this partial result -- just flag the metadata so
        # decide_fetch_mode retries a full fetch again next run, and leave
        # the data file exactly as it was. The partial pages already
        # written to disk are discarded, not combined.
        console(
            f"   ⚠️  Form {form_id} | Full fetch INCOMPLETE ({total_records:,} row(s) retrieved "
            f"before giving up) -- keeping the PREVIOUS {form_id}.parquet untouched. "
            f"Will retry a full fetch again next run."
        )
        detail(f"Form {form_id} | Full fetch incomplete -- existing data left untouched.")

        for p in part_paths:
            try:
                p.unlink()
            except Exception:
                pass

        metadata_path = RAW_DIR / f"{form_id}_metadata.json"
        prior_metadata = {}

        if metadata_path.exists():
            try:
                with open(metadata_path, "r", encoding="utf-8") as f:
                    prior_metadata = json.load(f)
            except Exception:
                prior_metadata = {}

        prior_metadata["fetch_complete"] = False
        prior_metadata["last_full_fetch_attempt"] = datetime.now().isoformat()
        prior_metadata["last_full_fetch_attempt_rows_retrieved"] = total_records

        try:
            create_workflow_folders()
            with open(metadata_path, "w", encoding="utf-8") as f:
                json.dump(prior_metadata, f, indent=2, ensure_ascii=False)
        except Exception as e:
            detail(f"Form {form_id} | Could not record incomplete-fetch flag: {e}")

        return {
            "form_id": form_id, "status": "failed_incomplete",
            "records": prior_metadata.get("records", 0), "new_records": 0,
            "size_mb": round(output_path.stat().st_size / (1024 * 1024), 2)
                if output_path.exists() else 0,
            "path": str(output_path)
        }

    if not part_paths:
        console(f"   ⚠️  No data fetched for form {form_id}")
        return {
            "form_id": form_id, "status": "failed_no_data",
            "records": 0, "new_records": 0, "size_mb": 0, "path": str(output_path)
        }

    console(f"   ✅ Fetch complete: {total_records:,} records across {page} page(s)")

    metadata = _combine_fetch_parts_streaming(form_id, part_paths)

    for p in part_paths:
        try:
            p.unlink()
        except Exception:
            pass

    try:
        if parts_dir.exists() and not any(parts_dir.iterdir()):
            parts_dir.rmdir()
    except Exception:
        pass

    if metadata is not None:
        # This full fetch just overwrote the combined file directly -- any
        # year-partition files left over from before it are now stale (see
        # _clear_stale_partitions()'s docstring for why that matters).
        _clear_stale_partitions(form_id)

    if not metadata:
        console(f"   ❌ Save failed for form {form_id}")
        return {
            "form_id": form_id, "status": "failed",
            "records": 0, "new_records": 0, "size_mb": 0, "path": str(output_path)
        }

    file_size = output_path.stat().st_size / (1024 * 1024)
    console(f"   💾 Saved: {form_id}.parquet | {total_records:,} rows | {file_size:.2f} MB")

    return {
        "form_id": form_id, "status": "full",
        "records": total_records, "new_records": total_records,
        "size_mb": round(file_size, 2), "path": str(output_path)
    }


def run_full_fetch_and_record(form_id, i, total_forms, page_size, results, total_records, total_size_mb):
    """run_full_fetch(), append its row to results, and roll its counts
    into the running (total_records, total_size_mb) totals. Used both for
    the normal full-fetch path and every incremental fallback path."""
    row = run_full_fetch(form_id, i, total_forms, page_size)
    results.append(row)

    if row["status"] == "full":
        total_records += row["new_records"]
        total_size_mb += row["size_mb"]

    return total_records, total_size_mb


def process_one_form(form_id, i, total_forms, args, results, total_records, total_size_mb):
    """Handle one form's fetch decision + execution for a single pass of the
    main loop. Returns the updated ``(total_records, total_size_mb)``.

    Split out from ``main()`` so the caller can wrap a single form's work in
    its own try/except -- an unhandled error here must only take out this
    one form, not every form still queued behind it in the run.
    """
    output_path = RAW_DIR / f"{form_id}.parquet"

    mode, previous_metadata, reason = decide_fetch_mode(
        form_id, output_path, args.force_full, args.full_refresh_days
    )
    detail(f"Form {form_id} | decided mode={mode} | {reason}")

    if mode == "full":
        return run_full_fetch_and_record(
            form_id, i, total_forms, args.page_size,
            results, total_records, total_size_mb
        )

    # mode == "incremental" — previous_metadata is guaranteed non-None here
    since_iso = compute_since_iso(previous_metadata.get("last_submission_time"))

    if since_iso is None:
        console(
            f"   ⚠️  Form {form_id} | Could not compute an incremental cursor "
            f"from stored metadata; running full fetch instead."
        )
        detail(f"Form {form_id} | Incremental cursor unavailable — falling back to full.")
        return run_full_fetch_and_record(
            form_id, i, total_forms, args.page_size,
            results, total_records, total_size_mb
        )

    try:
        new_data = fetch_new_data(
            form_id=form_id,
            since_iso=since_iso,
            form_index=i,
            total_forms=total_forms,
            page_size=args.page_size
        )
    except IncrementalFetchError as e:
        console(
            f"   ⚠️  Form {form_id} | Incremental fetch failed ({e}); "
            f"running full fetch instead."
        )
        detail(f"Form {form_id} | Incremental fetch error: {e} — falling back to full.")
        return run_full_fetch_and_record(
            form_id, i, total_forms, args.page_size,
            results, total_records, total_size_mb
        )

    if not new_data:
        metadata = touch_metadata_checked(form_id, previous_metadata)
        existing_records = metadata.get("records", 0)

        console(
            f"✓  Form {form_id} ({i}/{total_forms}) | "
            f"UP TO DATE | {existing_records:,} records"
        )
        detail(f"Form {form_id} | Incremental check: 0 new records since {since_iso}.")

        results.append({
            "form_id": form_id,
            "status": "checked_no_new",
            "records": existing_records,
            "new_records": 0,
            "size_mb": round(output_path.stat().st_size / (1024 * 1024), 2)
                if output_path.exists() else 0,
            "path": str(output_path)
        })

        return total_records, total_size_mb

    peak_mb = _peak_rss_mb()
    if peak_mb is not None:
        console(f"   [MEM] Peak RSS before merging form {form_id}: {peak_mb:,.0f} MB")

    existing_row_count = previous_metadata.get("records", 0)
    isolate_merge = existing_row_count > _ISOLATE_MERGE_ROW_THRESHOLD

    if isolate_merge:
        console(
            f"   [MEM] Form {form_id} | existing data is {existing_row_count:,} rows -- "
            f"running this merge in an isolated subprocess so an out-of-memory kill "
            f"here can't take down the rest of this fetch run."
        )
        metadata = _merge_incremental_isolated(form_id, new_data, previous_metadata)
    else:
        metadata = save_incremental(form_id, new_data, previous_metadata)

    if metadata is None:
        if isolate_merge:
            # Already logged above (with the specific reason, e.g. an
            # OOM-kill) by _merge_incremental_isolated().
            detail(f"Form {form_id} | Isolated incremental merge failed -- leaving existing data untouched, will retry next run.")
            results.append({
                "form_id": form_id, "status": "failed_isolated_merge",
                "records": existing_row_count, "new_records": 0,
                "size_mb": round(output_path.stat().st_size / (1024 * 1024), 2)
                    if output_path.exists() else 0,
                "path": str(output_path)
            })
            return total_records, total_size_mb

        console(
            f"   ⚠️  Form {form_id} | Could not safely merge "
            f"{len(new_data):,} new record(s); running full fetch instead."
        )
        detail(f"Form {form_id} | Incremental merge failed — falling back to full.")
        return run_full_fetch_and_record(
            form_id, i, total_forms, args.page_size,
            results, total_records, total_size_mb
        )

    file_size = output_path.stat().st_size / (1024 * 1024)

    console(
        f"   💾 Merged: {form_id}.parquet | "
        f"+{len(new_data):,} new | {metadata['records']:,} total | {file_size:.2f} MB"
    )

    results.append({
        "form_id": form_id,
        "status": "incremental",
        "records": metadata["records"],
        "new_records": len(new_data),
        "size_mb": round(file_size, 2),
        "path": str(output_path)
    })

    return total_records + len(new_data), total_size_mb + file_size


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch Independent Monitoring IM data from ONA and save as Parquet. "
            "By default, forms with a recent local copy are fetched INCREMENTALLY "
            "(only new submissions); use --force-full to force a full re-download."
        )
    )

    parser.add_argument(
        "--base-dir",
        default=str(BASE_DIR),
        help=(
            "im_workflow base directory. Already resolved from this flag (if "
            "passed) before this parser even runs -- see the module-level "
            "comment above BASE_DIR -- so this entry exists only so --help "
            "documents it. (default: %(default)s)"
        )
    )

    parser.add_argument(
        "--config",
        help="Optional YAML/JSON config file path containing IM form IDs"
    )

    parser.add_argument(
        "--force-full",
        action="store_true",
        help="Force full fetch and overwrite existing Parquet files for every form"
    )

    parser.add_argument(
        "--full-refresh-days",
        type=float,
        default=30,
        help=(
            "A form gets a full re-fetch (instead of incremental) if its last full "
            "fetch is older than this many days — catches edits/corrections made to "
            "previously-fetched submissions, which pure incremental fetching would "
            "never see. Default: 30"
        )
    )

    parser.add_argument(
        "--form-ids",
        help="Comma-separated form IDs to fetch, e.g. 8587,7178"
    )

    parser.add_argument(
        "--test",
        action="store_true",
        help="Test API connection only"
    )

    parser.add_argument(
        "--page-size",
        type=int,
        default=10000,
        help="Number of records per API page. Default: 10000"
    )

    # Internal-only flags used when this script re-invokes itself as the
    # isolated merge child spawned by _merge_incremental_isolated() --
    # not meant to be passed by hand, hence argparse.SUPPRESS.
    parser.add_argument("--internal-merge-form", type=int, default=None, help=argparse.SUPPRESS)
    parser.add_argument("--new-data-file", default=None, help=argparse.SUPPRESS)
    parser.add_argument("--previous-metadata-file", default=None, help=argparse.SUPPRESS)
    parser.add_argument("--result-file", default=None, help=argparse.SUPPRESS)

    args = parser.parse_args()

    create_workflow_folders()

    if args.internal_merge_form is not None:
        # This invocation IS the isolated child process -- do just this
        # one form's merge and exit, skipping the normal 35-form pipeline
        # entirely. See _merge_incremental_isolated()'s docstring.
        with open(args.new_data_file, "r", encoding="utf-8") as f:
            new_data = json.load(f)
        with open(args.previous_metadata_file, "r", encoding="utf-8") as f:
            previous_metadata = json.load(f)

        result = save_incremental(args.internal_merge_form, new_data, previous_metadata)

        if result is None:
            sys.exit(1)

        with open(args.result_file, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False)

        sys.exit(0)

    if args.test:
        test_api_connection()
        return

    if args.form_ids:
        form_ids = [int(f.strip()) for f in args.form_ids.split(",") if f.strip()]
    else:
        form_ids = load_form_ids(args.config)

    form_ids = list(dict.fromkeys(form_ids))

    console("")
    console("🚀 INDEPENDENT MONITORING IM DATA FETCHER")
    console("============================================================")
    console(f"📂 Base folder      : {BASE_DIR}")
    console(f"📥 Raw folder       : {RAW_DIR}")
    console(f"🧾 Forms            : {len(form_ids)}")
    console(f"📦 Format           : Parquet")
    console(f"🔁 Force full       : {args.force_full}")
    console(f"🗓️  Full refresh    : every {args.full_refresh_days:g} day(s)")
    console("============================================================")

    if not test_api_connection():
        console("❌ Cannot proceed because API connection failed.")
        sys.exit(1)

    sync_missing_raw_from_sharepoint(form_ids)

    results = []
    total_records = 0
    total_size_mb = 0.0

    for i, form_id in enumerate(form_ids, 1):
        try:
            total_records, total_size_mb = process_one_form(
                form_id, i, len(form_ids), args, results, total_records, total_size_mb
            )
        except Exception as e:
            # A bug or crash while fetching/saving ONE form (e.g. form 4498's
            # MemoryError on 2026-08-22) must never take down the fetch for
            # every other form queued after it -- that run silently skipped
            # forms 13-35 entirely because the whole script died here, and
            # the rest of the pipeline went on to build reports from stale
            # data for all of them without any clear warning. Catching per
            # form keeps that failure contained to just this one form.
            console(
                f"   ❌ Form {form_id} ({i}/{len(form_ids)}) | UNEXPECTED ERROR: {e} -- "
                f"skipping this form and continuing with the rest. The existing "
                f"{form_id}.parquet (if any) is left untouched."
            )
            detail(f"Form {form_id} | Unexpected exception: {e!r}")

            import traceback
            detail(traceback.format_exc())

            results.append({
                "form_id": form_id, "status": "failed_exception",
                "records": 0, "new_records": 0, "size_mb": 0,
                "path": str(RAW_DIR / f"{form_id}.parquet")
            })

        # Reclaim memory before the next form, win or lose -- see the
        # save_incremental() comment on form 4498's OOM-kill for why this
        # matters over a long sequential run of many large forms.
        gc.collect()

        peak_mb = _peak_rss_mb()
        if peak_mb is not None:
            console(f"   [MEM] Peak RSS after form {form_id}: {peak_mb:,.0f} MB")

    full_count = sum(1 for r in results if r["status"] == "full")
    incremental_count = sum(1 for r in results if r["status"] == "incremental")
    checked_count = sum(1 for r in results if r["status"] == "checked_no_new")
    success_count = full_count + incremental_count
    incomplete_count = sum(1 for r in results if r["status"] == "failed_incomplete")
    exception_count = sum(1 for r in results if r["status"] == "failed_exception")
    failed_count = sum(
        1 for r in results
        if r["status"] in ["failed", "failed_no_data", "failed_incomplete", "failed_exception"]
    )

    total_available_records = sum(int(r.get("records", 0)) for r in results)

    summary = {
        "workflow": "Independent Monitoring IM",
        "timestamp": datetime.now().isoformat(),
        "base_dir": str(BASE_DIR),
        "raw_dir": str(RAW_DIR),
        "forms_total": len(form_ids),
        "full_fetches": full_count,
        "incremental_fetches": incremental_count,
        "checked_no_new": checked_count,
        "successful": success_count,
        "failed": failed_count,
        "total_records_fetched_this_run": total_records,
        "total_records_available_or_fetched": total_available_records,
        "total_size_mb_this_run": round(total_size_mb, 2),
        "format": "parquet",
        "results": results
    }

    write_fetch_summary(summary)
    append_fetch_history(summary)

    console("")
    console("============================================================")
    console("📊 FETCH SUMMARY")
    console("============================================================")
    console(f"✅ Full fetches           : {full_count}/{len(form_ids)}")
    console(f"🔄 Incremental (new data) : {incremental_count}")
    console(f"✓  Checked, up to date    : {checked_count}")
    console(f"🚧 Incomplete (kept old data, will retry): {incomplete_count}")
    console(f"❌ Crashed unexpectedly (see fetch_log.txt): {exception_count}")
    console(f"⚠️  Failed / no data       : {failed_count}")
    console(f"📈 New records this run   : {total_records:,}")
    console(f"📚 Records available      : {total_available_records:,}")
    console(f"💾 Data written this run  : {total_size_mb:.2f} MB")
    console(f"📂 Data saved to          : {RAW_DIR}")
    console("============================================================")

    print_created_files_preview()

    console("")
    console("✅ IM data fetch complete.")
    console("➡️  Next step: run regional_im_repository_builder.R")
    console("")


if __name__ == "__main__":
    main()
