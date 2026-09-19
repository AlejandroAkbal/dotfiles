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
  7. Local VM listener signals (diagnostic only; host forwarding sockets are not proof of VM health)

OrbStack and `coolify-node` application recovery are authoritatively handled by the separate user LaunchAgent documented below. The root watchdog still contains its legacy listener-based fallback, but those host sockets are diagnostic signals and are not relied upon to prove VM health.

## Multi-Layer Recovery
1. **Layer 1 (Interface Bounce - 5 min failure)**:
   If `en0` has no valid IP or cannot reach the local gateway / WAN, executes:
   ```bash
   /sbin/ifconfig en0 down && sleep 2 && /sbin/ifconfig en0 up
   ```
   This triggers a fresh DHCP request and clears stale ARP routing state without rebooting.

2. **Layer 2 (Service Restart - 10 min failure)**:
   Restarts `com.cloudflare.cloudflared` or Tailscale if their individual probes fail while the host network is fine. The unprivileged user LaunchAgent below is the authoritative OrbStack recovery path.

3. **Layer 3 (Host Reboot - 15 min sustained multi-witness outage)**:
   Initiates a graceful reboot (`shutdown -r +1`) if all probes fail for 3 consecutive cycles (15m).

## Anti-Bootloop Safeguards
- **Minimum Uptime**: Reboots are blocked if system uptime is under 20 minutes (`min_uptime_before_reboot: 1200s`).
- **Rate Limit**: Strictly capped at **maximum 2 reboots per rolling 24 hours**.
- **Cooldown**: Minimum **30 minutes** post-reboot lockout before another reboot can be scheduled.

## Files
- Root network watchdog: `/usr/local/bin/headless-watchdog.py` (source: `macos/scripts/headless-watchdog.py`)
- Root watchdog daemon: `/Library/LaunchDaemons/com.alejandro.headless-watchdog.plist`
- Root watchdog state: `/var/db/headless-watchdog/state.json`
- Root watchdog logs: `/var/log/headless-watchdog.log`

## OrbStack and Coolify VM Recovery

OrbStack supports **Start at login**, not unattended startup without a user desktop session. The Mac mini uses automatic login, but the login item alone did not recover `coolify-node` during the 2026-09-19 incident. A dedicated unprivileged LaunchAgent therefore owns application-layer recovery in the `gui/501` Aqua session.

### Incident: 2026-09-19

- macOS rebooted normally at `05:00:31 ICT`.
- UptimeRobot monitor `803068309` recorded `502 Bad Gateway` from `07:06:52` until `09:28:47 ICT`.
- Total OmniRoute outage: `2h 21m 55s`.
- OrbStack relaunched at `09:24:46`; `coolify-node`, Docker, and OmniRoute recovered afterward.
- The old TCP probes were insufficient: macOS SSH and OrbStack forwarding sockets could remain open while the VM backend was unavailable.

### Recovery Contract

`com.alejandro.orbstack-recovery` runs every five minutes and at user-session load. It takes action only when the host gateway and public DNS are reachable.

1. Check `orbctl status`.
2. Check the `coolify-node` state from `orbctl list`.
3. Probe OmniRoute through the local SNI route at `https://9router.akbal.dev/api/health` and require JSON `status=ok`.
4. Launch OrbStack when its daemon is unavailable.
5. Start `coolify-node` when stopped.
6. Restart `coolify-node` only after two consecutive failed L7 probes while the VM reports `running`.
7. Enforce a ten-minute action cooldown and never reboot the Mac.

### Installation

```bash
install -d "$HOME/.local/bin" "$HOME/.local/var/log" \
  "$HOME/.local/var/run" "$HOME/.local/var/lib/orbstack-recovery" \
  "$HOME/Library/LaunchAgents"
install -m 0755 macos/scripts/orbstack-recovery.py \
  "$HOME/.local/bin/orbstack-recovery.py"
install -m 0644 macos/launchagents/com.alejandro.orbstack-recovery.plist \
  "$HOME/Library/LaunchAgents/com.alejandro.orbstack-recovery.plist"
launchctl bootout "gui/$(id -u)/com.alejandro.orbstack-recovery" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.alejandro.orbstack-recovery.plist"
```

### Verification

```bash
launchctl print "gui/$(id -u)/com.alejandro.orbstack-recovery"
python3 "$HOME/.local/bin/orbstack-recovery.py"
tail -n 20 "$HOME/.local/var/log/orbstack-recovery.log"
curl -sk --resolve 9router.akbal.dev:443:127.0.0.1 \
  https://9router.akbal.dev/api/health
```

The expected healthy result is `{"result": "healthy"}` with no launch, start, or restart action in the recovery log. Do not stop the live VM merely to test recovery without an approved maintenance window.

---

# Jump Desktop User Agent Recovery

## Incident & Root Cause (2026-09-19)
Following weekly 05:00 scheduled headless reboots, incoming Jump Desktop connections repeatedly failed with the root daemon (`/Library/LaunchDaemons/com.p5sys.jump.connect.service.plist`) looping indefinitely:

```
[rtc.dp.launch] Trying to launch agent for: 501, backgroundLoginsDisabled:false, anySession:false
[rtc.dp.launch] User is already logged in, waiting for agent for: alejandro
```

### Root Cause
- Vendor plist `/Library/LaunchAgents/com.p5sys.jump.connect.agent.plist` has `<key>RunAtLoad</key><false/>` and relies on a `com.apple.notifyd.matching` notification `com.p5sys.jump.connect.agent.launchd`.
- On headless autologin, macOS `launchd` initializes `gui/501`, but does not automatically bootstrap `/Library/LaunchAgents/com.p5sys.jump.connect.agent.plist` into `gui/501`, or the notification is fired across domain boundaries before `gui/501` has subscribed.
- The root daemon cannot launch the agent, causing remote access failure until manual `launchctl bootstrap` is executed.
- Adding Jump Desktop to Login Items is prohibited because launching `Jump Desktop Connect.app` in GUI opens the interactive configuration window rather than running the background minimized daemon (`--minimized`).
- Editing `/Library/LaunchAgents/com.p5sys.jump.connect.agent.plist` directly is prohibited because vendor app updates overwrite it.

## Architecture
Implemented a dedicated unprivileged user LaunchAgent in Alejandro's Aqua domain:
- Plist: `~/Library/LaunchAgents/com.alejandro.jump-desktop-bootstrap.plist`
- Script: `~/.local/bin/jump-desktop-recovery.py`
- Test suite: `macos/scripts/tests/test_jump_desktop_recovery.py`

### State Machine & Actions
1. **Registered in domain** (`launchctl print gui/501/com.p5sys.jump.connect.agent` exit `0`):
   - Returns `"healthy"`. Instant no-op, zero session disruption, zero interference with active or idle states.
2. **Missing from domain** (exit != 0):
   - Executes `launchctl bootstrap gui/501 /Library/LaunchAgents/com.p5sys.jump.connect.agent.plist`.
   - Executes non-destructive `launchctl kickstart gui/501/com.p5sys.jump.connect.agent` (no `-k`) to spawn the agent immediately without waiting for transient notifications.
   - Logs event to `~/.local/var/log/jump-desktop-recovery.log`.
