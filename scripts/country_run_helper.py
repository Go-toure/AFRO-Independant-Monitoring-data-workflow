#!/usr/bin/env python3
"""
Small helper for the per-country run (scripts/run_country_workflow.R).

    python scripts/country_run_helper.py seed-lookup --home <scratch> [--repo-lookup <path>]

seed-lookup puts the campaign calendar (lookup.xlsx) into <scratch>/data/lookup/.
Order: the copy already on this server (--repo-lookup) -> the last-known-good copy
on SharePoint (READ ONLY download). Exit 0 when a calendar is in place, 1 when not.

This helper never writes to SharePoint (and the run sets IM_READ_ONLY_SHAREPOINT=1
as well, so the client would refuse anyway).
"""
import argparse
import shutil
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

SP_LOOKUP_FOLDER = "7. SIA_Data/Data Repository/Cloud-Independant-Monitoring/lookup_state"


def seed_lookup(home: Path, repo_lookup: Optional[Path]) -> bool:
    dest = home / "data" / "lookup" / "lookup.xlsx"
    dest.parent.mkdir(parents=True, exist_ok=True)

    if repo_lookup and repo_lookup.is_file() and repo_lookup.stat().st_size > 0:
        shutil.copyfile(repo_lookup, dest)
        print(f"[country-run] campaign calendar: using the copy on this server ({dest.stat().st_size:,} bytes)")
        return True

    try:
        from _env_loader import load_secrets_env
        load_secrets_env(home)            # <home>/config/secrets.env (copied by the run script), if any
        import _sharepoint_client as sp
        if sp.credentials_available():
            token = sp.get_token()
            drive = sp.get_drive_id(token) if token else None
            if drive and sp.download_file(token, drive, f"{SP_LOOKUP_FOLDER}/lookup.xlsx", dest):
                print(f"[country-run] campaign calendar: recovered the published copy ({dest.stat().st_size:,} bytes)")
                return True
    except Exception as e:                # never let a calendar problem crash the helper
        print(f"[country-run] campaign calendar: recovery failed ({type(e).__name__})")
    print("[country-run] campaign calendar: not available")
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("seed-lookup")
    s.add_argument("--home", required=True)
    s.add_argument("--repo-lookup", default="")
    a = ap.parse_args()
    if a.cmd == "seed-lookup":
        ok = seed_lookup(Path(a.home), Path(a.repo_lookup) if a.repo_lookup else None)
        return 0 if ok else 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
