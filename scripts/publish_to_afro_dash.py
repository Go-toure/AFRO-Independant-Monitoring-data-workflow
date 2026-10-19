#!/usr/bin/env python3
"""
Step 6b (opt-in) of the IM workflow: publish the AFRO-Dash IM data file.

Commits and pushes ONLY  input/AFRO_IM_data.rds  in the AFRO-Dash repository, which
makes Posit Connect Cloud redeploy the dashboard. Nothing else in that repository is
touched (other pending changes are left alone) and it never force-pushes.

Runs only when requested:  Rscript scripts/run_workflow.R --push-afro-dash
(or IM_PUSH_AFRO_DASH=1 for scheduled runs).  Try it first with --dry-run.

    python scripts/publish_to_afro_dash.py --dry-run
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

WORKFLOW = Path(os.environ.get("IM_WORKFLOW_HOME") or Path(__file__).resolve().parent.parent)
DEFAULT_DASH = WORKFLOW.parent / "AFRO-Dash"
TARGET = "input/AFRO_IM_data.rds"


def log(msg):
    print(f"[publish-afro-dash] {msg}", flush=True)


def git(repo, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "").rstrip("\r\n"), (r.stderr or "").strip()


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

    rc, status, err = git(repo, "status", "--porcelain", "--", TARGET)
    if rc != 0:
        log(f"ERROR: git status failed: {err}")
        return 1
    if not status.strip():
        log("IM data file unchanged - nothing to publish.")
        return 0
    log(f"Changed: {status.strip()}")
    if args.dry_run:
        log("Dry run - nothing committed or pushed.")
        return 0

    msg = args.message or f"Refresh IM Overview data (automated {datetime.now():%Y-%m-%d %H:%M})"
    for step in (("add", "--", TARGET), ("commit", "-m", msg, "--", TARGET)):
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
