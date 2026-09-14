#!/usr/bin/env python3
# ============================================================
# FETCH ALL POLIOVIRUSES FROM SHAREPOINT
#
# Standalone downloader for:
#   AllPolioviruses_20250106.xlsx
# from the WHO AF-pep/GISWORKSPACE SharePoint site, via a sharing link:
#   https://worldhealthorg.sharepoint.com/:x:/r/sites/AF-pep/GISWORKSPACE/
#     _layouts/15/Doc.aspx?sourcedoc=%7BE89A19B2-233D-4E86-872F-DC8DC2A74F01%7D
#     &file=AllPolioviruses_20250106.xlsx&action=default&mobileredirect=true
#
# Uses the same app-only (client-credentials) Microsoft Graph flow as the
# other WHO AFRO tooling (im_workflow's upload_to_sharepoint.py,
# prepare_the_AFRO_SIA_Dashboard_input.py's SharePoint downloads): resolves
# the sharing link straight to a driveItem via Graph's /shares/{id}
# endpoint, then downloads its content. No browser, no MFA, no dependency
# on any other project in this repo -- this file is self-contained.
#
# Setup (one-time):
#   pip install requests
#   Set three environment variables (or put them in a secrets.env file --
#   see --secrets-env below):
#     SHAREPOINT_TENANT_ID
#     SHAREPOINT_CLIENT_ID
#     SHAREPOINT_CLIENT_SECRET
#   These are the SAME app-registration credentials already used by
#   im_workflow / prepare_the_AFRO_SIA_Dashboard_input.py for this same
#   SharePoint site -- copy them from wherever you already keep those
#   (e.g. that project's own config/secrets.env). Never hardcode them
#   here, never paste them on the command line, never share this file
#   once it has real values in it.
#
# Usage:
#   python fetch_all_polioviruses.py
#   python fetch_all_polioviruses.py --output-dir data
#   python fetch_all_polioviruses.py --output-name AllPolioviruses.xlsx
#   python fetch_all_polioviruses.py --secrets-env config/secrets.env
#   python fetch_all_polioviruses.py --share-url "https://...другой-file..."
# ============================================================

import argparse
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

# Windows consoles frequently can't print accented characters unless the
# console codepage happens to be UTF-8 -- reconfigure so a stray print()
# falls back to '?'-style replacement instead of crashing the whole run.
try:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except Exception:
    pass

DEFAULT_SHARE_URL = (
    "https://worldhealthorg.sharepoint.com/:x:/r/sites/AF-pep/GISWORKSPACE/"
    "_layouts/15/Doc.aspx?sourcedoc=%7BE89A19B2-233D-4E86-872F-DC8DC2A74F01%7D"
    "&file=AllPolioviruses_20250106.xlsx&action=default&mobileredirect=true"
)
DEFAULT_OUTPUT_NAME = "AllPolioviruses_20250106.xlsx"
GRAPH_ENDPOINT = "https://graph.microsoft.com/v1.0"
MIN_BYTES = 1000  # below this, treat the download as failed/truncated


def log(msg):
    try:
        print(f"[fetch_all_polioviruses] {msg}", flush=True)
    except UnicodeEncodeError:
        print(f"[fetch_all_polioviruses] {str(msg).encode('ascii', errors='replace').decode('ascii')}", flush=True)


def load_secrets_env(path: Path):
    """Minimal, dependency-free .env loader: reads KEY=VALUE lines from
    `path` (if it exists) into os.environ, without overwriting a variable
    that's already set in the real shell environment (so `setx`/`export`
    always wins over the file, same convention as the rest of this WHO
    AFRO tooling). Blank lines and lines starting with '#' are ignored.
    Silently does nothing if the file doesn't exist -- that's the normal
    case when credentials are already set as real environment variables."""
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip()
        if key and key not in os.environ:
            os.environ[key] = value


def _graph_share_id(share_url: str) -> str:
    """Encode a SharePoint/OneDrive sharing URL into the base64 'shares'
    id Microsoft Graph's /shares/{id} endpoint expects (documented Graph
    behavior for resolving any sharing link into a driveItem, regardless
    of which folder the file actually lives in): base64-encode the URL,
    strip '=' padding, make it URL-safe, and prefix with 'u!'."""
    import base64
    b64 = base64.b64encode(share_url.encode("utf-8")).decode("utf-8")
    b64 = b64.rstrip("=").replace("/", "_").replace("+", "-")
    return "u!" + b64


