#!/usr/bin/env python3
"""
sharepoint_bin_report.py
READ-ONLY report of how much SharePoint storage is parked in the site's
recycle bin from this pipeline's raw_state folder.

Background: prune_old_versions() (see _sharepoint_client.py) deletes old file
versions after every raw-state upload, but deleted versions normally go to the
recycle bin and keep counting against the storage quota until the bin is
emptied. This script measures that -- it NEVER deletes, restores or changes
anything -- so the size of the problem is known before any purge is built.

Usage (from the project folder):
    python scripts/sharepoint_bin_report.py
    python scripts/sharepoint_bin_report.py --base-dir C:/Users/TOURE/Documents/im_workflow

Also called automatically at the end of Fetch_im_data.py's run (see
report_sharepoint_bin_usage() there). Always exits 0 -- a failed measurement
must never fail a pipeline run.
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Callable, Dict, List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _sharepoint_client as sp  # noqa: E402

# Same folder Fetch_im_data.py syncs raw state into (SP_RAW_FOLDER there).
RAW_FOLDER_MARKER = "7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/raw_state"


def _human(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:,.0f} {unit}" if unit == "B" else f"{size:,.2f} {unit}"
        size /= 1024
    return f"{n} B"


def format_report(result: Dict, folder_marker: str = RAW_FOLDER_MARKER) -> List[str]:
    """Turn a measure_recycle_bin() result into printable lines."""
    lines = ["[sharepoint-bin] Recycle bin check (read-only, nothing is deleted)"]
    if not result.get("ok"):
        status = result.get("status")
        lines.append(f"[sharepoint-bin]   Could not measure: HTTP {status}, {result.get('error')}"
                     if status else f"[sharepoint-bin]   Could not measure: {result.get('error')}")
        if status in (401, 403):
            lines.append("[sharepoint-bin]   The app registration probably lacks permission to read the "
                         "site recycle bin (Graph beta recycleBin/items). Ask IT, or this check "
                         "can't run -- it does not affect the pipeline.")
        elif status == 404:
            lines.append("[sharepoint-bin]   The beta recycleBin endpoint was not found for this site.")
        return lines

    lines.append(f"[sharepoint-bin]   raw_state items in the bin : {result['mine_items']:,} "
                 f"({_human(result['mine_bytes'])})")
    lines.append(f"[sharepoint-bin]   whole-site bin (everyone)   : {result['all_items']:,} "
                 f"({_human(result['all_bytes'])})"
                 + ("  [partial: page limit reached]" if result.get("truncated") else ""))
    if result["mine_items"]:
        lines.append(f"[sharepoint-bin]   oldest / newest deleted     : "
                     f"{result['oldest_mine']} / {result['newest_mine']}")
        for name, count, size in result.get("top_names", []):
            lines.append(f"[sharepoint-bin]     {name}: {count:,} item(s), {_human(size)}")
    else:
        lines.append(f"[sharepoint-bin]   Nothing matched '{folder_marker}'. If you expected "
                     "pruned versions here, the bin may store a different path format. "
                     "Locations seen in the bin:")
        for loc in result.get("sample_locations", []):
            lines.append(f"[sharepoint-bin]     {loc}")
    return lines


def run_report(print_fn: Callable[[str], None] = print,
               folder_marker: str = RAW_FOLDER_MARKER) -> Dict:
    """Measure and print. Never raises; returns the raw result dict."""
    try:
        if not sp.credentials_available():
            print_fn("[sharepoint-bin] Credentials not set -- skipping recycle bin check.")
            return {"ok": False, "status": None, "error": "credentials not set"}
        token = sp.get_token()
        if not token:
            print_fn("[sharepoint-bin] Could not acquire Graph token -- skipping recycle bin check.")
            return {"ok": False, "status": None, "error": "no token"}
        result = sp.measure_recycle_bin(token, folder_marker)
        for line in format_report(result, folder_marker):
            print_fn(line)
        return result
    except Exception as e:  # a diagnostic must never take down a run
        print_fn(f"[sharepoint-bin] Check failed unexpectedly: {type(e).__name__}: {e}")
        return {"ok": False, "status": None, "error": str(e)}


def main() -> int:
    ap = argparse.ArgumentParser(description="Read-only SharePoint recycle bin report.")
    ap.add_argument("--base-dir", default=None,
                    help="Project folder containing config/secrets.env "
                         "(default: IM_WORKFLOW_HOME, else the folder above scripts/).")
    args = ap.parse_args()
    base = Path(args.base_dir or os.environ.get("IM_WORKFLOW_HOME")
                or Path(__file__).resolve().parent.parent)
    from _env_loader import load_secrets_env
    load_secrets_env(base)
    run_report()
    return 0


if __name__ == "__main__":
    sys.exit(main())
