#!/usr/bin/env python3
"""
sharepoint_recyclebin_purge.py
Admin tool: permanently clear items from a SharePoint site collection's
recycle bin (both stages), with filters, safety limits and an audit log.

WHY THIS EXISTS
    Items deleted from SharePoint stay in the recycle bin (first stage, then
    second stage, ~93 days in total) and keep counting against the storage
    quota until they are purged. The Microsoft Graph API used by the IM
    pipeline cannot empty a regular site's recycle bin, so this script uses
    the SharePoint REST API (_api/site/RecycleBin) instead.

WHO SHOULD RUN IT
    A SharePoint / tenant administrator. The bin is SHARED: it holds files
    deleted by every member of the site, and a purge is PERMANENT -- nobody
    can restore those files afterwards. That is why the script:
      * is a DRY RUN unless --execute is given (it only lists + writes a CSV),
      * only touches items older than --older-than-days (default 30),
      * refuses to run on more than --max-items items (default 10000),
      * asks you to type a confirmation phrase unless --yes is given,
      * writes a CSV audit log of every item (who deleted it, when, size).
    It is NOT wired into the IM pipeline on purpose.

REQUIREMENTS
    pip install msal requests
    An Entra ID (Azure AD) app registration that authenticates with a
    CERTIFICATE (SharePoint REST rejects client-secret app-only tokens) and
    has SharePoint application permission Sites.FullControl.All
    (or Sites.Selected + FullControl on this one site). Admin consent needed.
    The certificate's private key as a PEM file:
        openssl pkcs12 -in cert.pfx -nocerts -nodes -out key.pem

CONFIGURATION (environment variables or command-line flags)
    SP_SITE_URL         https://<tenant>.sharepoint.com/sites/AF-pep/GISWORKSPACE
    SP_TENANT_ID        Directory (tenant) ID
    SP_APP_CLIENT_ID    Application (client) ID of the cert-based app
    SP_CERT_KEY_PATH    path to the PEM private key
    SP_CERT_THUMBPRINT  certificate thumbprint (hex, as shown in Entra ID)
    SP_CERT_PASSPHRASE  only if the PEM key is encrypted

EXAMPLES
    # 1. See what is there and what WOULD be purged (changes nothing):
    python sharepoint_recyclebin_purge.py

    # 2. Only items under one folder, older than 60 days:
    python sharepoint_recyclebin_purge.py --path-contains "Cloud-Independant-Monitoring/raw_state" --older-than-days 60

    # 3. Really purge (asks for a typed confirmation):
    python sharepoint_recyclebin_purge.py --execute

    # 4. Unattended / scheduled (no prompt -- only after a dry run looked right):
    python sharepoint_recyclebin_purge.py --execute --yes --older-than-days 30

NOTE ON TWO STAGES
    Deleting a first-stage item may only move it to the second-stage bin.
    With --stage all (default) the script re-reads the bin after each pass and
    deletes the same items again if they moved to second stage, so they are
    really gone. Only items selected in the first pass are ever re-deleted.

EXIT CODES: 0 ok / dry run, 1 some deletions failed, 2 configuration or
authentication error, 3 safety limit hit or confirmation declined.
"""

import argparse
import csv
import datetime as dt
import os
import re
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Callable, Dict, List, Optional
from urllib.parse import unquote

import requests

SELECT_FIELDS = ("Id,Title,DirName,LeafName,Size,DeletedDate,ItemState,ItemType,"
                 "DeletedByName,DeletedByEmail,AuthorName")
STAGE_FIRST, STAGE_SECOND = 1, 2
STAGE_LABEL = {STAGE_FIRST: "first-stage", STAGE_SECOND: "second-stage"}
DELETE_CHUNK = 100
PAGE_SIZE = 2000


class AbortRun(Exception):
    """Authentication/permission failure: stop everything immediately."""


