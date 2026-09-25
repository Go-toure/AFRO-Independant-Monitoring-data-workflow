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
import time
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


def _log_sp_failure(
    op: str,
    remote_path: str,
    response: Optional["requests.Response"] = None,
    exc: Optional[Exception] = None,
) -> None:
    """Print the real HTTP status code behind a write-side SharePoint
    failure (and, for a 429, its Retry-After header) instead of leaving
    every failure indistinguishable as a bare 'FAILED' in the pipeline
    log. Added 2026-09-25 after a run where every upload after the first
    two forms failed for the rest of the run with no way to tell a
    throttled 429 apart from an expired token (401), a permissions
    problem (403), or a transient 5xx -- this is purely a diagnostic
    side-channel: it never raises, and it changes nothing about any
    caller's own return value or the rest of this module's
    never-raises/best-effort contract.

    Prefers `response` (a real HTTP response was received, just not a
    success one) over `exc` (no response at all -- a network-level
    failure like a timeout or connection error)."""
    try:
        if response is not None:
            retry_after = response.headers.get("Retry-After")
            extra = f", Retry-After={retry_after}s" if retry_after else ""
            body = response.text[:300].replace("\n", " ") if response.text else ""
            print(
                f"   [sharepoint-error] {op} -- HTTP {response.status_code}{extra} "
                f"on {remote_path}: {body}",
                flush=True,
            )
        elif exc is not None:
            print(
                f"   [sharepoint-error] {op} -- {type(exc).__name__} on {remote_path}: {exc}",
                flush=True,
            )
    except Exception:
        pass


def _request_with_retry(
    method: str,
    url: str,
    max_attempts: int = 4,
    retry_delays: Optional[List[int]] = None,
    **kwargs,
) -> "requests.Response":
    """requests.request(), retrying up to max_attempts times on a 429
    (Too Many Requests) response before handing the caller whatever the
    last attempt returned -- the write-side counterpart to
    Fetch_im_data.py's own fetch_page(), which already retries a 429 from
    the ONA/Kobo API with a backoff. Added 2026-09-25: this SharePoint
    write path had no such handling at all, so a run that hit Graph's
    rate limit after roughly two forms' worth of write requests then
    failed every single write for the rest of that ~15-minute run, with
    nothing to back off and retry.

    Honors a Retry-After response header when Graph sends one (it
    usually does on a 429), falling back to retry_delays otherwise.
    Only 429 triggers a retry here -- any other status (including other
    4xx/5xx) is returned immediately on the first attempt, unchanged
    from this module's previous behavior, so the caller's own
    raise_for_status() / status-code handling still sees exactly what it
    always did for every failure mode except this one. A genuine network
    exception (timeout, connection error) is NOT retried here either --
    it propagates immediately, exactly as before this change."""
    if retry_delays is None:
        retry_delays = [15, 30, 60]

    response = requests.request(method, url, **kwargs)
    for attempt in range(1, max_attempts):
        if response.status_code != 429:
            return response

        retry_after = response.headers.get("Retry-After")
        try:
            delay = int(retry_after) if retry_after else retry_delays[min(attempt - 1, len(retry_delays) - 1)]
        except (TypeError, ValueError):
            delay = retry_delays[min(attempt - 1, len(retry_delays) - 1)]

        print(
            f"   [sharepoint] Rate limited (429) on {method} {url.split('?')[0]} -- "
            f"waiting {delay}s (attempt {attempt}/{max_attempts - 1})...",
            flush=True,
        )
        time.sleep(delay)
        response = requests.request(method, url, **kwargs)

    return response


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

            resp = _request_with_retry(
                "POST",
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
        except requests.exceptions.RequestException as e:
            _log_sp_failure("ensure_folder", current, response=getattr(e, "response", None), exc=e)
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
        r = _request_with_retry(
            "PUT",
            url,
            headers={**_auth(token), "Content-Type": "application/octet-stream"},
            data=content,
            timeout=300,
        )
        r.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        _log_sp_failure("upload_file", remote_path, response=getattr(e, "response", None), exc=e)
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
        session_resp = _request_with_retry(
            "POST",
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

                r = _request_with_retry(
                    "PUT",
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
                    _log_sp_failure("_upload_large_file:chunk", remote_path, response=r)
                    return False

                start += len(chunk)

        return True
    except requests.exceptions.RequestException as e:
        _log_sp_failure("_upload_large_file:session", remote_path, response=getattr(e, "response", None), exc=e)
        return False
    except OSError as e:
        _log_sp_failure("_upload_large_file:file-read", remote_path, exc=e)
        return False


def delete_item(token: str, drive_id: str, item_path: str) -> bool:
    """Delete an item (file, or a folder and everything under it) by its
    path, relative to the library root. Returns True once it's gone --
    including when it was already absent, so a caller doesn't need to
    check existence first -- and False only on a real failure. Never
    raises. Deleting through Graph goes to SharePoint's own recycle bin
    the same as deleting it by hand in the browser, so this is
    recoverable, not a permanent destroy."""
    try:
        url = f"https://graph.microsoft.com/v1.0/drives/{drive_id}/root:/{item_path}"
        r = _request_with_retry("DELETE", url, headers=_auth(token), timeout=60)
        if r.status_code in (204, 404):
            return True
        r.raise_for_status()
        return True
    except requests.exceptions.RequestException as e:
        _log_sp_failure("delete_item", item_path, response=getattr(e, "response", None), exc=e)
        return False
