#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
send_failure_alert.py
Sends a short email when the nightly IM workflow run fails, so a failure
during an unattended overnight run (Mon-Fri 11pm, see
run_workflow_nightly.bat) doesn't sit unnoticed until someone happens to
open the dashboard the next day.

Called from two places:
  - run_workflow.R, right where it detects a hard failure (Repository
    Builder failed/not found, or an --upload-only run's upload failing),
    passing a specific --subject/--body-file describing what happened.
  - run_workflow_nightly.bat, as a fallback ONLY if Rscript exited non-zero
    AND run_workflow.R's own alert above did not already fire (checked via
    logs/last_alert_sent.flag) -- this catches a crash severe enough that
    run_workflow.R never reached its own alert code (e.g. a missing R
    package, or Rscript failing to start at all).

Credentials are never hardcoded here (this file is tracked in git) -- set
them once via a local, git-ignored config/secrets.env file (copy
config/secrets.env.example), or via `setx` / `export` in your shell, same
convention as upload_to_sharepoint.py.

Best-effort by design: if credentials are missing or the send fails, this
prints a clear warning and exits non-zero, but never raises in a way that
could be mistaken for the pipeline itself failing -- alerting must never
become a second thing that can break a pipeline run.
"""

import argparse
import os
import smtplib
import ssl
import sys
from email.mime.text import MIMEText

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _env_loader import load_secrets_env


def send_alert(base_dir: str, subject: str, body: str) -> bool:
    load_secrets_env(base_dir)

    from_addr = os.environ.get("ALERT_EMAIL_FROM", "").strip()
    to_addr = os.environ.get("ALERT_EMAIL_TO", "").strip()
    app_password = os.environ.get("ALERT_EMAIL_APP_PASSWORD", "").strip()
    smtp_host = os.environ.get("ALERT_SMTP_HOST", "").strip() or "smtp.gmail.com"
    smtp_port_raw = os.environ.get("ALERT_SMTP_PORT", "").strip() or "587"

    if not from_addr or not to_addr or not app_password:
        print(
            "WARNING: Failure alert NOT sent - ALERT_EMAIL_FROM / ALERT_EMAIL_TO / "
            "ALERT_EMAIL_APP_PASSWORD are not all set. Copy "
            "config/secrets.env.example to config/secrets.env and fill them "
            "in to enable email alerts. (The pipeline run itself is unaffected.)",
            file=sys.stderr,
        )
        return False

    try:
        smtp_port = int(smtp_port_raw)
    except ValueError:
        print(f"WARNING: Failure alert NOT sent - ALERT_SMTP_PORT is not a number: {smtp_port_raw!r}", file=sys.stderr)
        return False

    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_addr

    try:
        context = ssl.create_default_context()
        with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
            server.starttls(context=context)
            server.login(from_addr, app_password)
            server.sendmail(from_addr, [to_addr], msg.as_string())
        print(f"Failure alert emailed to {to_addr}")
        return True
    except Exception as e:
        print(f"WARNING: Failure alert NOT sent (send error): {e!r}", file=sys.stderr)
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Email a failure alert for the IM workflow.")
    parser.add_argument(
        "--base-dir",
        default=os.environ.get("IM_WORKFLOW_HOME", "C:/Users/TOURE/Documents/im_workflow"),
        help="im_workflow base directory (default: %(default)s)",
    )
    parser.add_argument("--subject", required=True, help="Email subject line.")
    parser.add_argument("--body", help="Alert body text (short, single-line messages only).")
    parser.add_argument(
        "--body-file",
        help="Path to a file containing the alert body -- preferred for multi-line content, "
             "since quoting a multi-line string on the Windows command line is unreliable.",
    )
    args = parser.parse_args()

    if args.body_file:
        with open(args.body_file, "r", encoding="utf-8") as f:
            body = f.read()
    elif args.body:
        body = args.body
    else:
        parser.error("one of --body or --body-file is required")
        return

    ok = send_alert(args.base_dir, args.subject, body)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
