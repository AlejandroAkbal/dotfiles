# ASUS GT-BE19000AI Edge Gateway & AI Daughterboard Playbook

## 1. Architectural Overview

The ASUS ROG Rapture GT-BE19000AI operates on a dual-SoC asymmetric architecture:

1. **Host Router SoC (Broadcom BCM4916)**
   - **OS:** Asuswrt 3.0.0.6.102_40717 (Linux 5.4 aarch64).
   - **Role:** WAN routing, Wi-Fi 7 radio orchestration, DHCP/DNSmasq server (`192.168.50.1`).
   - **Internal Interconnect:** Point-to-point VLAN subinterface `eth.ai-10` (`169.254.0.1`) connected to the AI daughterboard.
   - **Local Management:** SSH on port 22 (Dropbear, key-only auth). Web UI on `https://192.168.50.1:8443`.

2. **AI Daughterboard (Synaptics Astra SL1680)**
   - **Hardware:** 4 GB LPDDR4, 32 GB eMMC, dedicated NPU/Edge AI accelerator.
   - **OS:** Poky Kirkstone (Yocto 5.15.140-yocto-standard aarch64), spoofed as Debian 12 bookworm.
   - **LAN IP:** `192.168.50.88` (static reservation for MAC `a0:ad:9f:6b:3e:22`).
   - **Tailscale IP:** `100.95.204.62` (`asus-router`).
   - **Workloads:** Managed via Coolify:
     - AdGuard Home replica (`ydqmyd2ixfcnlc1mpr71tlhi` on `:53` and `:3000`)
     - sing-box outbound residential proxy (`ph43iu1jhii4r7luzy65qdqn` on `100.95.204.62:1080`)
     - Watchtower container updater (`g4trjpvwfkeh9w7vgwo8bogt`)
     - Portainer CE (`:9443`)

3. **Power Watchdog (Shelly Plug M Gen3)**
   - **IP:** `192.168.50.60`
   - **Firmware:** Gen3 EC v2.0
   - **Function:** Autonomous JavaScript watchdog pinging external WAN targets (1.1.1.1, 8.8.8.8) every 60s. If WAN fails continuously for 10 minutes, it cycles power. Contains a 60-minute circuit breaker to prevent bootloops during ISP outages.

---

## 2. Storage Layout & Persistence Strategy

The SL1680 daughterboard uses A/B rootfs partitions:

```
/dev/mmcblk0p12  ->  Slot A (2.8 GB, Rootfs mount /)      [EPHEMERAL on swupdate]
/dev/mmcblk0p13  ->  Slot B (2.8 GB, Standby Rootfs)      [EPHEMERAL on swupdate]
/dev/mmcblk0p18  ->  Data   (23.1 GB, Mounted on /home)   [PERSISTENT across updates]
```

### The `/home/persist` Self-Healing Architecture
Because any firmware upgrade or factory rescue wipes `/`, all custom binaries and system configurations are backed up in `/home/persist/`:

- `/home/persist/bin/` — Static binaries (`docker`, `dockerd` 27.5.1, `tailscale`, `tailscaled` 1.102.4, `jq`, `git`)
- `/home/persist/etc/` — Debian `os-release`, `tailscaled.service`, `adguardhome.conf`, `dropbear`
- `/home/persist/tailscale/` — Persistent `tailscaled.state` (preserves `100.95.204.62` node identity)
- `/home/persist/data/` — Coolify service compose definitions
- `/home/persist/restore.sh` — 10-step automated restoration script

---

## 3. Coolify Server Validation Prerequisites

Coolify requires three distinct prerequisites to manage a Linux host:

1. **OS ID in `/etc/os-release`:** Coolify's `validateOS` rejects `ID=poky`. We spoof:
   ```ini
   ID=debian
   ID_LIKE=debian
   VERSION_ID="12"
   VERSION="12 (bookworm)"
   VERSION_CODENAME=bookworm
   ```
2. **Docker Engine Version $\ge 24.0$:** Stock firmware runs Docker 20.10.25. Replaced with official static Docker Engine v27.5.1 binaries in `/usr/bin/`.
3. **CLI Tools:** Requires `curl`, `jq`, and `git`. `jq` is symlinked from `jq-linux-arm64`. `git` is wrapped via an `alpine/git:latest` container runner script at `/usr/local/bin/git`.

---

## 4. Tailscale & Networking Configuration

### Tailscale IP Re-binding & Persistence
1. Tailscale node `asus-router` is bound to `100.95.204.62`.
2. Docker port proxying requires a loopback alias so containers can bind to the Tailscale IP before the TUN interface connects:
   ```sh
   ifconfig lo:1 100.95.204.62 netmask 255.255.255.255 up
   ```
3. Inbound Tailscale connections require an explicit route for CGNAT subnet `100.64.0.0/10` to prevent asymmetric return routing via default gateway `eth0`:
   ```sh
   route add -net 100.64.0.0 netmask 255.192.0.0 dev tailscale0
   ```
4. Handled automatically on boot by `/lib/systemd/system/tailscaled.service` via a 30s polling loop in `ExecStartPost`.

---

## 5. DNS Redundancy & Synchronization

- **LAN Primary Resolver:** `192.168.50.88` (AdGuard Home replica on AI daughterboard).
- **WAN Secondary Failover:** `91.107.213.51` (AdGuard Home master on Hetzner).
- **Host Router NVRAM:** Configured with `dhcp_dns1_x=192.168.50.88` and `dhcp_dns2_x=91.107.213.51`.
- **Systemd-Resolved Conflict:** Disabled via `/etc/systemd/resolved.conf.d/adguardhome.conf` setting `DNSStubListener=no`.
- **Sync Architecture:** `adguardhome-sync` runs hourly on Hetzner, synchronizing all blocklists, whitelists, user rules, and services from Master to Edge.

---

## 6. Security Hardening

1. **SSH Key-Only Enforcement:**
   - Router SoC: `nvram set sshd_pass=0 && nvram commit` (Dropbear running with `-s`).
   - AI Board: `/etc/default/dropbear` sets `DROPBEAR_EXTRA_ARGS="-s -g"`.
2. **WAN Web UI Access Disabled:**
   - `nvram set misc_http_x=0 && nvram commit && service restart_firewall` removes the port 8443 NAT forwarding rule.

---

## 7. Disaster Recovery & 1-Command Verification

To run a complete end-to-end verification and trigger daughterboard self-healing from the Mac Mini:

```bash
bash router/asus-gt-be19000ai/scripts/asus-dr.sh
```

### Manual SWUpdate Factory Flash (Last Resort)
If the daughterboard eMMC partition table is completely corrupt:
1. Verify Docker image RSA signatures on the router SoC:
   ```sh
   rsasign_check /ai/docker_images/slm.tar /ai/docker_images/slm_rsasign3.bin
   ```
2. Trigger the native SWUpdate recovery script on the router SoC:
   ```sh
   /usr/sbin/webs_ai_rescue.sh > /ai/log/rescue_direct.log 2>&1 &
   ```
3. Once reflashed, access Portainer on `https://192.168.50.88:9443`, spawn a privileged container mounting `/` to `/host`, inject SSH keys into `/host/home/root/.ssh/authorized_keys`, and execute `/home/persist/restore.sh`.
