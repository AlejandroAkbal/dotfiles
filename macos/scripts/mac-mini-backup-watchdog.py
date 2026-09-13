#!/usr/bin/env python3
"""Alert only when the macOS backup has stopped working."""
import datetime as dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

LABEL = f"gui/{os.getuid()}/com.alejandro.mac-mini-backup"
STATE = Path.home() / ".local/state/mac-mini-backup/status"
ALERT_STATE_FILE = Path.home() / ".local/state/mac-mini-backup/watchdog_alert.json"
MAX_AGE = dt.timedelta(hours=30)
EMAIL_SCRIPT = Path.home() / ".hermes/scripts/send-email.py"
ALERT_RECIPIENT = "alexromero652@gmail.com"


def launchd_report():
    p = subprocess.run(["/bin/launchctl", "print", LABEL], text=True, capture_output=True)
    if p.returncode:
        return "", f"launchd is not loaded: {p.stderr.strip() or p.stdout.strip()}"
    return p.stdout, None


def send_alert_email(problems: list[str]):
    # Cooldown check: don't re-email identical problems more than once every 12 hours
    now = dt.datetime.now(dt.timezone.utc)
    fingerprint = "|".join(sorted(problems))
    if ALERT_STATE_FILE.exists():
        try:
            state = json.loads(ALERT_STATE_FILE.read_text())
            last_fp = state.get("fingerprint")
            last_sent = dt.datetime.fromisoformat(state.get("sent_at"))
            if last_fp == fingerprint and (now - last_sent) < dt.timedelta(hours=12):
                return
        except Exception:
            pass

    body = (
        "Mac mini backup watchdog detected critical issues:\n\n"
        + "\n".join(f"- {p}" for p in problems)
        + f"\n\nChecked at: {now.isoformat()}\nState file: {STATE}\n"
    )
    if EMAIL_SCRIPT.exists():
        subprocess.run(
            [
                sys.executable,
                str(EMAIL_SCRIPT),
                "--to",
                ALERT_RECIPIENT,
                "--subject",
                "⚠️ [Alert] Mac mini backup watchdog failure",
                "--body",
                body,
            ],
            capture_output=True,
            text=True,
        )
    ALERT_STATE_FILE.write_text(json.dumps({"fingerprint": fingerprint, "sent_at": now.isoformat()}))


def clear_alert_state():
    if ALERT_STATE_FILE.exists():
        try:
            ALERT_STATE_FILE.unlink(missing_ok=True)
        except Exception:
            pass


def main():
    problems = []
    report, error = launchd_report()
    if error:
        problems.append(error)
    else:
        exit_match = re.search(r"last exit code = (\d+)", report)
        if exit_match and exit_match.group(1) != "0":
            problems.append(f"last launchd exit code was {exit_match.group(1)}")
        if '"Hour" => 0' not in report or '"Minute" => 0' not in report:
            problems.append("launchd schedule is not midnight daily")

    values = {}
    try:
        values = dict(
            line.split("=", 1)
            for line in STATE.read_text().splitlines()
            if "=" in line
        )
    except OSError as exc:
        problems.append(f"status file unavailable: {exc}")

    if values.get("status") != "success":
        problems.append(f"status is {values.get('status', 'missing')}")
    finished = values.get("finished")
    if finished:
        try:
            when = dt.datetime.fromisoformat(finished.replace("Z", "+00:00"))
            age = dt.datetime.now(dt.timezone.utc) - when.astimezone(dt.timezone.utc)
            if age > MAX_AGE:
                problems.append(f"last success is {age.days} days old")
        except ValueError:
            problems.append("status has an invalid finished timestamp")
    elif values.get("status") == "success":
        problems.append("successful status has no finished timestamp")

    if problems:
        alert_msg = "Mac mini backup watchdog alert:\n- " + "\n- ".join(problems)
        print(alert_msg)
        send_alert_email(problems)
        sys.exit(1)
    else:
        clear_alert_state()


if __name__ == "__main__":
    main()