def get_graph_token(tenant_id: str, client_id: str, client_secret: str) -> str:
    """App-only client-credentials token: authenticates as the registered
    application itself, not as a person -- no browser login, no MFA."""
    import requests
    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "scope": "https://graph.microsoft.com/.default",
        "grant_type": "client_credentials",
    }
    r = requests.post(url, data=data, timeout=30)
    r.raise_for_status()
    return r.json()["access_token"]


def download_sharepoint_file(share_url: str, output_path: Path, min_bytes: int = MIN_BYTES) -> bool:
    """Download a single file from a WHO SharePoint sharing link and save
    it at output_path, backing up whatever was already there. Never
    raises -- any failure is logged and reported back as False."""
    import requests

    tenant_id = os.environ.get("SHAREPOINT_TENANT_ID", "").strip()
    client_id = os.environ.get("SHAREPOINT_CLIENT_ID", "").strip()
    client_secret = os.environ.get("SHAREPOINT_CLIENT_SECRET", "").strip()
    if not all([tenant_id, client_id, client_secret]):
        log("FAILED: SHAREPOINT_TENANT_ID / SHAREPOINT_CLIENT_ID / SHAREPOINT_CLIENT_SECRET "
            "are not all set. Set them as environment variables, or put them in a secrets.env "
            "file and pass --secrets-env path/to/secrets.env. Treat them like passwords -- "
            "never hardcode them in this script or paste them anywhere else.")
        return False

    log("Authenticating to Microsoft Graph...")
    try:
        token = get_graph_token(tenant_id, client_id, client_secret)
    except Exception as e:
        log(f"FAILED: could not authenticate to Microsoft Graph ({e}).")
        return False

    headers = {"Authorization": f"Bearer {token}"}
    share_id = _graph_share_id(share_url)
    try:
        meta = requests.get(f"{GRAPH_ENDPOINT}/shares/{share_id}/driveItem", headers=headers, timeout=60)
        meta.raise_for_status()
        item = meta.json()

        download_url = item.get("@microsoft.graph.downloadUrl")
        if download_url:
            file_resp = requests.get(download_url, timeout=180)
            file_resp.raise_for_status()
            file_bytes = file_resp.content
        else:
            # Fall back to the drive item's own /content endpoint if the
            # metadata response didn't include a direct download URL.
            drive_id = item["parentReference"]["driveId"]
            item_id = item["id"]
            content_resp = requests.get(
                f"{GRAPH_ENDPOINT}/drives/{drive_id}/items/{item_id}/content",
                headers=headers, timeout=180,
            )
            content_resp.raise_for_status()
            file_bytes = content_resp.content
    except Exception as e:
        log(f"FAILED: could not download the file from SharePoint ({e}).")
        return False

    if len(file_bytes) < min_bytes:
        log(f"FAILED: downloaded file looks too small ({len(file_bytes)} bytes) -- "
            f"treating this as a failed download. Nothing was replaced.")
        return False

    try:
        if output_path.exists():
            backup_dir = output_path.parent / "backups"
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup_path = backup_dir / f"{output_path.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}{output_path.suffix}"
            shutil.copy2(output_path, backup_path)
            log(f"Backed up previous file -> {backup_path}")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(file_bytes)
    except PermissionError as e:
        log(f"FAILED: could not write {output_path} ({e}). This almost always means the file "
            f"is currently open in Excel or another program -- close it and re-run.")
        return False

    log(f"SUCCESS: {output_path} saved ({len(file_bytes)} bytes).")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Download AllPolioviruses_20250106.xlsx from the WHO AF-pep/GISWORKSPACE "
                    "SharePoint site via Microsoft Graph (app-only auth, no browser/MFA)."
    )
    parser.add_argument("--share-url", default=DEFAULT_SHARE_URL,
                        help="SharePoint sharing link to download (default: the "
                             "AllPolioviruses_20250106.xlsx link).")
    parser.add_argument("--output-dir", default=".",
                        help="Directory to save the file into (default: current directory).")
    parser.add_argument("--output-name", default=DEFAULT_OUTPUT_NAME,
                        help=f"Filename to save as (default: {DEFAULT_OUTPUT_NAME}).")
    parser.add_argument("--secrets-env", default="config/secrets.env",
                        help="Path to a KEY=VALUE file providing SHAREPOINT_TENANT_ID / "
                             "SHAREPOINT_CLIENT_ID / SHAREPOINT_CLIENT_SECRET if they aren't "
                             "already set as environment variables (default: config/secrets.env, "
                             "silently skipped if it doesn't exist).")
    args = parser.parse_args()

    load_secrets_env(Path(args.secrets_env))

    output_path = Path(args.output_dir) / args.output_name
    ok = download_sharepoint_file(args.share_url, output_path)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
