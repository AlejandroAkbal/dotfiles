# Headless Mac mini Self-Healing Watchdog

Autonomous, zero-LLM watchdog daemon running on the headless Mac mini to handle link flaps, router reboots, and network freezes.

## Problem Context
The upstream router reboots daily at 05:00 AM. When the physical Ethernet port powers up, macOS `AppleBCM5701Ethernet` detects link before the router DHCP server (`dnsmasq`) is active. macOS falls back to a self-assigned IP (`169.254.x.x`) and latches stale ARP cache entries without re-probing automatically.

## How the Watchdog Works
- **Cadence**: Runs every 300 seconds (5 minutes) as a system LaunchDaemon (`/Library/LaunchDaemons/com.alejandro.headless-watchdog.plist`).
- **Dynamic Gateway Discovery**: Resolves the active default gateway dynamically via `route -n get default` (compatible with any subnet or router).
- **Probes**:
  1. `en0` assigned IPv4 address
  2. Gateway responsiveness (TCP 80, 8443, 53)
  3. Public WAN DNS reachability (Cloudflare, Google, Quad9)
  4. Cloudflared internal `/ready` metrics API (`readyConnections > 0`)
  5. Local web listener (`https://127.0.0.1:443`)
  6. Tailscale node responsiveness (`100.88.191.18:22`)
  7. Local VM listeners (SSH 22, Web 443)

## Multi-Layer Recovery
1. **Layer 1 (Interface Bounce - 5 min failure)**:
   If `en0` has no valid IP or cannot reach the local gateway / WAN, executes:
   ```bash
   /sbin/ifconfig en0 down && sleep 2 && /sbin/ifconfig en0 up
   ```
   This triggers a fresh DHCP request and clears stale ARP routing state without rebooting.

2. **Layer 2 (Service Restart - 10 min failure)**:
   Restarts `com.cloudflare.cloudflared`, OrbStack (`orbctl restart`), or Tailscale if individual listeners stall while the host network is fine.

3. **Layer 3 (Host Reboot - 15 min sustained multi-witness outage)**:
   Initiates a graceful reboot (`shutdown -r +1`) if all probes fail for 3 consecutive cycles (15m).

## Anti-Bootloop Safeguards
- **Minimum Uptime**: Reboots are blocked if system uptime is under 20 minutes (`min_uptime_before_reboot: 1200s`).
- **Rate Limit**: Strictly capped at **maximum 2 reboots per rolling 24 hours**.
- **Cooldown**: Minimum **30 minutes** post-reboot lockout before another reboot can be scheduled.

## Files
- Script: `/usr/local/bin/headless-watchdog.py` (Source: `macos/scripts/headless-watchdog.py`)
- Daemon: `/Library/LaunchDaemons/com.alejandro.headless-watchdog.plist` (Source: `macos/launchdaemons/com.alejandro.headless-watchdog.plist`)
- State file: `/tmp/headless-watchdog-state.json`
- Logs: `/var/log/headless-watchdog.log`
