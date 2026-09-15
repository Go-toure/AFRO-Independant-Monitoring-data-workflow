# _sharepoint_client.py
"""
Shared Microsoft Graph / SharePoint helper functions for the IM workflow.

Centralizes the app-only (client-credentials) Graph API calls used across
the pipeline's Python scripts (upload_to_sharepoint.py, Fetch_im_data.py,
refresh_preparedness_lookup.py, ...) so each script doesn't reimplement its
own token/site/drive resolution and upload/download plumbing.

Credentials (SHAREPOINT_TENANT_ID / SHAREPOINT_CLIENT_ID /
SHAREPOINT_CLIENT_SECRET) are loaded the same way as the rest of the
pipeline -- via config/secrets.env locally, or real environment variables
in Posit Connect Cloud. Every function here degrades to returning
None/False/[] rather than raising when credentials are missing or a call
fails, so a caller can treat SharePoint sync as an optional accelerant,
never a hard dependency -- exactly like shiny_app/R/data_source_sharepoint.R
already does on the dashboard's read side.
"""

import os
import requests
from pathlib import Path
from typing import Optional, List, Dict

# Same SharePoint site/library every script in this workflow already talks
# to (see upload_to_sharepoint.py) -- kept here as the single place that
# ever needs to change if the site moves.
SP_HOSTNAME = "worldhealthorg.sharepoint.com"
SP_SITE_PATH = "/sites/AF-pep/GISWORKSPACE"
SP_LIBRARY_NAME = "Documents"


def credentials_available() -> bool:
    """True if SHAREPOINT_TENANT_ID / CLIENT_ID / CLIENT_SECRET are all set
    (as real env vars, or via config/secrets.env already loaded by the
    caller's _env_loader.load_secrets_env() call)."""
    return all([
        os.environ.get("SHAREPOINT_TENANT_ID"),
        os.environ.get("SHAREPOINT_CLIENT_ID"),
        os.environ.get("SHAREPOINT_CLIENT_SECRET"),
    ])


def _auth(token: str) -> Dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def get_token() -> Optional[str]:
    """Get a Microsoft Graph app-only access token, or None on any failure
    (missing credentials, network error, bad credentials, ...)."""
    tenant_id = os.environ.get("SHAREPOINT_TENANT_ID", "")
    client_id = os.environ.get("SHAREPOINT_CLIENT_ID", "")
    client_secret = os.environ.get("SHAREPOINT_CLIENT_SECRET", "")

    if not all([tenant_id, client_id, client_secret]):
        return None

    url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
    data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "scope": "https://graph.microsoft.com/.default",
        "grant_type": "client_credentials",
    }

    try:
        r = requests.post(url, data=data, timeout=30)
        r.raise_for_status()
        return r.json().get("access_token")
    except requests.exceptions.RequestException:
        return None


def get_drive_id(token: str) -> Optional[str]:
    """Resolve the id of the SharePoint document library (drive) used by
    this workflow. Returns None on any failure."""
    try:
        site_url = f"https://graph.microsoft.com/v1.0/sites/{SP_HOSTNAME}:{SP_SITE_PATH}"
        site = requests.get(site_url, headers=_auth(token), timeout=60)
        site.raise_for_status()
        site_id = site.json()["id"]

        drives_url = f"https://graph.microsoft.com/v1.0/sites/{site_id}/drives"
        drives = requests.get(drives_url, headers=_auth(token), timeout=60)
        drives.raise_for_status()

        for d in drives.json().get("value", []):
            if d.get("name", "").lower() == SP_LIBRARY_NAME.lower():
                return d["id"]

        return None
    except requests.exceptions.RequestException:
        return None


def list_folder(token: str, drive_id: str, folder_path: str) -> List[Dict]:
    """List items (files + subfolders) directly inside folder_path. Returns
    [] if the folder doesn't exist yet, is empty, or on any error -- callers
    treat "nothing there" and "not there yet" the same way."""
    items: List[Dict] = []
    try:
        url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{folder_path}:/children"
        while url:
            r = requests.get(url, headers=_auth(token), timeout=60)
            if r.status_code == 404:
                return []
            r.raise_for_status()
            body = r.json()
            items.extend(body.get("value", []))
            url = body.get("@odata.nextLink")
        return items
    except requests.exceptions.RequestException:
        return items