# --------------------------------------------------------------------------
# Authentication (certificate-based app-only)
# --------------------------------------------------------------------------
def make_token_provider(site_url: str, tenant_id: str, client_id: str,
                        key_path: str, thumbprint: str,
                        passphrase: Optional[str] = None) -> Callable[[], str]:
    """Return a function that gives a valid access token (msal caches/refreshes)."""
    import msal  # imported here so --help and the tests work without msal installed
    from urllib.parse import urlparse
    host = urlparse(site_url).netloc
    private_key = Path(key_path).read_text(encoding="utf-8")
    cred = {"private_key": private_key, "thumbprint": thumbprint.replace(":", "").strip()}
    if passphrase:
        cred["passphrase"] = passphrase
    app = msal.ConfidentialClientApplication(
        client_id, authority=f"https://login.microsoftonline.com/{tenant_id}",
        client_credential=cred)

    def provider() -> str:
        res = app.acquire_token_for_client(scopes=[f"https://{host}/.default"])
        if "access_token" not in res:
            raise AbortRun(f"Token request failed: {res.get('error')}: "
                           f"{res.get('error_description')}")
        return res["access_token"]
    return provider


# --------------------------------------------------------------------------
# SharePoint REST client
# --------------------------------------------------------------------------
class RecycleBinClient:
    def __init__(self, site_url: str, token_provider: Callable[[], str],
                 session=None, sleep: Callable[[float], None] = time.sleep):
        self.site = site_url.rstrip("/")
        self.token_provider = token_provider
        self.session = session or requests.Session()
        self.sleep = sleep

    def _request(self, method: str, url: str, json_body=None, retries: int = 5):
        for attempt in range(retries + 1):
            headers = {
                "Authorization": f"Bearer {self.token_provider()}",
                "Accept": "application/json;odata=nometadata",
            }
            if json_body is not None:
                headers["Content-Type"] = "application/json;odata=nometadata"
            resp = self.session.request(method, url, headers=headers,
                                        json=json_body, timeout=120)
            if resp.status_code in (401, 403):
                raise AbortRun(f"HTTP {resp.status_code} from SharePoint -- the app "
                               f"lacks permission or the certificate is not accepted. "
                               f"{(resp.text or '')[:300]}")
            if resp.status_code in (429, 503, 504) and attempt < retries:
                wait = float(resp.headers.get("Retry-After", 2 ** attempt))
                self.sleep(min(wait, 120))
                continue
            return resp
        return resp

    def list_items(self, max_pages: int = 500) -> List[Dict]:
        url = (f"{self.site}/_api/site/RecycleBin?$select={SELECT_FIELDS}"
               f"&$top={PAGE_SIZE}")
        items: List[Dict] = []
        for _ in range(max_pages):
            resp = self._request("GET", url)
            if resp.status_code != 200:
                raise RuntimeError(f"Listing the recycle bin failed: HTTP "
                                   f"{resp.status_code} {(resp.text or '')[:300]}")
            body = resp.json()
            items.extend(body.get("value", []))
            url = body.get("odata.nextLink") or body.get("@odata.nextLink")
            if not url:
                return items
        raise RuntimeError("Recycle bin listing exceeded the page limit; "
                           "refusing to continue with a partial list.")

    def delete_ids(self, ids: List[str]) -> Dict[str, str]:
        """Permanently delete (or advance to next stage) the given ids.
        Returns {id: 'ok' | 'failed: <reason>'}."""
        result: Dict[str, str] = {}
        resp = self._request("POST", f"{self.site}/_api/site/RecycleBin/DeleteByIds",
                             json_body={"ids": ids})
        if resp.status_code in (200, 204):
            return {i: "ok" for i in ids}
        # Fall back to one-by-one so a single bad item does not block the rest.
        for i in ids:
            r = self._request("POST",
                              f"{self.site}/_api/site/RecycleBin('{i}')/DeleteObject")
            result[i] = "ok" if r.status_code in (200, 204) else \
                f"failed: HTTP {r.status_code} {(r.text or '')[:120]}"
        return result


