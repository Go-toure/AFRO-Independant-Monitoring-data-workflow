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
import requests
import pandas as pd

from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Optional


# ============================================================
# WINDOWS CONSOLE ENCODING FIX
# ============================================================

if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")


# ============================================================
# CENTRALIZED IM WORKFLOW PATHS
# ============================================================

# Set once via `setx IM_WORKFLOW_HOME "D:/new/path"` (Windows) if this
# project ever moves off this laptop/drive -- every script in the pipeline
# reads the same variable, so nothing else needs editing.
BASE_DIR = Path(os.environ.get("IM_WORKFLOW_HOME", r"C:/Users/TOURE/Documents/im_workflow"))

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
_STATUS_TAGS = {
    "✅": "[OK]",      # ✅
    "❌": "[ERROR]",   # ❌
    "⚠️": "[WARN]",  # ⚠️
    "⚠": "[WARN]",    # ⚠
}

# Everything else here is a purely decorative bullet (section-header icons
# like 📦/🚀/📊/⏳/✓) and is just dropped, along with one trailing space, so
# the line reads as plain text instead of an emoji + text mashup.
_DECORATIVE_EMOJI_RE = re.compile(
    "[\U0001F300-\U0001FAFF☀-➿←-⇿⌀-⏿]️? *"
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

    Returns ``(all_data, fetch_complete)``. ``fetch_complete`` is False if a
    page had to be given up on after retries (see ``fetch_page``) — in that
    case ``all_data`` is only a PARTIAL, untrustworthy result and callers
    must not save it over existing data or treat its max submission time as
    a safe incremental cursor.
    """
    all_data = []
    page = 1
    fetch_complete = True

    console(f"📦 Form {form_id} ({form_index}/{total_forms}) | FULL fetch")
    detail(f"[FETCH:FULL] Form {form_id}")

    while True:
        live_line(
            f"   ⏳ Fetching page {page} | Records so far: {len(all_data):,}"
        )

        data = fetch_page(form_id, page, page_size)

        if data is None:
            clear_live_line()
            detail(f"Form {form_id} | Page {page} | Giving up -- fetch marked INCOMPLETE.")
            fetch_complete = False
            break

        if not data:
            clear_live_line()
            detail(f"Form {form_id} | Page {page} | No data returned.")
            break

        flattened_data = [flatten_dict(record) for record in data]
        all_data.extend(flattened_data)

        detail(
            f"Form {form_id} | Page {page} | Retrieved {len(data):,} records | "
            f"Running total: {len(all_data):,}"
        )

        live_line(
            f"   ⏳ Page {page} complete | Records so far: {len(all_data):,}"
        )

        if len(data) < page_size:
            clear_live_line()
            break

        page += 1
        time.sleep(0.5)

    if fetch_complete:
        console(f"   ✅ Fetch complete: {len(all_data):,} records across {page} page(s)")
    else:
        console(
            f"   ⚠️  Fetch INCOMPLETE: page {page} failed after retries — only "
            f"{len(all_data):,} record(s) retrieved. Existing data will NOT be "
            f"overwritten with this partial result."
        )

    detail(f"[DONE] Form {form_id}: {len(all_data):,} total records | complete={fetch_complete}")

    return all_data, fetch_complete


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


def build_dataframe_from_records(data: List[Dict]) -> pd.DataFrame:
    """Turn a list of flattened record dicts into the standard IM DataFrame
    (all-string columns, GPS components split out). Shared by full and
    incremental fetches so both produce identical column shapes.

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
    df = pd.DataFrame(data)

    for col in df.columns:
        series = df[col]
        if series.isna().any():
            series = series.fillna("")
        df[col] = series.astype(str)

    df = extract_gps_components(df)
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

    return write_parquet_and_metadata(df, form_id, meta_extra)


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
    """
    if not new_data:
        return None

    existing_path = RAW_DIR / f"{form_id}.parquet"

    if not existing_path.exists():
        detail(f"[WARNING] Form {form_id} | Incremental merge requested but no existing Parquet file.")
        return None

    try:
        existing_df = pd.read_parquet(existing_path)
    except Exception as e:
        detail(f"[WARNING] Form {form_id} | Could not read existing Parquet for merge: {e}")
        return None

    new_df = build_dataframe_from_records(new_data)

    if "_id" not in existing_df.columns or "_id" not in new_df.columns:
        detail(f"[WARNING] Form {form_id} | No _id column available — cannot safely de-duplicate merge.")
        return None

    try:
        combined = pd.concat([existing_df, new_df], ignore_index=True, sort=False)
        combined = combined.fillna("").astype(str)
        combined = combined.drop_duplicates(subset=["_id"], keep="last").reset_index(drop=True)
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


def run_full_fetch(form_id: int, i: int, total_forms: int, page_size: int) -> Dict:
    """Perform a full fetch + full overwrite save for one form. Returns a
    results-row dict for the run summary."""
    output_path = RAW_DIR / f"{form_id}.parquet"

    data, fetch_complete = fetch_all_data(
        form_id=form_id,
        form_index=i,
        total_forms=total_forms,
        page_size=page_size
    )

    if not fetch_complete:
        # A page failed after retries partway through the fetch. Never
        # overwrite the existing (possibly larger, definitely more trusted)
        # Parquet file with this partial result -- just flag the metadata so
        # decide_fetch_mode retries a full fetch again next run, and leave
        # the data file exactly as it was.
        console(
            f"   ⚠️  Form {form_id} | Full fetch INCOMPLETE ({len(data):,} row(s) retrieved "
            f"before giving up) -- keeping the PREVIOUS {form_id}.parquet untouched. "
            f"Will retry a full fetch again next run."
        )
        detail(f"Form {form_id} | Full fetch incomplete -- existing data left untouched.")

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
        prior_metadata["last_full_fetch_attempt_rows_retrieved"] = len(data)

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

    if not data:
        console(f"   ⚠️  No data fetched for form {form_id}")
        return {
            "form_id": form_id, "status": "failed_no_data",
            "records": 0, "new_records": 0, "size_mb": 0, "path": str(output_path)
        }

    metadata = save_to_parquet(data, form_id)

    if not metadata:
        console(f"   ❌ Save failed for form {form_id}")
        return {
            "form_id": form_id, "status": "failed",
            "records": 0, "new_records": 0, "size_mb": 0, "path": str(output_path)
        }

    file_size = output_path.stat().st_size / (1024 * 1024)
    console(f"   💾 Saved: {form_id}.parquet | {len(data):,} rows | {file_size:.2f} MB")

    return {
        "form_id": form_id, "status": "full",
        "records": len(data), "new_records": len(data),
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

    metadata = save_incremental(form_id, new_data, previous_metadata)

    if metadata is None:
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

    args = parser.parse_args()

    create_workflow_folders()

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
