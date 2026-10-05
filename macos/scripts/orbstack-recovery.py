#!/usr/bin/env python3
"""Recover OrbStack and the Coolify VM after user-session or VM failures.

Three host-side failure modes are handled distinctly, because the correct action
differs for each:

  * stopped   - the app or its daemon is gone      -> launch the app / start the VM
  * unhealthy - daemon up, VM up, ingress failing  -> restart the VM (cheap, in-guest)
  * wedged    - daemon alive but not serving       -> SIGKILL the host processes and relaunch

A wedged OrbStack (VM kernel livelock, logged by OrbStack itself as
`sampling stacks due to VM hang`) leaves the host processes alive and spinning. In
that state `open -a OrbStack` is a no-op and every `orbctl` call blocks on the dead
daemon, so only killing the host processes recovers it. This supervisor escalates to
that, and then alerts and exits non-zero once its escalation budget is spent, instead
of retrying the same inert action forever.
"""

import collections
import fcntl
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ORBCTL = "/usr/local/bin/orbctl"
OPEN = "/usr/bin/open"
ROUTE = "/sbin/route"
CURL = "/usr/bin/curl"
KILLALL = "/usr/bin/killall"
SYSCTL = "/usr/sbin/sysctl"
ORB_APP = "/Applications/OrbStack.app"
VM_NAME = "coolify-node"
INGRESS_HOST = "9router.akbal.dev"
INGRESS_URL = f"https://{INGRESS_HOST}/api/health"
DOCKER_SOCK = Path.home() / ".orbstack/run/docker.sock"
VMGR_LOG = Path.home() / ".orbstack/log/vmgr.log"
BACKUP_LOCK = Path.home() / ".local/state/mac-mini-backup/backup.lock"
ALERT_SCRIPT = Path.home() / ".hermes/scripts/send-email.py"
ALERT_TO = "alexromero652@gmail.com"
SYSTEM_PYTHON = "/usr/bin/python3"

VMGR_HANG_MARKER = "sampling stacks due to VM hang"
VMGR_TIME_RE = re.compile(r'time="(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})"')
HARD_KILL_PROCESSES = ("OrbStack Helper", "OrbStack")


