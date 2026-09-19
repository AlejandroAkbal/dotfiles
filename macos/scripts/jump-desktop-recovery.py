#!/usr/bin/env python3
"""Bootstrap and monitor Jump Desktop's user agent in Aqua user session domain (gui/501)."""

import datetime
import os
import subprocess
import sys
from pathlib import Path

LABEL = "com.p5sys.jump.connect.agent"
PLIST_PATH = "/Library/LaunchAgents/com.p5sys.jump.connect.agent.plist"
LOG_DIR = Path.home() / ".local/var/log"
LOG_FILE = LOG_DIR / "jump-desktop-recovery.log"


def log(msg: str) -> None:
    now = datetime.datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
    line = f"[{now}] {msg}\n"
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass
    print(line, end="")


def get_gui_domain() -> str:
    return f"gui/{os.getuid()}"


def is_agent_loaded(domain: str, label: str = LABEL) -> bool:
    try:
        res = subprocess.run(
            ["/bin/launchctl", "print", f"{domain}/{label}"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return res.returncode == 0
    except Exception as e:
        log(f"WARN launchctl print check failed: {e}")
        return False


def bootstrap_agent(domain: str, plist_path: str = PLIST_PATH) -> bool:
    if not Path(plist_path).exists():
        log(f"ERROR Plist not found: {plist_path}")
        return False
    try:
        res = subprocess.run(
            ["/bin/launchctl", "bootstrap", domain, plist_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if res.returncode == 0:
            log(f"SUCCESS Bootstrapped {plist_path} into {domain}")
            # Ensure agent spawns if notifyd was already posted before bootstrap
            try:
                subprocess.run(
                    ["/bin/launchctl", "kickstart", f"{domain}/{LABEL}"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
            except Exception:
                pass
            return True
        # Spurious 5 (EIO) or 17 (already loaded) can happen if racing launchd
        if is_agent_loaded(domain):
            log(f"NOTICE Agent confirmed loaded despite bootstrap exit {res.returncode}")
            return True
        log(f"ERROR bootstrap failed exit={res.returncode}: {res.stderr.strip()}")
        return False
    except Exception as e:
        log(f"ERROR Exception during bootstrap: {e}")
        return False


def run_cycle() -> str:
    domain = get_gui_domain()
    if is_agent_loaded(domain):
        log(f"OK {LABEL} is loaded in {domain}")
        return "healthy"

    log(f"TRIGGER {LABEL} is missing from {domain}. Bootstrapping...")
    if bootstrap_agent(domain):
        if is_agent_loaded(domain):
            log(f"OK Verified {LABEL} loaded after bootstrap in {domain}")
            return "recovered"
        log(f"WARN Bootstrap reported success but {LABEL} not detected in {domain}")
        return "verify_failed"
    return "bootstrap_failed"


if __name__ == "__main__":
    result = run_cycle()
    sys.exit(0 if result in ("healthy", "recovered") else 1)
