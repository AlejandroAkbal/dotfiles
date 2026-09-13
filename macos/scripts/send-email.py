#!/usr/bin/env python3
"""Send an email via Google Workspace CLI (gws)."""
import argparse
import base64
import json
import os
import subprocess
import sys
from email.mime.text import MIMEText


def main() -> int:
    parser = argparse.ArgumentParser(description="Send an email via gws CLI")
    parser.add_argument("--to", required=True, help="Recipient email address")
    parser.add_argument("--subject", required=True, help="Email subject")
    parser.add_argument("--body", required=True, help="Email body content")
    parser.add_argument("--html", action="store_true", help="Send as HTML email")
    args = parser.parse_args()

    gws_bin = os.getenv("HERMES_GWS_BIN", "/opt/homebrew/bin/gws")
    msg = MIMEText(args.body, "html" if args.html else "plain", "utf-8")
    msg["To"] = args.to
    msg["From"] = "sa.alejandro.romero@gmail.com"
    msg["Subject"] = args.subject

    raw_b64 = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    payload = json.dumps({"raw": raw_b64})

    cmd = [
        gws_bin,
        "gmail",
        "users",
        "messages",
        "send",
        "--params",
        json.dumps({"userId": "me"}),
        "--json",
        payload,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error sending email: {res.stderr or res.stdout}", file=sys.stderr)
        return res.returncode

    print(f"Email sent successfully to {args.to}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
