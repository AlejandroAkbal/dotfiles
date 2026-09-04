#!/usr/bin/env python3
"""
Headless Host & VM Self-Healing Watchdog
----------------------------------------
Deterministic, zero-LLM health checker and recovery daemon for macOS headless hosts.

Key Invariants:
1. Cadence: 300s (5m) via LaunchDaemon.
2. Cloudflared Native Health:
   Queries cloudflared's built-in metrics/readiness API (`http://127.0.0.1:20241/ready`).
   Verifies active tunnel connections (`readyConnections > 0`).
3. Local Origin Probe:
   Verifies local web/ingress listener (`https://127.0.0.1:443`).
4. Dynamic Gateway Discovery:
   Automatically detects current default gateway via `route -n get default`.
5. Link & Interface Recovery (Layer 1):
   If Ethernet stalls, loses valid IP (including 169.254.x.x APIPA), or loses gateway/WAN reachability,
   bounces en0 (`/sbin/ifconfig en0 down && sleep 2 && /sbin/ifconfig en0 up`).
6. Tailscale Session-Aware Recovery (Layer 2):
   Restarts Tailscale cleanly inside user GUI session if backend state degrades.
7. Anti-Bootloop Safeguards:
   - State stored in `/var/db/headless-watchdog/state.json` (persists across reboots).
   - Max 2 host reboots per rolling 24 hours.
   - 30-minute post-reboot cooldown.
   - Minimum 20-minute uptime requirement before reboot can trigger (safe fallback to 0.0 on error).
"""

import sys
import os
import time
import json
import socket
import subprocess
import urllib.request
import urllib.error
import ssl
from pathlib import Path

# Explicit system binary paths for root LaunchDaemon environment
IFCONFIG_BIN = "/sbin/ifconfig"
SYSCTL_BIN = "/usr/sbin/sysctl"
SHUTDOWN_BIN = "/sbin/shutdown"
ROUTE_BIN = "/sbin/route"
LAUNCHCTL_BIN = "/bin/launchctl"
TAILSCALE_BIN = "/usr/local/bin/tailscale"

DEFAULT_CONFIG = {
    "mode": "FULL",  # "DRY_RUN", "SOFT", "FULL"
    "check_interval_seconds": 300,
    "consecutive_threshold_interface": 1,  # 5 minutes before interface bounce
    "consecutive_threshold_service": 2,    # 10 minutes before service restart
    "consecutive_threshold_reboot": 3,     # 15 minutes before host reboot
    "max_reboots_24h": 2,
    "reboot_cooldown_seconds": 1800,       # 30 minutes
    "min_uptime_before_reboot": 1200,      # 20 minutes minimum uptime required
    "service_cooldown_seconds": 600,       # 10 minutes
    "interface_cooldown_seconds": 300,     # 5 minutes
    "state_file": "/var/db/headless-watchdog/state.json",
    "log_file": "/var/log/headless-watchdog.log",
    "interface": "en0",
    "targets": {
        "fallback_gateway_ip": "192.168.50.1",
        "gateway_ports": [80, 8443, 53],
        "public_dns": [("1.1.1.1", 53), ("8.8.8.8", 53), ("9.9.9.9", 53)],
        "local_ssh_port": 22,
        "local_web_port": 443,
        "cloudflared_metrics_port": 20241,
    }
}