def ensure_folder(token: str, drive_id: str, folder_path: str) -> bool:
    """Create folder_path (and any missing parent segments) if it doesn't
    already exist. Returns True once the folder exists (already there or
    just created), False if creation failed."""
    folders = [f for f in folder_path.split("/") if f]
    current = ""

    for folder in folders:
        parent = current
        current = f"{current}/{folder}" if current else folder

        check_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{current}"
        try:
            r = requests.get(check_url, headers=_auth(token), timeout=30)
            if r.status_code == 200:
                continue
        except requests.exceptions.RequestException:
            pass

        try:
            if parent:
                parent_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{parent}"
                parent_resp = requests.get(parent_url, headers=_auth(token), timeout=30)
                parent_resp.raise_for_status()
                parent_id = parent_resp.json()["id"]
                create_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/items/{parent_id}/children"
            else:
                create_url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root/children"

            resp = requests.post(
                create_url,
                headers=_auth(token),
                json={
                    "name": folder,
                    "folder": {},
                    "@microsoft.graph.conflictBehavior": "rename",
                },
                timeout=30,
            )
            resp.raise_for_status()
        except requests.exceptions.RequestException:
            return False

    return True


def download_file(token: str, drive_id: str, remote_path: str, local_path: Path) -> bool:
    """Download one file by its path (relative to the library root) to
    local_path. Returns False (never raises) on any failure, including the
    file not existing remotely."""
    try:
        url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{remote_path}:/content"
        r = requests.get(url, headers=_auth(token), timeout=180)
        if r.status_code == 404:
            return False
        r.raise_for_status()
        local_path.parent.mkdir(parents=True, exist_ok=True)
        with open(local_path, "wb") as f:
            f.write(r.content)
        return True
    except requests.exceptions.RequestException:
        return False


# Microsoft's own cutoff for the simple PUT-to-/content upload -- Graph
# accepts it up to a few hundred MB in practice, but officially recommends
# switching to a chunked upload session above ~4MB, and does reject it
# outright somewhere in the low hundreds of MB (this is what silently
# failed for the IM workflow's largest raw form -- 4498, ~374MB -- while
# every smaller form up to ~120MB uploaded fine via simple PUT).
_SIMPLE_UPLOAD_LIMIT = 4 * 1024 * 1024  # 4 MiB

# Must be a multiple of 320 KiB per Graph's upload-session requirement.
# 60 MiB keeps a reasonable number of requests for even the largest form
# (~375MB today -> ~7 chunks) without holding more than one chunk in
# memory at a time.
_UPLOAD_CHUNK_SIZE = 60 * 1024 * 1024  # 60 MiB


def upload_file(token: str, drive_id: str, local_path: Path, remote_path: str) -> bool:
    """Upload local_path to remote_path (relative to the library root),
    overwriting any existing file there. Returns False (never raises) on
    any failure. Files at or under 4MB use a single simple PUT; anything
    larger goes through a chunked upload session instead, since a simple
    PUT silently fails once a file crosses Graph's undocumented size
    ceiling (observed between ~120MB and ~374MB in this workflow)."""
    try:
        file_size = local_path.stat().st_size
    except OSError:
        return False

    if file_size > _SIMPLE_UPLOAD_LIMIT:
        return _upload_large_file(token, drive_id, local_path, remote_path, file_size)

    try:
        with open(local_path, "rb") as f:
            content = f.read()

        url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{remote_path}:/content"
        r = requests.put(
            url,
            headers={**_auth(token), "Content-Type": "application/octet-stream"},
            data=content,
            timeout=300,
        )
        r.raise_for_status()
        return True
    except requests.exceptions.RequestException:
        return False


def _upload_large_file(token: str, drive_id: str, local_path: Path, remote_path: str, file_size: int) -> bool:
    """Upload a file larger than _SIMPLE_UPLOAD_LIMIT via a resumable Graph
    upload session, sent in _UPLOAD_CHUNK_SIZE chunks. Never holds more
    than one chunk in memory, and never raises -- returns False on any
    failure, same contract as upload_file()."""
    try:
        session_url = (
            f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{remote_path}:/createUploadSession"
        )
        session_resp = requests.post(
            session_url,
            headers=_auth(token),
            json={"item": {"@microsoft.graph.conflictBehavior": "replace"}},
            timeout=60,
        )
        session_resp.raise_for_status()
        upload_url = session_resp.json()["uploadUrl"]

        with open(local_path, "rb") as f:
            start = 0
            while start < file_size:
                chunk = f.read(_UPLOAD_CHUNK_SIZE)
                if not chunk:
                    break
                end = start + len(chunk) - 1

                r = requests.put(
                    upload_url,
                    headers={
                        "Content-Length": str(len(chunk)),
                        "Content-Range": f"bytes {start}-{end}/{file_size}",
                    },
                    data=chunk,
                    timeout=300,
                )

                # 200/201 on the final chunk (item created), 202 ("Accepted")
                # on every chunk in between.
                if r.status_code not in (200, 201, 202):
                    return False

                start += len(chunk)

        return True
    except requests.exceptions.RequestException:
        return False
    except OSError:
        return False
