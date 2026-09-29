#!/usr/bin/env bash
set -euo pipefail

# ASUS GT-BE19000AI 1-Command Disaster Recovery & Verification Script
# Targets: Host Router (192.168.50.1), AI Daughterboard (192.168.50.88), Shelly Watchdog (192.168.50.60)

SSH_KEY="${COOLIFY_SSH_KEY:-${HOME}/.ssh/id_ed25519_coolify}"
SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i ${SSH_KEY}"
ROUTER_IP="${ROUTER_IP:-192.168.50.1}"
BOARD_IP="${BOARD_IP:-192.168.50.88}"
HETZNER_MASTER="${HETZNER_MASTER:-91.107.213.51}"
SHELLY_IP="${SHELLY_IP:-192.168.50.60}"
SINGBOX_AUTH="${SINGBOX_AUTH:-router_user:SecurePassword123}"
SINGBOX_IP="${SINGBOX_IP:-100.95.204.62}"

echo "=== [1/5] Checking Host Router (${ROUTER_IP}) ==="
if ping -c 1 -W 2 "${ROUTER_IP}" >/dev/null 2>&1; then
    echo "  [+] Router is reachable via ICMP."
    ssh ${SSH_OPTS} "admin@${ROUTER_IP}" "
        echo '  [*] Verifying NVRAM DNS & DHCP settings (NextDNS via stubby DoT)...'
        NVRAM_CHANGED=0
        # Retired: AdGuard replica (${BOARD_IP}) / Hetzner master (${HETZNER_MASTER}) as resolvers. The
        # router's own dnsmasq -> stubby DoT (127.0.1.1) is the resolver now, and LAN clients must use
        # the router itself, so dhcp_dns1_x/dhcp_dns2_x have to stay EMPTY. Never re-assert the old pair:
        # doing so hands clients dead resolvers and blackholes DNS.
        for pair in 'wan_dns1_x 127.0.1.1' 'wan_dns 127.0.1.1' 'wan_dnsenable_x 0' 'misc_http_x 0' 'sshd_pass 0'; do
            set -- \$pair
            CURR=\$(nvram get \$1 2>/dev/null || true)
            if [ \"\$CURR\" != \"\$2\" ]; then
                echo \"  [!] Correcting \$1: '\$CURR' -> '\$2'\"
                nvram set \$1=\"\$2\"
                NVRAM_CHANGED=1
            fi
        done
        for v in dhcp_dns1_x dhcp_dns2_x wan_dns2_x; do
            CURR=\$(nvram get \$v 2>/dev/null || true)
            if [ -n \"\$CURR\" ]; then
                echo \"  [!] Clearing \$v: '\$CURR' -> ''\"
                nvram set \$v=\"\"
                NVRAM_CHANGED=1
            fi
        done
        echo '  [*] Verifying Wi-Fi stability settings (Auto channel, boot-only ACS)...'
        WIFI_CHANGED=0
        # Staged rollback after the 2026-09-29 wedge: leave channels on Auto (0) so acsd picks once per
        # boot, while wl*_acs_boot_only=1 keeps the runtime decision path off. Do NOT re-pin individual
        # channels here; if the wedge returns, re-pin wl0 to 6 and wl1 to 149/80 (both non-DFS).
        for pair in 'wl0_chanspec 0' 'wl1_chanspec 0' 'wl2_chanspec 0' 'wl0_acs_boot_only 1' 'wl1_acs_boot_only 1' 'wl2_acs_boot_only 1'; do
            set -- \$pair
            CURR=\$(nvram get \$1 2>/dev/null || true)
            if [ \"\$CURR\" != \"\$2\" ]; then
                echo \"  [!] Correcting \$1: '\$CURR' -> '\$2'\"
                nvram set \$1=\"\$2\"
                WIFI_CHANGED=1
            fi
        done
        if [ \$WIFI_CHANGED -eq 1 ]; then
            echo '  [*] Committing NVRAM and restarting wireless (Wi-Fi drops ~30s)...'
            nvram commit
            service restart_wireless >/dev/null 2>&1 || true
        fi
        if [ \$NVRAM_CHANGED -eq 1 ]; then
            echo '  [*] Committing NVRAM and restarting services...'
            nvram commit
            service restart_dnsmasq >/dev/null 2>&1 || true
            service restart_firewall >/dev/null 2>&1 || true
        else
            echo '  [+] Router NVRAM configuration is consistent.'
        fi
    "
else
    echo "  [-] ERROR: Router ${ROUTER_IP} is unreachable!"
fi

echo "=== [2/5] Checking AI Daughterboard (${BOARD_IP}) ==="
if ping -c 1 -W 2 "${BOARD_IP}" >/dev/null 2>&1; then
    echo "  [+] Daughterboard is reachable via ICMP."
    ssh ${SSH_OPTS} "root@${BOARD_IP}" "
        if [ -x /home/persist/restore.sh ]; then
            echo '  [*] Running /home/persist/restore.sh...'
            /home/persist/restore.sh
        else
            echo '  [-] ERROR: /home/persist/restore.sh not found!'
            exit 1
        fi
    "
else
    echo "  [-] ERROR: Daughterboard ${BOARD_IP} is unreachable!"
fi

echo "=== [3/5] Testing DNS Resolution (router dnsmasq -> stubby DoT -> NextDNS) ==="
echo -n "  [*] Router dnsmasq (${ROUTER_IP}): "
dig @${ROUTER_IP} +short +time=3 +tries=2 cloudflare.com | head -n 1 || echo "FAILED"
echo -n "  [*] Router stubby DoT listener (127.0.1.1): "
ssh ${SSH_OPTS} "admin@${ROUTER_IP}" "nslookup cloudflare.com 127.0.1.1 2>/dev/null | sed -n 's/^Address [0-9]*: //p' | tail -n 1"
echo -n "  [*] Stubby DoT upstream profile: "
ssh ${SSH_OPTS} "admin@${ROUTER_IP}" "grep -o '[a-z0-9]*\.dns\.nextdns\.io' /etc/stubby/stubby-0.yml | head -n 1"

echo "=== [4/5] Testing SingBox Proxy Egress via Tailscale ==="
if ssh hetzner-de-1 "curl -s -x http://${SINGBOX_AUTH}@${SINGBOX_IP}:1080 --connect-timeout 5 https://ifconfig.me" > /tmp/singbox_out 2>/dev/null; then
    echo "  [+] Egress successful via IP: $(cat /tmp/singbox_out)"
else
    echo "  [-] ERROR: SingBox egress test failed."
fi
rm -f /tmp/singbox_out

echo "=== [5/5] Checking Shelly Watchdog (${SHELLY_IP}) ==="
if [ -f "${HOME}/.hermes/scripts/shelly-rpc.py" ]; then
    python3 "${HOME}/.hermes/scripts/shelly-rpc.py" Switch.GetStatus '{"id": 0}' 2>/dev/null | jq -r '"  [+] Shelly Relay: output=" + (.output|tostring) + ", power=" + (.apower|tostring) + "W"' || echo "  [*] Shelly probe returned no data."
else
    echo "  [*] Shelly script not available locally."
fi

echo "=== Disaster Recovery Verification Completed ==="
