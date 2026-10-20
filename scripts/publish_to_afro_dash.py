#!/usr/bin/env python3
"""
Step 6b (opt-in) of the IM workflow: publish the AFRO-Dash IM data file.

Commits and pushes ONLY the IM data files in the AFRO-Dash repository, which makes Posit Connect Cloud redeploy
the dashboard:  input/AFRO_IM_data.rds,  input/AFRO_snapshot_stats_IM.csv,  the per-country settlement files
input/<formid>.csv.gz (rebuilt here from data/raw by AFRO-Dash/tools/build_settlement_inputs.py) and manifest.json
(checksums refreshed for exactly those files). Nothing else in that repository is touched (other pending changes
are left alone) and it never force-pushes.

Runs only when requested:  Rscript scripts/run_workflow.R --push-afro-dash
(or IM_PUSH_AFRO_DASH=1 for scheduled runs).  Try it first with --dry-run.

    python scripts/publish_to_afro_dash.py --dry-run
"""

import argparse
import glob
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

WORKFLOW = Path(os.environ.get("IM_WORKFLOW_HOME") or Path(__file__).resolve().parent.parent)
DEFAULT_DASH = WORKFLOW.parent / "AFRO-Dash"
TARGET = "input/AFRO_IM_data.rds"
STATS_TARGET = "input/AFRO_snapshot_stats_IM.csv"   # raw-data counts for the Snapshot landing page
TARGETS = [TARGET, STATS_TARGET]


def log(msg):
    print(f"[publish-afro-dash] {msg}", flush=True)


def git(repo, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "").rstrip("\r\n"), (r.stderr or "").strip()


def refresh_snapshot_stats(repo):
    """Recompute the raw-data counts (submissions, settlements, facilities) for the Snapshot page.
    Soft-fail: a problem here never blocks the IM data publish."""
    script = repo / "tools" / "snapshot_stats.py"
    if not script.exists():
        log(f"WARNING: {script} not found - Snapshot raw-data counts not refreshed.")
        return
    cmd = [sys.executable, str(script), "--source", "IM",
           "--raw-dir", str(WORKFLOW / "data" / "raw"),
           "--country-forms", str(WORKFLOW / "config" / "country_forms.csv"),
           "--out", str(repo / STATS_TARGET)]
    log("Refreshing Snapshot raw-data counts (IM)...")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    tail = (r.stdout or "").strip().splitlines()[-3:]
    for line in tail:
        log("  " + line)
    if r.returncode != 0:
        log(f"WARNING: snapshot_stats.py failed ({(r.stderr or '').strip()[-300:]}) - keeping the previous counts.")


def refresh_settlement_inputs(repo):
    """Rebuild input/<formid>.csv.gz (IM Settlement Maps tab) from the raw parquet files.
    Soft-fail: a problem here never blocks the IM data publish; forms that fail keep their previous file."""
    script = repo / "tools" / "build_settlement_inputs.py"
    if not script.exists():
        log(f"WARNING: {script} not found - settlement files not refreshed.")
        return
    cmd = [sys.executable, str(script),
           "--raw-dir", str(WORKFLOW / "data" / "raw"), "--out-dir", str(repo / "input")]
    cf = WORKFLOW / "config" / "country_forms.csv"
    if cf.exists():
        cmd += ["--country-forms", str(cf)]
    log("Rebuilding the settlement-level files (IM Settlement Maps)...")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    lines = (r.stdout or "").strip().splitlines()
    for line in [l for l in lines if "FAILED" in l or "REFUSED" in l or l.startswith("done")][-12:]:
        log("  " + line.strip())
    if r.returncode != 0:
        log(f"WARNING: build_settlement_inputs.py failed ({(r.stderr or '').strip()[-300:]}) - keeping the previous files.")


def settlement_files(repo):
    return sorted(p.relative_to(repo).as_posix() for p in (repo / "input").glob("*.csv.gz") if p.name[:-7].isdigit())


