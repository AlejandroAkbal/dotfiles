#!/usr/bin/env python3
"""Recover OrbStack and the Coolify VM after user-session or VM failures."""

import fcntl
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

ORBCTL = "/usr/local/bin/orbctl"
OPEN = "/usr/bin/open"
ROUTE = "/sbin/route"
CURL = "/usr/bin/curl"
ORB_APP = "/Applications/OrbStack.app"
VM_NAME = "coolify-node"
INGRESS_HOST = "9router.akbal.dev"
INGRESS_URL = f"https://{INGRESS_HOST}/api/health"


class OrbStackRecovery:
    def __init__(
        self,
        state_path: Optional[Path] = None,
        log_path: Optional[Path] = None,
        lock_path: Optional[Path] = None,
        cooldown_seconds: int = 600,
        restart_after: int = 2,
    ):
        home = Path.home()
        self.state_path = state_path or home / ".local/var/lib/orbstack-recovery/state.json"
        self.log_path = log_path or home / ".local/var/log/orbstack-recovery.log"
        self.lock_path = lock_path or home / ".local/var/run/orbstack-recovery.lock"
        self.cooldown_seconds = cooldown_seconds
        self.restart_after = restart_after

    def log(self, message: str) -> None:
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
        with self.log_path.open("a", encoding="utf-8") as handle:
            handle.write(f"[{timestamp}] {message}\n")

    def run(self, args: List[str], timeout: int = 15) -> subprocess.CompletedProcess:
        return subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
            env={**os.environ, "HOME": str(Path.home())},
        )

    def load_state(self) -> Dict[str, int]:
        default = {"ingress_failures": 0, "last_action": 0}
        try:
            data = json.loads(self.state_path.read_text(encoding="utf-8"))
            return {
                "ingress_failures": int(data.get("ingress_failures", 0)),
                "last_action": int(data.get("last_action", 0)),
            }
        except (OSError, ValueError, TypeError):
            return default

    def save_state(self, state: Dict[str, int]) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp_name = tempfile.mkstemp(prefix="state.", dir=str(self.state_path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(state, handle, sort_keys=True)
                handle.write("\n")
            os.replace(tmp_name, self.state_path)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)

    def default_gateway(self) -> Optional[str]:
        try:
            result = self.run([ROUTE, "-n", "get", "default"], timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            return None
        for line in result.stdout.splitlines():
            if "gateway:" in line:
                return line.split("gateway:", 1)[1].strip()
        return None

    @staticmethod
    def tcp_probe(host: str, port: int, timeout: float = 2.0) -> bool:
        try:
            with socket.create_connection((host, port), timeout=timeout):
                return True
        except OSError:
            return False

    def host_network_ok(self) -> bool:
        gateway = self.default_gateway()
        if not gateway:
            return False
        gateway_ok = any(self.tcp_probe(gateway, port) for port in (53, 80, 443, 8443))
        internet_ok = any(self.tcp_probe(host, 53) for host in ("1.1.1.1", "8.8.8.8"))
        return gateway_ok and internet_ok

    def orb_running(self) -> bool:
        try:
            return self.run([ORBCTL, "status"], timeout=15).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            return False

    def vm_state(self) -> str:
        try:
            result = self.run([ORBCTL, "list"], timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            return "unknown"
        if result.returncode != 0:
            return "unknown"
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) >= 2 and fields[0] == VM_NAME:
                return fields[1].lower()
        return "absent"

    def ingress_ok(self) -> bool:
        try:
            result = self.run(
                [
                    CURL,
                    "-skS",
                    "--max-time",
                    "8",
                    "--resolve",
                    f"{INGRESS_HOST}:443:127.0.0.1",
                    INGRESS_URL,
                ],
                timeout=10,
            )
        except (OSError, subprocess.TimeoutExpired):
            return False
        if result.returncode != 0:
            return False
        try:
            payload = json.loads(result.stdout)
        except (ValueError, TypeError):
            return False
        return payload.get("status") == "ok"

    def launch_orbstack(self) -> bool:
        self.log("ACTION launch OrbStack")
        try:
            launched = self.run([OPEN, "-gj", "-a", ORB_APP], timeout=15)
        except (OSError, subprocess.TimeoutExpired) as exc:
            self.log(f"ERROR launching OrbStack: {exc}")
            return False
        if launched.returncode != 0:
            self.log(f"ERROR launching OrbStack: {launched.stderr.strip()}")
            return False
        for _ in range(12):
            time.sleep(5)
            if self.orb_running():
                state = self.vm_state()
                if state == "stopped":
                    return self.start_vm()
                return True
        self.log("ERROR OrbStack did not become ready within 60 seconds")
        return False

    def start_vm(self) -> bool:
        self.log(f"ACTION start {VM_NAME}")
        try:
            result = self.run([ORBCTL, "start", VM_NAME], timeout=45)
        except (OSError, subprocess.TimeoutExpired) as exc:
            self.log(f"ERROR starting {VM_NAME}: {exc}")
            return False
        if result.returncode != 0:
            self.log(f"ERROR starting {VM_NAME}: {result.stderr.strip()}")
            return False
        return True

    def restart_vm(self) -> bool:
        self.log(f"ACTION restart {VM_NAME} after {self.restart_after} failed ingress probes")
        try:
            result = self.run([ORBCTL, "restart", VM_NAME], timeout=60)
        except (OSError, subprocess.TimeoutExpired) as exc:
            self.log(f"ERROR restarting {VM_NAME}: {exc}")
            return False
        if result.returncode != 0:
            self.log(f"ERROR restarting {VM_NAME}: {result.stderr.strip()}")
            return False
        return True

    def run_cycle(self, now: Optional[int] = None) -> str:
        now = int(now if now is not None else time.time())
        state = self.load_state()

        if not self.host_network_ok():
            self.log("SKIP host network unhealthy")
            return "network_unhealthy"

        in_cooldown = now - state["last_action"] < self.cooldown_seconds
        if not self.orb_running():
            if in_cooldown:
                self.log("SKIP OrbStack unavailable during recovery cooldown")
                return "cooldown"
            if self.launch_orbstack():
                state.update({"ingress_failures": 0, "last_action": now})
                self.save_state(state)
                return "orbstack_started"
            return "orbstack_start_failed"

        vm_state = self.vm_state()
        if vm_state == "absent":
            self.log(f"ERROR {VM_NAME} is absent")
            return "vm_absent"
        if vm_state == "starting":
            self.log(f"WAIT {VM_NAME}=starting")
            return "vm_starting"
        if vm_state == "stopped":
            if in_cooldown:
                self.log(f"SKIP {VM_NAME} state={vm_state} during recovery cooldown")
                return "cooldown"
            if self.start_vm():
                state.update({"ingress_failures": 0, "last_action": now})
                self.save_state(state)
                return "vm_started"
            return "vm_start_failed"
        if vm_state != "running":
            self.log(f"WARN {VM_NAME} state={vm_state}; deferring recovery")
            return "vm_unknown"

        if self.ingress_ok():
            if state["ingress_failures"]:
                state["ingress_failures"] = 0
                self.save_state(state)
            self.log(f"OK {VM_NAME}=running ingress=healthy")
            return "healthy"

        state["ingress_failures"] += 1
        self.save_state(state)
        self.log(
            f"WARN ingress unhealthy {state['ingress_failures']}/{self.restart_after} "
            f"with {VM_NAME}=running"
        )
        if state["ingress_failures"] < self.restart_after:
            return "ingress_failure"
        if in_cooldown:
            self.log("SKIP VM restart during recovery cooldown")
            return "cooldown"
        if self.restart_vm():
            state.update({"ingress_failures": 0, "last_action": now})
            self.save_state(state)
            return "vm_restarted"
        return "vm_restart_failed"

    def run_locked(self) -> str:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        with self.lock_path.open("w", encoding="utf-8") as lock_handle:
            try:
                fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                self.log("SKIP another recovery cycle is still running")
                return "locked"
            return self.run_cycle()


def main() -> int:
    try:
        result = OrbStackRecovery().run_locked()
        print(json.dumps({"result": result}))
        return 0
    except Exception as exc:
        OrbStackRecovery().log(f"ERROR unhandled recovery failure: {exc}")
        print(json.dumps({"result": "error", "error": str(exc)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