# --------------------------------------------------------------------------
# Selection logic (pure functions, unit-tested)
# --------------------------------------------------------------------------
def _norm(s: str) -> str:
    return unquote(s or "").replace("\\", "/").lower()


def item_path(it: Dict) -> str:
    d = (it.get("DirName") or "").strip("/")
    return f"{d}/{it.get('LeafName') or it.get('Title') or ''}".strip("/")


def parse_deleted_date(it: Dict) -> Optional[dt.datetime]:
    """Parse SharePoint's DeletedDate (UTC ISO 8601, with or without fractions)."""
    m = re.match(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})?$",
                 (it.get("DeletedDate") or "").strip())
    if not m:
        return None
    d = dt.datetime.fromisoformat(m.group(1))
    tz = m.group(2)
    if tz and tz != "Z":
        sign = 1 if tz[0] == "+" else -1
        d = d.replace(tzinfo=dt.timezone(sign * dt.timedelta(hours=int(tz[1:3]), minutes=int(tz[4:6]))))
    else:
        d = d.replace(tzinfo=dt.timezone.utc)
    return d


def select_items(items: List[Dict], stage: str, older_than_days: int,
                 path_contains: List[str], exclude_paths: List[str],
                 now: Optional[dt.datetime] = None) -> List[Dict]:
    """Items matching all filters. Items with an unreadable date are never selected."""
    now = now or dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(days=older_than_days)
    inc = [_norm(p) for p in path_contains]
    exc = [_norm(p) for p in exclude_paths]
    out = []
    for it in items:
        state = int(it.get("ItemState") or 0)
        if stage == "first" and state != STAGE_FIRST:
            continue
        if stage == "second" and state != STAGE_SECOND:
            continue
        d = parse_deleted_date(it)
        if d is None or d > cutoff:
            continue
        p = _norm(item_path(it))
        if inc and not any(x in p for x in inc):
            continue
        if any(x in p for x in exc):
            continue
        out.append(it)
    return out


def _size(it: Dict) -> int:
    try:
        return int(it.get("Size") or 0)
    except (TypeError, ValueError):
        return 0


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 1024 or unit == "TB":
            return f"{n:,.0f} {unit}" if unit == "B" else f"{n:,.2f} {unit}"
        n /= 1024
    return f"{n} B"


def summarize(items: List[Dict], print_fn=print, label="") -> None:
    total = sum(_size(i) for i in items)
    print_fn(f"{label}{len(items):,} item(s), {human(total)}")
    by_user: Dict[str, List[int]] = defaultdict(lambda: [0, 0])
    by_stage: Dict[str, List[int]] = defaultdict(lambda: [0, 0])
    for i in items:
        u = i.get("DeletedByName") or i.get("DeletedByEmail") or "(unknown)"
        by_user[u][0] += 1
        by_user[u][1] += _size(i)
        s = STAGE_LABEL.get(int(i.get("ItemState") or 0), "unknown")
        by_stage[s][0] += 1
        by_stage[s][1] += _size(i)
    for s, (c, b) in sorted(by_stage.items()):
        print_fn(f"    {s:<13} {c:>7,} item(s)  {human(b)}")
    print_fn("    deleted by (top 10 by size):")
    for u, (c, b) in sorted(by_user.items(), key=lambda kv: -kv[1][1])[:10]:
        print_fn(f"      {u}: {c:,} item(s), {human(b)}")


# --------------------------------------------------------------------------
# Audit log
# --------------------------------------------------------------------------
LOG_COLUMNS = ["run_utc", "action", "result", "id", "stage", "deleted_utc",
               "size_bytes", "deleted_by", "type", "path"]