class OrbStackRecovery:
    def __init__(
        self,
        state_path: Optional[Path] = None,
        log_path: Optional[Path] = None,
        lock_path: Optional[Path] = None,
        cooldown_seconds: int = 600,
        restart_after: int = 2,
        hard_restart_after: int = 4,
        hard_kill_window: int = 3600,
        hard_kill_budget: int = 2,
        boot_grace_seconds: int = 180,
        hang_marker_window: int = 240,
        orbctl_timeout: int = 8,
        docker_probe_timeout: float = 3.0,
        readiness_timeout: int = 180,
        backup_skip_alert_after: int = 15,
        alert_to: str = ALERT_TO,
        alert_script: Path = ALERT_SCRIPT,
    ):
        home = Path.home()
        self.state_path = state_path or home / ".local/var/lib/orbstack-recovery/state.json"
        self.log_path = log_path or home / ".local/var/log/orbstack-recovery.log"
        self.lock_path = lock_path or home / ".local/var/run/orbstack-recovery.lock"
        self.cooldown_seconds = cooldown_seconds
        self.restart_after = restart_after
        self.hard_restart_after = hard_restart_after
        self.hard_kill_window = hard_kill_window
        self.hard_kill_budget = hard_kill_budget
        self.boot_grace_seconds = boot_grace_seconds
        self.hang_marker_window = hang_marker_window
        self.orbctl_timeout = orbctl_timeout
        self.docker_probe_timeout = docker_probe_timeout
        self.readiness_timeout = readiness_timeout
        self.backup_skip_alert_after = backup_skip_alert_after
        self.alert_to = alert_to
        self.alert_script = alert_script

    # ------------------------------------------------------------------- state

    @staticmethod
    def default_state() -> Dict[str, Any]:
        return {
            "ingress_failures": 0,
            "last_action": 0,
            "hard_kills": [],
            "alerted_gave_up": False,
            "alerted_escalation": False,
            "backup_skips": 0,
            "alerted_backup_skips": False,
        }

    def load_state(self) -> Dict[str, Any]:
        state = self.default_state()
        try:
            data = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (OSError, ValueError, TypeError):
            return state
        if not isinstance(data, dict):
            return state
        try:
            state["ingress_failures"] = max(0, int(data.get("ingress_failures", 0)))
            state["last_action"] = int(data.get("last_action", 0))
        except (TypeError, ValueError):
            pass
        kills = data.get("hard_kills", [])
        if isinstance(kills, list):
            cleaned: List[int] = []
            for item in kills:
                try:
                    cleaned.append(int(item))
                except (TypeError, ValueError):
                    continue
            state["hard_kills"] = cleaned
        for key in ("alerted_gave_up", "alerted_escalation", "alerted_backup_skips"):
            state[key] = bool(data.get(key, False))
        try:
            state["backup_skips"] = max(0, int(data.get("backup_skips", 0)))
        except (TypeError, ValueError):
            pass
        return state

    def save_state(self, state: Dict[str, Any]) -> None:
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

    def log(self, message: str) -> None:
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %z")
        with self.log_path.open("a", encoding="utf-8") as handle:
            handle.write(f"[{timestamp}] {message}\n")

    def tail_log(self, lines: int) -> str:
        try:
            with self.log_path.open("r", encoding="utf-8", errors="replace") as handle:
                return "".join(collections.deque(handle, maxlen=lines)).strip()
        except OSError:
            return "(no recovery log available)"

    # ----------------------------------------------------------------- helpers

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

    def boot_time(self) -> Optional[int]:
        try:
            result = self.run([SYSCTL, "-n", "kern.boottime"], timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            return None
        match = re.search(r"sec\s*=\s*(\d+)", result.stdout)
        return int(match.group(1)) if match else None

    def within_boot_grace(self, now: int) -> bool:
        boot = self.boot_time()
        if boot is None:
            return False
        return (now - boot) < self.boot_grace_seconds

    def backup_in_progress(self) -> bool:
        """A backup holds `backup.lock` for its whole run; only the flock proves that.

        This deliberately does NOT use `pgrep -f mac-mini-backup`: that matched any
        other process whose command line merely contained the string (a diagnostic
        shell, a delegated agent's prompt) and silently disabled recovery. Observed
        twice on 2026-10-05, during the outage this supervisor failed to fix.
        """
        try:
            handle = BACKUP_LOCK.open("r+")
        except FileNotFoundError:
            return False
        except OSError:
            return False
        with handle:
            try:
                fcntl.lockf(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except (BlockingIOError, OSError):
                return True
            fcntl.lockf(handle, fcntl.LOCK_UN)
        return False

    # --------------------------------------------------------------- detection

    def docker_sock_state(self) -> str:
        """Probe the OrbStack Docker socket: 'ok', 'down' or 'wedged'.

        'wedged' is a socket that accepts the connection and then never answers, or
        closes it without a response - the signature of an OrbStack VM that hung
        while the host-side processes stayed alive.
        """
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                sock.settimeout(self.docker_probe_timeout)
                sock.connect(str(DOCKER_SOCK))
                sock.sendall(b"GET /_ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
                chunks = []
                total = 0
                while total < 4096:
                    data = sock.recv(1024)
                    if not data:
                        break
                    chunks.append(data)
                    total += len(data)
        except (FileNotFoundError, ConnectionRefusedError, NotADirectoryError):
            return "down"
        except (socket.timeout, TimeoutError, OSError):
            return "wedged"
        payload = b"".join(chunks)
        return "ok" if b"OK" in payload else "wedged"

    def orbctl_status(self) -> str:
        """'running', 'down', or 'timeout' when the daemon accepted nothing at all."""
        try:
            result = self.run([ORBCTL, "status"], timeout=self.orbctl_timeout)
        except subprocess.TimeoutExpired:
            return "timeout"
        except OSError:
            return "down"
        return "running" if result.returncode == 0 else "down"

    def orb_running(self) -> bool:
        return self.orbctl_status() == "running"

    def vm_state(self) -> str:
        try:
            result = self.run([ORBCTL, "list"], timeout=self.orbctl_timeout)
        except (OSError, subprocess.TimeoutExpired):
            return "unknown"
        if result.returncode != 0:
            return "unknown"
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) >= 2 and fields[0] == VM_NAME:
                return fields[1].lower()
        return "absent"

    @staticmethod
    def parse_vmgr_time(line: str, now: Optional[int] = None) -> Optional[int]:
        match = VMGR_TIME_RE.search(line)
        if not match:
            return None
        month, day, hour, minute, second = (int(group) for group in match.groups())
        reference = datetime.fromtimestamp(now) if now is not None else datetime.now()
        try:
            stamp = reference.replace(
                month=month, day=day, hour=hour, minute=minute, second=second, microsecond=0
            )
        except ValueError:
            return None
        candidate = int(stamp.timestamp())
        reference_ts = now if now is not None else time.time()
        if candidate - reference_ts > 86400:
            # The vmgr log carries no year, so a stamp "in the future" means the line
            # predates the new year. Roll the year back exactly - subtracting 366 days
            # is off by one in every non-leap year - and refuse on Feb 29.
            try:
                stamp = stamp.replace(year=stamp.year - 1)
            except ValueError:
                return None
            candidate = int(stamp.timestamp())
        return candidate

    def vmgr_hang_marker(self, now: Optional[int] = None) -> bool:
        """True when OrbStack itself logged a VM hang inside the recent window."""
        try:
            with VMGR_LOG.open("r", encoding="utf-8", errors="replace") as handle:
                lines = list(collections.deque(handle, maxlen=400))
        except OSError:
            return False
        reference = int(now if now is not None else time.time())
        for line in reversed(lines):
            if VMGR_HANG_MARKER not in line:
                continue
            stamp = self.parse_vmgr_time(line, reference)
            if stamp is None:
                return True
            return (reference - stamp) <= self.hang_marker_window
        return False

    def _probe_ingress_once(self) -> bool:
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

    def ingress_ok(self) -> bool:
        if self._probe_ingress_once():
            return True
        time.sleep(3)
        return self._probe_ingress_once()

    # ------------------------------------------------------------------ alerts

    def alert(self, subject: str, body: str) -> bool:
        if not os.access(str(self.alert_script), os.X_OK):
            self.log(f"WARN alert channel unavailable: {self.alert_script}")
            return False
        try:
            result = self.run(
                [
                    SYSTEM_PYTHON,
                    str(self.alert_script),
                    "--to",
                    self.alert_to,
                    "--subject",
                    f"[OrbStack] {subject}",
                    "--body",
                    body,
                ],
                timeout=90,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            self.log(f"ERROR alert delivery failed: {exc}")
            return False
        if result.returncode != 0:
            self.log(f"ERROR alert delivery failed: {result.stderr.strip()}")
            return False
        self.log(f"ALERT delivered: {subject}")
        return True

    # ----------------------------------------------------------------- actions

    def open_orbstack_app(self) -> bool:
        self.log("ACTION launch OrbStack app")
        try:
            launched = self.run([OPEN, "-gj", "-a", ORB_APP], timeout=15)
        except (OSError, subprocess.TimeoutExpired) as exc:
            self.log(f"ERROR launching OrbStack: {exc}")
            return False
        if launched.returncode != 0:
            self.log(f"ERROR launching OrbStack: {launched.stderr.strip()}")
            return False
        return True

    def launch_orbstack(self) -> bool:
        if not self.open_orbstack_app():
            return False
        for _ in range(12):
            time.sleep(5)
            if self.orbctl_status() == "running":
                if self.vm_state() == "stopped":
                    return self.start_vm()
                return True
        self.log("ERROR OrbStack did not become ready within 60 seconds")
        return False

    def kill_orbstack(self) -> bool:
        """Force-kill the wedged host processes - the only action that recovers them."""
        ok = True
        for name in HARD_KILL_PROCESSES:
            try:
                result = self.run([KILLALL, "-9", name], timeout=15)
            except (OSError, subprocess.TimeoutExpired) as exc:
                self.log(f"ERROR killing {name}: {exc}")
                ok = False
                continue
            if result.returncode in (0, 1):  # 1 == nothing matched, also acceptable
                self.log(f"KILLED {name}")
            else:
                self.log(f"ERROR killing {name}: rc={result.returncode} {result.stderr.strip()}")
                ok = False
        time.sleep(3)
        return ok

    def wait_for_recovery(self, timeout: int) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            time.sleep(5)
            if self.orbctl_status() == "running" and self._probe_ingress_once():
                return True
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

    # -------------------------------------------------------------- escalation

    def count_failure(self, state: Dict[str, Any], now: int) -> None:
        state["ingress_failures"] = int(state["ingress_failures"]) + 1
        state["hard_kills"] = self.prune_hard_kills(list(state["hard_kills"]), now)
        self.save_state(state)

    def reset_failures(self, state: Dict[str, Any], now: int) -> None:
        state["ingress_failures"] = 0
        state["last_action"] = now
        self.save_state(state)

    def escalate(self, state: Dict[str, Any], now: int, reason: str) -> str:
        if len(state["hard_kills"]) >= self.hard_kill_budget:
            return self.give_up(state, now, reason)
        if self.in_cooldown(state, now):
            self.log("SKIP hard restart during recovery cooldown")
            return "cooldown"
        return self.hard_restart(state, now, reason)

    def prune_hard_kills(self, kills: List[int], now: int) -> List[int]:
        return [stamp for stamp in kills if now - stamp < self.hard_kill_window]

    def in_cooldown(self, state: Dict[str, Any], now: int) -> bool:
        return (now - int(state.get("last_action", 0))) < self.cooldown_seconds

    def hard_restart(self, state: Dict[str, Any], now: int, reason: str) -> str:
        attempt = len(state["hard_kills"]) + 1
        self.log(
            f"ACTION hard restart OrbStack: reason={reason} "
            f"attempt={attempt}/{self.hard_kill_budget} in {self.hard_kill_window}s window"
        )
        self.kill_orbstack()
        launched = self.open_orbstack_app()
        state["hard_kills"] = self.prune_hard_kills(list(state["hard_kills"]) + [now], now)
        state["last_action"] = now
        self.save_state(state)

        if launched and self.wait_for_recovery(self.readiness_timeout):
            state["ingress_failures"] = 0
            state["alerted_gave_up"] = False
            self.save_state(state)
            self.log(f"OK hard restart recovered OrbStack (reason={reason})")
            recovered = True
        else:
            self.log(f"ERROR hard restart did not restore ingress within {self.readiness_timeout}s")
            recovered = False

        if not state["alerted_escalation"]:
            state["alerted_escalation"] = True
            self.save_state(state)
            self.alert(
                "OrbStack was wedged; escalated to a hard restart",
                "\n".join(
                    [
                        f"outcome: {'recovered' if recovered else 'NOT recovered'}",
                        f"reason: {reason}",
                        f"attempt: {attempt}/{self.hard_kill_budget} in {self.hard_kill_window}s window",
                        f"host: {socket.gethostname()}",
                        "",
                        "Recent recovery log:",
                        self.tail_log(15),
                    ]
                ),
            )
        return "hard_restarted" if recovered else "hard_restart_failed"

    def give_up(self, state: Dict[str, Any], now: int, reason: str) -> str:
        self.log(
            f"ERROR giving up: reason={reason}; {len(state['hard_kills'])}/"
            f"{self.hard_kill_budget} hard restarts spent in the last {self.hard_kill_window}s"
        )
        if not state["alerted_gave_up"]:
            state["alerted_gave_up"] = True
            self.save_state(state)
            self.alert(
                "OrbStack cannot be recovered automatically",
                "\n".join(
                    [
                        "OmniRoute ingress is failing and the hard-restart budget is spent.",
                        "The supervisor keeps probing and re-arms when the window rolls over.",
                        "",
                        f"reason: {reason}",
                        f"hard_kills_in_window: {state['hard_kills']}",
                        f"host: {socket.gethostname()}",
                        "",
                        "Recent recovery log:",
                        self.tail_log(25),
                    ]
                ),
            )
        return "gave_up"

    def note_backup_skip(self, state: Dict[str, Any]) -> None:
        """Count cycles spent unable to act because `backup.lock` is held.

        Called only once ingress is already known to be failing, so a long backup
        against a broken VM can never silence the outage.
        """
        state["backup_skips"] = int(state["backup_skips"]) + 1
        self.save_state(state)
        if (
            state["backup_skips"] >= self.backup_skip_alert_after
            and not state["alerted_backup_skips"]
        ):
            state["alerted_backup_skips"] = True
            self.save_state(state)
            self.alert(
                "recovery paused by backup.lock while OmniRoute is down",
                "\n".join(
                    [
                        f"ingress has been failing and recovery has been skipped",
                        f"{state['backup_skips']} consecutive cycles because mac-mini-backup",
                        "holds backup.lock.",
                        "",
                        "Recent recovery log:",
                        self.tail_log(15),
                    ]
                ),
            )

    # ------------------------------------------------------------------- cycle

    def run_cycle(self, now: Optional[int] = None) -> str:
        now = int(now if now is not None else time.time())
        state = self.load_state()

        if not self.host_network_ok():
            self.log("SKIP host network unhealthy")
            return "network_unhealthy"

        if self.within_boot_grace(now):
            self.log("SKIP within boot grace window")
            return "boot_grace"

        # Probe first so a long backup can never hide whether ingress is actually up;
        # a held lock pauses remediation, not detection.
        if self.ingress_ok():
            if (
                state["ingress_failures"]
                or state["alerted_gave_up"]
                or state["alerted_escalation"]
                or state["backup_skips"]
            ):
                state["ingress_failures"] = 0
                state["alerted_gave_up"] = False
                state["alerted_escalation"] = False
                state["backup_skips"] = 0
                state["alerted_backup_skips"] = False
                self.save_state(state)
            self.log(f"OK {VM_NAME}={self.vm_state()} ingress=healthy")
            return "healthy"

        if self.backup_in_progress():
            self.note_backup_skip(state)
            self.log("SKIP backup in progress (backup.lock held)")
            return "backup_in_progress"

        status = self.orbctl_status()
        sock_state = self.docker_sock_state()
        hang = self.vmgr_hang_marker(now)
        wedged = sock_state == "wedged" or hang or status == "timeout"
        if sock_state == "wedged":
            reason = "docker_sock_wedged"
        elif hang:
            reason = "vmgr_hang_marker"
        elif status == "timeout":
            reason = "orbctl_timeout"
        else:
            reason = f"orb={status} docker={sock_state}"

        self.log(f"WARN ingress unhealthy orb={status} docker={sock_state} vmgr_hang={hang}")

        # Only a wedged daemon justifies a hard kill, so this path escalates immediately
        # and never routes through the launch logic below.
        if wedged:
            self.count_failure(state, now)
            return self.escalate(state, now, reason)

        # Cleanly stopped: launching is the correct action, and a count of failed L7
        # probes must never turn into a SIGKILL for a daemon that is simply not up.
        if status != "running":
            if self.in_cooldown(state, now):
                self.log("SKIP OrbStack launch during recovery cooldown")
                return "cooldown"
            if self.launch_orbstack():
                self.reset_failures(state, now)
                return "orbstack_started"
            return "orbstack_start_failed"

        vm_state = self.vm_state()
        if vm_state == "absent":
            self.log(f"ERROR {VM_NAME} is absent")
            return "vm_absent"
        # A slow boot must not be mistaken for ill health, so nothing is counted here.
        if vm_state == "starting":
            self.log(f"WAIT {VM_NAME}=starting; not counting this cycle")
            return "vm_starting"
        if vm_state == "stopped":
            if self.in_cooldown(state, now):
                self.log(f"SKIP {VM_NAME} start during recovery cooldown")
                return "cooldown"
            if self.start_vm():
                self.reset_failures(state, now)
                return "vm_started"
            return "vm_start_failed"
        if vm_state != "running":
            self.log(f"WARN {VM_NAME} state={vm_state}; deferring recovery")
            return "vm_unknown"

        # Daemon up, VM running, ingress failing: this is the state escalation is for.
        self.count_failure(state, now)
        failures = int(state["ingress_failures"])
        self.log(f"WARN ingress unhealthy {failures} consecutive (daemon up, {VM_NAME}=running)")
        if failures >= self.hard_restart_after:
            return self.escalate(state, now, reason)
        if failures < self.restart_after:
            return "ingress_failure"
        if self.in_cooldown(state, now):
            self.log("SKIP VM restart during recovery cooldown")
            return "cooldown"
        if self.restart_vm():
            self.reset_failures(state, now)
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


def main(argv: Optional[List[str]] = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if "--test-alert" in argv:
        recovery = OrbStackRecovery()
        delivered = recovery.alert(
            "test alert",
            "Synthetic alert from orbstack-recovery.py --test-alert; no failure occurred.",
        )
        print(json.dumps({"result": "alert_sent" if delivered else "alert_failed"}))
        return 0 if delivered else 1
    try:
        result = OrbStackRecovery().run_locked()
    except Exception as exc:
        OrbStackRecovery().log(f"ERROR unhandled recovery failure: {exc}")
        print(json.dumps({"result": "error", "error": str(exc)}), file=sys.stderr)
        return 1
    print(json.dumps({"result": result}))
    return 1 if result == "gave_up" else 0


if __name__ == "__main__":
    raise SystemExit(main())