def log(message: str, log_file_path: str):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S %Z")
    entry = f"[{timestamp}] {message}"
    print(entry)
    try:
        with open(log_file_path, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass


def get_system_uptime_seconds() -> float:
    """Returns uptime in seconds. Returns 0.0 on failure to safely enforce min_uptime check."""
    try:
        res = subprocess.run([SYSCTL_BIN, "-n", "kern.boottime"], capture_output=True, text=True, timeout=5)
        out = res.stdout
        if "sec =" in out:
            sec_str = out.split("sec =")[1].split(",")[0].strip()
            return max(0.0, time.time() - float(sec_str))
    except Exception:
        pass
    return 0.0


def get_default_gateway_ip(fallback: str = "192.168.50.1") -> str:
    try:
        res = subprocess.run([ROUTE_BIN, "-n", "get", "default"], capture_output=True, text=True, timeout=5)
        for line in res.stdout.splitlines():
            if "gateway:" in line:
                gw = line.split("gateway:")[1].strip()
                if gw and not gw.startswith("link#"):
                    return gw
    except Exception:
        pass
    return fallback


def is_process_running(process_name: str) -> bool:
    try:
        res = subprocess.run(["pgrep", "-f", process_name], capture_output=True, text=True, timeout=5)
        return res.returncode == 0 and len(res.stdout.strip()) > 0
    except Exception:
        return False


def get_interface_has_valid_ip(interface: str = "en0") -> bool:
    """Returns True only if interface has a real routable IPv4 (rejects 127.x and 169.254.x APIPA)."""
    try:
        res = subprocess.run([IFCONFIG_BIN, interface], capture_output=True, text=True, timeout=5)
        if res.returncode != 0:
            return False
        for line in res.stdout.splitlines():
            line = line.strip()
            if line.startswith("inet "):
                parts = line.split()
                if len(parts) >= 2:
                    ip = parts[1]
                    if not ip.startswith("127.") and not ip.startswith("169.254."):
                        return True
        return False
    except Exception:
        return False


def tcp_probe(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except Exception:
        return False


def probe_lan_gateway(ip: str, ports: list, timeout: float = 2.0) -> bool:
    for p in ports:
        if tcp_probe(ip, p, timeout=timeout):
            return True
    return False


def http_local_origin_probe(port: int = 443, host_header: str = "9router.akbal.dev", timeout: float = 3.0) -> bool:
    """Probes local Traefik/OmniRoute listener on localhost:443."""
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        url = f"https://127.0.0.1:{port}/"
        req = urllib.request.Request(url, headers={"Host": host_header, "User-Agent": "WatchdogLocalProbe/1.0"})
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
            return resp.status < 500
    except urllib.error.HTTPError as e:
        return e.code < 500
    except Exception:
        return False


def check_cloudflared_ready(port: int = 20241, timeout: float = 2.0) -> tuple:
    """Queries cloudflared's internal /ready API to verify active edge tunnel connections."""
    try:
        url = f"http://127.0.0.1:{port}/ready"
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            data = json.loads(resp.read().decode())
            ready_connections = data.get("readyConnections", 0)
            return (ready_connections > 0, ready_connections)
    except Exception:
        return (False, 0)


def check_tailscale_status(timeout: float = 3.0) -> bool:
    """Checks Tailscale engine status via CLI."""
    tailscale_paths = [TAILSCALE_BIN, "/usr/bin/tailscale", "/opt/homebrew/bin/tailscale"]
    for ts in tailscale_paths:
        if Path(ts).exists():
            try:
                res = subprocess.run([ts, "status", "--json"], capture_output=True, text=True, timeout=timeout)
                if res.returncode == 0:
                    data = json.loads(res.stdout)
                    backend_state = data.get("BackendState", "")
                    return backend_state in ["Running", "Starting"]
            except Exception:
                pass
    return False


def load_state(state_file_path: str) -> dict:
    default_state = {
        "consecutive_failures": {
            "interface_ip": 0,
            "lan": 0,
            "dns": 0,
            "tunnel": 0,
            "tailscale": 0,
            "vm_listeners": 0
        },
        "last_action_timestamp": {
            "interface_bounce": 0,
            "tunnel_restart": 0,
            "vm_restart": 0,
            "tailscale_restart": 0,
            "host_reboot": 0
        },
        "reboot_history": []
    }
    try:
        p = Path(state_file_path)
        if p.exists():
            data = json.loads(p.read_text())
            for k, v in default_state.items():
                if k not in data:
                    data[k] = v
            return data
    except Exception:
        pass
    return default_state


def save_state(state: dict, state_file_path: str):
    try:
        p = Path(state_file_path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(state, indent=2))
    except Exception:
        pass


def execute_action(action_name: str, cmd: list, mode: str, log_file: str) -> bool:
    if mode == "DRY_RUN":
        log(f"[DRY-RUN] Would execute: {' '.join(cmd)}", log_file)
        return True
    log(f"[EXECUTE] Running: {' '.join(cmd)}", log_file)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        log(f"[EXECUTE] Result ({action_name}) exit={res.returncode}: {res.stdout.strip()} {res.stderr.strip()}", log_file)
        return res.returncode == 0
    except Exception as e:
        log(f"[EXECUTE] Error executing {action_name}: {e}", log_file)
        return False


def run_health_cycle(raw_cfg = None) -> dict:
    cfg = DEFAULT_CONFIG.copy()
    if raw_cfg:
        for k, v in raw_cfg.items():
            if isinstance(v, dict) and k in cfg and isinstance(cfg[k], dict):
                cfg[k] = {**cfg[k], **v}
            else:
                cfg[k] = v

    mode = cfg.get("mode", "FULL")
    log_file = cfg.get("log_file", DEFAULT_CONFIG["log_file"])
    state_file = cfg.get("state_file", DEFAULT_CONFIG["state_file"])
    targets = cfg.get("targets", DEFAULT_CONFIG["targets"])
    interface = cfg.get("interface", "en0")
    now = time.time()
    uptime = get_system_uptime_seconds()

    state = load_state(state_file)
    cf = state["consecutive_failures"]
    last_act = state["last_action_timestamp"]

    # 1. Probes
    has_ip = get_interface_has_valid_ip(interface)
    gateway_ip = get_default_gateway_ip(targets.get("fallback_gateway_ip", "192.168.50.1"))
    lan_ok = probe_lan_gateway(gateway_ip, targets["gateway_ports"], timeout=2.0)
    
    dns_results = [tcp_probe(h, p, timeout=3.0) for h, p in targets["public_dns"]]
    internet_ok = any(dns_results)
    
    tunnel_proc = is_process_running("cloudflared")
    tunnel_ready, active_conns = check_cloudflared_ready(port=targets.get("cloudflared_metrics_port", 20241))
    local_origin_ok = http_local_origin_probe(port=targets["local_web_port"])
    tunnel_ok = tunnel_proc and tunnel_ready

    tailscale_ok = check_tailscale_status()

    ssh_ok = tcp_probe("127.0.0.1", targets["local_ssh_port"], timeout=2.0)
    web_ok = tcp_probe("127.0.0.1", targets["local_web_port"], timeout=2.0)
    vm_listeners_ok = ssh_ok and web_ok

    log(f"[PROBE] InterfaceIP({interface})={has_ip} | Gateway({gateway_ip})={lan_ok} | WAN_DNS={internet_ok} | TunnelReady={tunnel_ok} (ReadyConns={active_conns}, LocalOrigin={local_origin_ok}) | Tailscale={tailscale_ok} | VM_Listeners={vm_listeners_ok} | Uptime={int(uptime)}s", log_file)

    # 2. Update Failure Counters
    cf["interface_ip"] = 0 if has_ip else cf.get("interface_ip", 0) + 1
    cf["lan"] = 0 if lan_ok else cf["lan"] + 1
    cf["dns"] = 0 if internet_ok else cf["dns"] + 1
    cf["tunnel"] = 0 if tunnel_ok else cf["tunnel"] + 1
    cf["tailscale"] = 0 if tailscale_ok else cf["tailscale"] + 1
    cf["vm_listeners"] = 0 if vm_listeners_ok else cf["vm_listeners"] + 1

    actions_taken = []

    # 3. Decision Matrix & Recovery Actions
    
    # Layer 1: Interface / Link Recovery (Fixes router reboot stall & 169.254 APIPA)
    # Trigger if interface has invalid/no IP or if both LAN gateway and Internet are down
    if (not has_ip or (not lan_ok and not internet_ok)) and (cf["interface_ip"] >= cfg["consecutive_threshold_interface"] or cf["lan"] >= cfg["consecutive_threshold_interface"]):
        last_if_act = last_act.get("interface_bounce", 0)
        if now - last_if_act > cfg["interface_cooldown_seconds"]:
            log(f"[TRIGGER] Local network interface stalled (ValidIP={has_ip}, LAN={lan_ok}, DNS={internet_ok}). Bouncing {interface}...", log_file)
            cmd = ["/bin/sh", "-c", f"{IFCONFIG_BIN} {interface} down && sleep 2 && {IFCONFIG_BIN} {interface} up"]
            execute_action("interface_bounce", cmd, mode, log_file)
            last_act["interface_bounce"] = now
            actions_taken.append("interface_bounce")

    # Layer 2: Service-Level Restarts
    if lan_ok or internet_ok:
        # Tunnel Restart (tunnel process dead or 0 ready connections to Cloudflare)
        if not tunnel_ok and cf["tunnel"] >= cfg["consecutive_threshold_service"]:
            last_tunnel_act = last_act.get("tunnel_restart", 0)
            if now - last_tunnel_act > cfg["service_cooldown_seconds"]:
                log(f"[TRIGGER] Cloudflare Tunnel degraded (Ready={tunnel_ready}, Conns={active_conns}). Restarting cloudflared LaunchDaemon...", log_file)
                cmd = [LAUNCHCTL_BIN, "kickstart", "-k", "system/com.cloudflare.cloudflared"]
                execute_action("tunnel_restart", cmd, mode, log_file)
                last_act["tunnel_restart"] = now
                actions_taken.append("tunnel_restart")

        # VM Listeners Restart
        if not vm_listeners_ok and cf["vm_listeners"] >= cfg["consecutive_threshold_service"]:
            last_vm_act = last_act.get("vm_restart", 0)
            if now - last_vm_act > cfg["service_cooldown_seconds"]:
                log(f"[TRIGGER] VM listeners down for {cf['vm_listeners']} cycles. Restarting OrbStack...", log_file)
                cmd = ["/usr/local/bin/orbctl", "restart"]
                execute_action("vm_restart", cmd, mode, log_file)
                last_act["vm_restart"] = now
                actions_taken.append("vm_restart")

        # Tailscale Restart (session-aware)
        if not tailscale_ok and cf["tailscale"] >= cfg["consecutive_threshold_service"]:
            last_ts_act = last_act.get("tailscale_restart", 0)
            if now - last_ts_act > cfg["service_cooldown_seconds"]:
                log(f"[TRIGGER] Tailscale unresponsive for {cf['tailscale']} cycles. Restarting Tailscale in user session...", log_file)
                cmd = ["/bin/sh", "-c", "/usr/bin/killall Tailscale 2>/dev/null; sleep 2; launchctl asuser $(id -u alejandro) /usr/bin/open -a /Applications/Tailscale.app"]
                execute_action("tailscale_restart", cmd, mode, log_file)
                last_act["tailscale_restart"] = now
                actions_taken.append("tailscale_restart")

    # Layer 3: Critical Multi-Witness Outage -> Graceful Host Reboot
    # Strict Invariants:
    # 1. System must have been up >= min_uptime_before_reboot (20 mins) to prevent boot loops.
    # 2. Reboots capped at max_reboots_24h (2 per 24h).
    # 3. 30m cooldown between reboots.
    multi_outage = (
        cf["dns"] >= cfg["consecutive_threshold_reboot"] and
        cf["tailscale"] >= cfg["consecutive_threshold_reboot"] and
        cf["tunnel"] >= cfg["consecutive_threshold_reboot"]
    ) or (not has_ip and cf["interface_ip"] >= cfg["consecutive_threshold_reboot"] + 1)

    if multi_outage and (mode == "FULL"):
        cutoff_24h = now - 86400
        recent_reboots = [t for t in state.get("reboot_history", []) if t > cutoff_24h]
        state["reboot_history"] = recent_reboots

        last_reboot_time = recent_reboots[-1] if recent_reboots else 0
        cooldown_elapsed = (now - last_reboot_time) > cfg["reboot_cooldown_seconds"]
        uptime_ok = uptime >= cfg.get("min_uptime_before_reboot", 1200)

        if len(recent_reboots) < cfg["max_reboots_24h"] and cooldown_elapsed and uptime_ok:
            log(f"[CRITICAL] Host unrecoverable after {cfg['consecutive_threshold_reboot']} cycles (15m). Initiating graceful reboot...", log_file)
            state["reboot_history"].append(now)
            save_state(state, state_file)
            execute_action("host_reboot", [SHUTDOWN_BIN, "-r", "+1", "Headless Watchdog Emergency Network Recovery"], mode, log_file)
            actions_taken.append("host_reboot")
        else:
            log(f"[SAFEGUARD] Reboot suppressed: count={len(recent_reboots)}/{cfg['max_reboots_24h']} in 24h, cooldown_ok={cooldown_elapsed}, uptime_ok={uptime_ok} ({int(uptime)}s)", log_file)

    save_state(state, state_file)
    overall_ok = (has_ip and lan_ok and internet_ok and tunnel_ok and local_origin_ok and tailscale_ok and vm_listeners_ok)
    return {
        "status": "ok" if overall_ok else "degraded",
        "actions": actions_taken,
        "probes": {
            "interface_ip": has_ip,
            "lan": lan_ok,
            "dns": internet_ok,
            "tunnel": tunnel_ok,
            "tunnel_ready_connections": active_conns,
            "local_origin": local_origin_ok,
            "tailscale": tailscale_ok,
            "vm": vm_listeners_ok
        }
    }


if __name__ == "__main__":
    cfg = {}
    if len(sys.argv) > 1:
        arg_mode = sys.argv[1].upper()
        if arg_mode in ["DRY_RUN", "SOFT", "FULL"]:
            cfg["mode"] = arg_mode
        elif arg_mode == "STATUS":
            st = load_state(DEFAULT_CONFIG["state_file"])
            print(json.dumps(st, indent=2))
            sys.exit(0)

    result = run_health_cycle(cfg)
    print(json.dumps(result, indent=2))
