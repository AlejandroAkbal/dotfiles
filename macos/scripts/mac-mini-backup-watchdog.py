#!/usr/bin/env python3
"""Alert only when the macOS backup has stopped working."""
import datetime as dt
import os
import re
import subprocess
from pathlib import Path

LABEL = f"gui/{os.getuid()}/com.alejandro.mac-mini-backup"
STATE = Path.home() / ".local/state/mac-mini-backup/status"
MAX_AGE = dt.timedelta(hours=30)


def launchd_report():
    p = subprocess.run(["/bin/launchctl", "print", LABEL], text=True, capture_output=True)
    if p.returncode:
        return "", f"launchd is not loaded: {p.stderr.strip() or p.stdout.strip()}"
    return p.stdout, None


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
        print("Mac mini backup watchdog alert:\n- " + "\n- ".join(problems))


if __name__ == "__main__":
    main()