def update_manifest(repo, paths):
    """Refresh the Posit Connect manifest.json checksums of `paths` (added if missing). Returns True if the file changed."""
    mf = repo / "manifest.json"
    if not mf.exists():
        return False
    raw = mf.read_text(encoding="utf-8")
    m = json.loads(raw)
    files = m.setdefault("files", {})
    for rel in paths:
        f = repo / rel
        if f.exists():
            files[rel] = {"checksum": hashlib.md5(f.read_bytes()).hexdigest()}
    m["files"] = dict(sorted(files.items()))
    new = json.dumps(m, indent=2) + ("\n" if raw.endswith("\n") else "")
    if new == raw:
        return False
    with open(mf, "w", encoding="utf-8", newline="") as fh:
        fh.write(new)
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=f"Commit and push {TARGET} only.")
    ap.add_argument("--repo", default=os.environ.get("AFRO_DASH_REPO") or str(DEFAULT_DASH))
    ap.add_argument("--branch", default="main")
    ap.add_argument("--message", default="")
    ap.add_argument("--dry-run", action="store_true", help="show what would be published, change nothing")
    args = ap.parse_args(sys.argv[1:] if argv is None else argv)

    repo = Path(args.repo)
    if not (repo / ".git").exists():
        log(f"ERROR: not a git repository: {repo}")
        return 1
    if not (repo / TARGET).exists():
        log(f"ERROR: {repo / TARGET} does not exist - run scripts/export_afro_dash_data.R first.")
        return 1
    rc, branch, err = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    branch = branch.strip()
    if rc != 0:
        log(f"ERROR: cannot read the current branch: {err}")
        return 1
    if branch != args.branch:
        log(f"ERROR: AFRO-Dash is on branch '{branch}', expected '{args.branch}'. Nothing published.")
        return 1

    # manifest.json is committed whole, so it must not carry someone else's pending edits: if it is already modified
    # (e.g. app.R was changed and not yet committed), publish only the IM data files and leave the settlement files alone.
    rc, mstat, _ = git(repo, "status", "--porcelain", "--", "manifest.json")
    manifest_clean = rc == 0 and not mstat.strip()
    if not manifest_clean:
        log("WARNING: AFRO-Dash/manifest.json has uncommitted changes - settlement files and the manifest are NOT "
            "published this time (commit or discard the manifest changes first).")

    if not args.dry_run:
        refresh_snapshot_stats(repo)
        if manifest_clean:
            refresh_settlement_inputs(repo)

    data_targets = [t for t in TARGETS if (repo / t).exists()]
    extra = (settlement_files(repo) + ["manifest.json"]) if manifest_clean and (repo / "manifest.json").exists() else []
    if manifest_clean and not args.dry_run and update_manifest(repo, data_targets + [e for e in extra if e != "manifest.json"]):
        log("manifest.json checksums refreshed.")
    existing = data_targets + extra
    rc, status, err = git(repo, "status", "--porcelain", "--", *existing)
    if rc != 0:
        log(f"ERROR: git status failed: {err}")
        return 1
    if not status.strip():
        log("IM data and Snapshot counts unchanged - nothing to publish.")
        return 0
    log(f"Changed: {status.strip()}")
    if args.dry_run:
        log("Dry run - nothing committed or pushed.")
        return 0

    msg = args.message or f"Refresh IM Overview data (automated {datetime.now():%Y-%m-%d %H:%M})"
    for step in (("add", "--", *existing), ("commit", "-m", msg, "--", *existing)):
        rc, out, err = git(repo, *step)
        if rc != 0:
            log(f"ERROR: git {step[0]} failed: {err or out}")
            return 1

    rc, out, err = git(repo, "push", "origin", args.branch)
    if rc != 0:
        log("Push was rejected (GitHub has newer commits) - rebasing onto origin and retrying once.")
        rc, out, err = git(repo, "pull", "--rebase", "--autostash", "origin", args.branch)
        if rc != 0:
            git(repo, "rebase", "--abort")
            log("ERROR: rebase hit a conflict and was aborted. Your commit is saved locally, "
                f"nothing was lost. Resolve it in {repo} (git pull --rebase) and push.")
            return 1
        rc, out, err = git(repo, "push", "origin", args.branch)
        if rc != 0:
            log(f"ERROR: push failed after rebase: {err or out}")
            return 1
    _, sha, _ = git(repo, "rev-parse", "--short", "HEAD")
    log(f"Published as {sha.strip()}. Posit Connect Cloud will redeploy the dashboard.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
