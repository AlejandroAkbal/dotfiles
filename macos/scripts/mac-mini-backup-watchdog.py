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
MAX_RUNTIME = dt.timedelta(hours=3)  # ponytail: raise only if normal runs approach this
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
        "The nightly Mac mini backup is not healthy:\n\n"
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
                "Mac mini backup needs attention",
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


def parse_time(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(dt.timezone.utc)
    except ValueError:
        return None


def age_text(age):
    minutes = max(0, int(age.total_seconds() // 60))
    if minutes < 60:
        return f"{minutes} minutes"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes}m"


def main():
    problems = []
    report, error = launchd_report()
    values = {}
    try:
        values = dict(
            line.split("=", 1)
            for line in STATE.read_text().splitlines()
            if "=" in line
        )
    except OSError as exc:
        problems.append(f"status file unavailable: {exc}")

    now = dt.datetime.now(dt.timezone.utc)
    status = values.get("status")
    started = parse_time(values.get("started"))
    finished = parse_time(values.get("finished"))
    active = "\tstate = running" in report
    exit_match = re.search(r"last exit code = (\d+)", report)
    exit_code = exit_match.group(1) if exit_match else None

    if error:
        problems.append(error)
    elif '"Hour" => 0' not in report or '"Minute" => 0' not in report:
        problems.append("launchd schedule is not midnight daily")

    if active:
        if status == "running" and started and now - started > MAX_RUNTIME:
            problems.append(f"backup has been running for {age_text(now - started)}; it is likely stuck")
    elif status == "running":
        when = values.get("started", "an unknown time")
        age = f" ({age_text(now - started)} ago)" if started else ""
        result = f"; launchd exited with code {exit_code}" if exit_code and exit_code != "0" else ""
        problems.append(f"backup started at {when}{age} but never completed{result}")
    elif status == "failure":
        code = values.get("exit_code") or exit_code or "unknown"
        problems.append(f"last backup failed with exit code {code}")
    elif status == "success":
        if not finished:
            problems.append("last backup says success but has no completion time")
        elif now - finished > MAX_AGE:
            problems.append(f"no successful backup for {age_text(now - finished)}")
    elif values:
        problems.append(f"backup status is invalid: {status or 'missing'}")

    if problems:
        alert_msg = "Mac mini backup watchdog alert:\n- " + "\n- ".join(problems)
        print(alert_msg)
        send_alert_email(problems)
        sys.exit(1)
    else:
        clear_alert_state()


if __name__ == "__main__":
    main()