class AuditLog:
    def __init__(self, log_dir: Path, tag: str):
        log_dir.mkdir(parents=True, exist_ok=True)
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d_%H%M%S")
        self.path = log_dir / f"recyclebin_{tag}_{stamp}.csv"
        self.run = stamp
        self._fh = open(self.path, "w", newline="", encoding="utf-8")
        self._w = csv.writer(self._fh)
        self._w.writerow(LOG_COLUMNS)

    def row(self, action: str, result: str, it: Dict) -> None:
        d = parse_deleted_date(it)
        self._w.writerow([
            self.run, action, result, it.get("Id"),
            STAGE_LABEL.get(int(it.get("ItemState") or 0), "unknown"),
            d.isoformat() if d else "", _size(it),
            it.get("DeletedByName") or it.get("DeletedByEmail") or "",
            it.get("ItemType"), item_path(it)])
        self._fh.flush()

    def close(self) -> None:
        self._fh.close()


# --------------------------------------------------------------------------
# Orchestration
# --------------------------------------------------------------------------
def run(client: RecycleBinClient, *, stage: str, older_than_days: int,
        path_contains: List[str], exclude_paths: List[str], execute: bool,
        assume_yes: bool, max_items: int, log_dir: Path,
        input_fn: Callable[[str], str] = input, print_fn=print) -> int:
    all_items = client.list_items()
    print_fn(f"Whole site collection recycle bin: {len(all_items):,} item(s), "
             f"{human(sum(_size(i) for i in all_items))}")
    chosen = select_items(all_items, stage, older_than_days, path_contains, exclude_paths)
    print_fn(f"Filters: stage={stage}, older than {older_than_days} day(s), "
             f"path contains={path_contains or 'any'}, excluding={exclude_paths or 'nothing'}")
    summarize(chosen, print_fn, label="Selected: ")

    log = AuditLog(log_dir, "execute" if execute else "dryrun")
    try:
        for it in chosen:
            log.row("selected" if execute else "would_delete", "", it)
        for it in chosen[:15]:
            print_fn(f"    {item_path(it)}  ({human(_size(it))}, "
                     f"{it.get('DeletedByName') or '?'})")
        if len(chosen) > 15:
            print_fn(f"    ... and {len(chosen) - 15:,} more (see the log)")

        if not chosen:
            print_fn("Nothing to do.")
            return 0
        if len(chosen) > max_items:
            print_fn(f"REFUSING: {len(chosen):,} items selected, above --max-items "
                     f"{max_items:,}. Narrow the filters or raise --max-items on purpose.")
            return 3
        if not execute:
            print_fn(f"DRY RUN -- nothing was deleted. Log: {log.path}\n"
                     f"Re-run with --execute to purge these items permanently.")
            return 0

        phrase = f"DELETE {len(chosen)}"
        if not assume_yes:
            print_fn("\nThis PERMANENTLY deletes the items above, including files deleted "
                     "by other people. It cannot be undone.")
            if input_fn(f"Type '{phrase}' to continue: ").strip() != phrase:
                print_fn("Confirmation did not match -- nothing was deleted.")
                return 3

        failures = 0
        done = 0
        first_pass_ids = [i["Id"] for i in chosen]
        by_id = {i["Id"]: dict(i) for i in chosen}   # snapshot: original stage/path for logging

        def purge(ids: List[str], label: str) -> None:
            nonlocal failures, done
            for k in range(0, len(ids), DELETE_CHUNK):
                chunk = ids[k:k + DELETE_CHUNK]
                res = client.delete_ids(chunk)
                for i in chunk:
                    r = res.get(i, "failed: no result")
                    log.row(label, r, by_id[i])
                    if r == "ok":
                        done += 1
                    else:
                        failures += 1
                print_fn(f"  {label}: {min(k + DELETE_CHUNK, len(ids)):,}/{len(ids):,}")

        purge(first_pass_ids, "delete_pass1")

        if stage == "all":
            # items from the first stage may now sit in the second stage; remove
            # only the ones WE selected, never anything else that is in there.
            remaining = client.list_items()
            again = [i["Id"] for i in remaining
                     if i["Id"] in by_id and int(i.get("ItemState") or 0) == STAGE_SECOND
                     and int(by_id[i["Id"]].get("ItemState") or 0) == STAGE_FIRST]
            if again:
                print_fn(f"{len(again):,} item(s) moved to the second stage; deleting them again...")
                purge(again, "delete_pass2")

        left = client.list_items()
        still = [i for i in left if i["Id"] in by_id]
        print_fn(f"Done. {done:,} delete call(s) ok, {failures:,} failed. "
                 f"{len(still):,} selected item(s) still visible "
                 f"({'second-stage or failed' if still else 'none'}). Log: {log.path}")
        return 1 if failures else 0
    finally:
        log.close()


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        description="Purge a SharePoint site collection recycle bin (dry run by default).")
    e = os.environ.get
    ap.add_argument("--site-url", default=e("SP_SITE_URL"))
    ap.add_argument("--tenant-id", default=e("SP_TENANT_ID"))
    ap.add_argument("--client-id", default=e("SP_APP_CLIENT_ID"))
    ap.add_argument("--cert-key-path", default=e("SP_CERT_KEY_PATH"))
    ap.add_argument("--cert-thumbprint", default=e("SP_CERT_THUMBPRINT"))
    ap.add_argument("--stage", choices=["first", "second", "all"], default="all",
                    help="Which bin stage to select (default: all). 'first' only moves "
                         "items to the second stage (quota NOT freed); 'second' and "
                         "'all' purge permanently.")
    ap.add_argument("--older-than-days", type=int, default=30,
                    help="Only items deleted more than N days ago (default 30; 0 = all).")
    ap.add_argument("--path-contains", action="append", default=[],
                    help="Only items whose original path contains this text (repeatable).")
    ap.add_argument("--exclude-path", action="append", default=[],
                    help="Never touch items whose original path contains this text.")
    ap.add_argument("--max-items", type=int, default=10000,
                    help="Refuse to run if more items than this are selected.")
    ap.add_argument("--execute", action="store_true",
                    help="Actually delete. Without this flag nothing is changed.")
    ap.add_argument("--yes", action="store_true",
                    help="Skip the typed confirmation (for scheduled runs).")
    ap.add_argument("--log-dir", default="recyclebin_logs")
    return ap


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    missing = [n for n, v in (("--site-url / SP_SITE_URL", args.site_url),
                              ("--tenant-id / SP_TENANT_ID", args.tenant_id),
                              ("--client-id / SP_APP_CLIENT_ID", args.client_id),
                              ("--cert-key-path / SP_CERT_KEY_PATH", args.cert_key_path),
                              ("--cert-thumbprint / SP_CERT_THUMBPRINT", args.cert_thumbprint))
               if not v]
    if missing:
        print("Missing configuration: " + ", ".join(missing), file=sys.stderr)
        return 2
    if args.older_than_days < 0:
        print("--older-than-days must be >= 0", file=sys.stderr)
        return 2
    try:
        provider = make_token_provider(args.site_url, args.tenant_id, args.client_id,
                                       args.cert_key_path, args.cert_thumbprint,
                                       os.environ.get("SP_CERT_PASSPHRASE"))
        client = RecycleBinClient(args.site_url, provider)
        return run(client, stage=args.stage, older_than_days=args.older_than_days,
                   path_contains=args.path_contains, exclude_paths=args.exclude_path,
                   execute=args.execute, assume_yes=args.yes, max_items=args.max_items,
                   log_dir=Path(args.log_dir))
    except ImportError as e:
        print(f"Missing Python package: {e}. Install with: pip install msal requests",
              file=sys.stderr)
        return 2
    except AbortRun as e:
        print(f"ABORTED: {e}", file=sys.stderr)
        return 2
    except (OSError, RuntimeError, requests.RequestException) as e:
        print(f"ERROR: {type(e).__name__}: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
