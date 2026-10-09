"""Offline orchestration tests for scripts/run_country_workflow.R.

A throw-away fake "repo" supplies stand-ins for the fetch / build / clean scripts, so the
REAL runner, the REAL find_workflow_home.R and the REAL country_run_helper.py are exercised
without any network or real data.  Run from the repo root:   python tests/test_country_run.py
Needs: Rscript with the processx package, python3.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
n = 0


def ok(desc, cond, extra=""):
    global n
    if not cond:
        raise SystemExit(f"FAILED: {desc} {extra}")
    n += 1
    print("  ok -", desc)


FAKE_FETCH = textwrap.dedent('''
    import os, sys, time, pathlib
    a = sys.argv
    base = pathlib.Path(a[a.index("--base-dir") + 1]); fid = a[a.index("--form-ids") + 1]
    (base / "logs" / "env_seen_fetch.txt").write_text(
        "RO=%s|ADMIN=%s|COUNTRY=%s|AI=%s|HOME=%s" % (
            os.environ.get("IM_READ_ONLY_SHAREPOINT"), os.environ.get("IM_ADMIN_CODES", ""),
            os.environ.get("IM_COUNTRY_CODES", ""), os.environ.get("ANTHROPIC_API_KEY", ""),
            os.environ.get("IM_WORKFLOW_HOME")))
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from _env_loader import load_secrets_env
    load_secrets_env(base)       # like the real script: must NOT bring the dashboard codes back
    (base / "logs" / "env_after_load.txt").write_text("ADMIN=%s|COUNTRY=%s|AI=%s|SMTP=%s|TENANT=%s" % (
        os.environ.get("IM_ADMIN_CODES", ""), os.environ.get("IM_COUNTRY_CODES", ""),
        os.environ.get("ANTHROPIC_API_KEY", ""), os.environ.get("SMTP_PASSWORD", ""),
        os.environ.get("SHAREPOINT_TENANT_ID", "")))
    mode = os.environ.get("FAKE_FETCH_MODE", "ok")
    print("Form %s | fetching page 1" % fid, flush=True)
    sys.stdout.buffer.write(b"caf\\xe9 bad byte line\\n"); sys.stdout.buffer.flush()
    print('  File "/usr/lib/python3/site-packages/x.py", line 5', flush=True)
    print("[sharepoint] Using https://worldhealthorg.sharepoint.com/sites/x token=abc123", flush=True)
    if mode == "hang":
        time.sleep(600)
    if mode == "fail_nodata":
        print("Traceback (most recent call last): boom with secret=XYZ", flush=True); sys.exit(3)
    (base / "data" / "raw" / (fid + ".parquet")).write_bytes(b"PAR1fake")
    if mode == "fail_keep":
        print("API connection failed", flush=True); sys.exit(2)
    print("Form %s | done" % fid, flush=True)
''')

FAKE_BUILD = textwrap.dedent('''
    home <- Sys.getenv("IM_WORKFLOW_HOME"); stopifnot(nzchar(home))
    source(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))), "find_workflow_home.R"))
    stopifnot(identical(normalizePath(find_workflow_home()), normalizePath(home)))
    stopifnot(Sys.getenv("IM_READ_ONLY_SHAREPOINT") == "1", Sys.getenv("IM_ADMIN_CODES") == "")
    stopifnot(file.exists(file.path(home, "data", "lookup", "lookup.xlsx")))
    if (Sys.getenv("FAKE_BUILD_MODE") == "fail") {
      message("Error: cannot read https://x.sharepoint.com/f with token=SECRET123"); quit(status = 1)
    }
    writeLines(c("country,v", "ANGOLA,1", "ANGOLA,2"), file.path(home, "data", "final", "Regional_IM_repository.csv"))
    write.csv(data.frame(file = "10267.parquet", rows_output = 2), file.path(home, "data", "final", "IM_processing_summary.csv"), row.names = FALSE)
''')

FAKE_CLEAN = textwrap.dedent('''
    home <- Sys.getenv("IM_WORKFLOW_HOME")
    if (Sys.getenv("FAKE_CLEAN_MODE") == "fail") quit(status = 1)
    d <- read.csv(file.path(home, "data", "final", "Regional_IM_repository.csv"))
    write.csv(d, file.path(home, "data", "final", "Regional_IM_repository_cleaned.csv"), row.names = FALSE)
''')


def make_repo(tmp: Path) -> Path:
    repo = tmp / "repo"
    (repo / "scripts").mkdir(parents=True)
    (repo / "config").mkdir()
    (repo / "data" / "lookup").mkdir(parents=True)
    (repo / "data" / "lookup" / "lookup.xlsx").write_bytes(b"fake-xlsx")
    (repo / "config" / "config.yaml").write_text("im: {}\n")
    (repo / "config" / "secrets.env").write_bytes(
        b"\xef\xbb\xbfIM_ADMIN_CODES=FILE-ADMIN-CODE-1\n# comment\nSHAREPOINT_TENANT_ID=tenant-xyz\nONA_API_TOKEN=ona-tok\n"
        b"IM_COUNTRY_CODES=AGO=FILE-CTRY-CODE\nANTHROPIC_API_KEY=sk-file-key\nSMTP_PASSWORD=smtp-pw\nALERT_EMAIL_TO=a@b.c\n"
        b"IM_ACCESS_MODE=open\nPOSIT_API_KEY=posit-key\nGITHUB_PAT=ghp_x\nSLACK_WEBHOOK_URL=https://hooks.example/x\n")
    for f in ("find_workflow_home.R", "country_run_helper.py", "_env_loader.py", "_sharepoint_client.py"):
        shutil.copy(SCRIPTS / f, repo / "scripts" / f)
    (repo / "scripts" / "Fetch_im_data.py").write_text(FAKE_FETCH)
    (repo / "scripts" / "regional_im_repository_builder.R").write_text(FAKE_BUILD)
    (repo / "scripts" / "clean_geonames.R").write_text(FAKE_CLEAN)
    return repo


def snapshot(p: Path):
    return sorted(str(x.relative_to(p)) for x in p.rglob("*") if "__pycache__" not in x.parts)


def run(repo, home, form="10267", env_extra=None, extra_args=(), timeout=240):
    env = dict(os.environ)
    env.update({"IM_ADMIN_CODES": "ADMIN-SECRET-1", "IM_COUNTRY_CODES": "AGO=ANG-SECRET-9",
                "ANTHROPIC_API_KEY": "sk-ant-secret", "IM_WORKFLOW_HOME": str(repo)})
    env.update(env_extra or {})
    cmd = ["Rscript", str(SCRIPTS / "run_country_workflow.R"), "--repo", str(repo),
           "--home", str(home), "--form-id", form, *extra_args]
    r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=timeout)
    return r.returncode, r.stdout + r.stderr


def result(home):
    return json.loads((Path(home) / "run_result.json").read_text())


FORBIDDEN = ["sharepoint", "token", "secret", "SECRET", "https://", "worldhealthorg", "Traceback", "ANG-SECRET", "ADMIN-SECRET"]

with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    repo = make_repo(tmp)
    before = snapshot(repo)

    print("happy path")
    home = tmp / "run1"
    code, out = run(repo, home)
    ok("exit 0", code == 0, out)
    r = result(home)
    ok("result ok + all steps ok", r["ok"] and (r["fetch"], r["build"], r["clean"]) == ("ok", "ok", "ok"), r)
    ok("cleaned csv + raw parquet delivered", (home / "data/final/Regional_IM_repository_cleaned.csv").exists()
       and (home / "data/raw/10267.parquet").exists())
    ok("row count reported", r["rows"] == 2, r)
    ok("campaign calendar was seeded", (home / "data/lookup/lookup.xlsx").read_bytes() == b"fake-xlsx")
    ok("children saw read-only mode, no codes, no API key, scratch home",
       (home / "logs/env_seen_fetch.txt").read_text() == f"RO=1|ADMIN=|COUNTRY=|AI=|HOME={home.resolve()}")
    ok("nothing sensitive in the dashboard-visible output", not any(w in out for w in FORBIDDEN), out)
    ok("progress shown without file-system paths / python frames", "/usr/lib" not in out and "site-packages" not in out, out)
    ok("progress lines present", "1/3 Fetching" in out and "2/3 Processing" in out and "3/3 Cleaning" in out and "DONE" in out, out)
    ok("the regional folder was not touched", snapshot(repo) == before)
    sc = (home / "config/secrets.env").read_text()
    ok("scratch secrets.env keeps only the SharePoint read settings",
       "SHAREPOINT_TENANT_ID=tenant-xyz" in sc and "ONA_API_TOKEN=ona-tok" in sc
       and not any(w in sc for w in ("IM_", "ANTHROPIC", "SMTP", "ALERT_", "POSIT", "GITHUB", "SLACK", "\ufeff")), sc)
    ok("a child that loads secrets.env cannot bring the dashboard codes / keys back",
       (home / "logs/env_after_load.txt").read_text() == "ADMIN=|COUNTRY=|AI=|SMTP=|TENANT=tenant-xyz",
       (home / "logs/env_after_load.txt").read_text())

    print("fetch fails but published data exists -> continue with a warning")
    home = tmp / "run2"
    code, out = run(repo, home, env_extra={"FAKE_FETCH_MODE": "fail_keep"})
    r = result(home)
    ok("still succeeds", code == 0 and r["ok"], out)
    ok("fetch marked warning", r["fetch"] == "warning" and "could not be refreshed" in out, out)

    print("fetch fails with no data -> clean failure")
    home = tmp / "run3"
    code, out = run(repo, home, env_extra={"FAKE_FETCH_MODE": "fail_nodata"})
    r = result(home)
    ok("exit 1 and result not ok", code == 1 and not r["ok"] and r["fetch"] == "failed", out)
    ok("error text is filtered (no secret/traceback/url)", not any(w in out for w in FORBIDDEN), out)
    ok("build/clean never ran", r["build"] == "pending" and r["clean"] == "pending")

    print("build fails")
    home = tmp / "run4"
    code, out = run(repo, home, env_extra={"FAKE_BUILD_MODE": "fail"})
    r = result(home)
    ok("exit 1, build failed, clean pending", code == 1 and r["build"] == "failed" and r["clean"] == "pending", out)
    ok("child error output is filtered", "SECRET123" not in out and "sharepoint" not in out.lower(), out)
    ok("full log kept privately in the scratch folder", "SECRET123" in (home / "logs/step2_build.txt").read_text())

    print("clean fails")
    home = tmp / "run5"
    code, out = run(repo, home, env_extra={"FAKE_CLEAN_MODE": "fail"})
    ok("exit 1, no cleaned file", code == 1 and not result(home)["ok"] and result(home)["clean"] == "failed", out)

    print("time limit")
    home = tmp / "run6"
    code, out = run(repo, home, env_extra={"FAKE_FETCH_MODE": "hang"}, extra_args=("--timeouts", "0.05,5,5"))
    ok("hung fetch is killed and reported", code == 1 and "time limit" in out, out)

    print("argument safety")
    for bad in ("abc", "12;rm", "../1", "", "1 2"):
        code, out = run(repo, tmp / "run7", form=bad)
        ok(f"form id {bad!r} refused", code == 2, out)
    code, out = run(repo, repo)
    ok("refuses to use the workflow folder as scratch", code == 2 and "scratch" in out, out)
    ok("regional folder still untouched after all runs", snapshot(repo) == before)

print(f"\nAll {n} country-run checks passed.")
