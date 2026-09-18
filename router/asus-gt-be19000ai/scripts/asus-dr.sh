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
        echo '  [*] Verifying NVRAM DNS & DHCP settings...'
        NVRAM_CHANGED=0
        for pair in 'dhcp_dns1_x ${BOARD_IP}' 'dhcp_dns2_x ${HETZNER_MASTER}' 'wan_dns1_x ${BOARD_IP}' 'wan_dns2_x ${HETZNER_MASTER}' 'wan_dnsenable_x 0' 'misc_http_x 0' 'sshd_pass 0'; do
            set -- \$pair
            CURR=\$(nvram get \$1 2>/dev/null || true)
            if [ \"\$CURR\" != \"\$2\" ]; then
                echo \"  [!] Correcting \$1: '\$CURR' -> '\$2'\"
                nvram set \$1=\"\$2\"
                NVRAM_CHANGED=1
            fi
        done
        CURR_WAN_DNS=\$(nvram get wan_dns 2>/dev/null || true)
        if [ \"\$CURR_WAN_DNS\" != \"${BOARD_IP} ${HETZNER_MASTER}\" ]; then
            echo \"  [!] Correcting wan_dns: '\$CURR_WAN_DNS' -> '${BOARD_IP} ${HETZNER_MASTER}'\"
            nvram set wan_dns=\"${BOARD_IP} ${HETZNER_MASTER}\"
            NVRAM_CHANGED=1
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

echo "=== [3/5] Testing DNS Resolution & Failover ==="
echo -n "  [*] Daughterboard AdGuard (${BOARD_IP}): "
dig @${BOARD_IP} +short +time=3 +tries=2 cloudflare.com | head -n 1 || echo "FAILED"
echo -n "  [*] Hetzner Master AdGuard (${HETZNER_MASTER}): "
dig @${HETZNER_MASTER} +short +time=3 +tries=2 cloudflare.com | head -n 1 || echo "FAILED"
echo -n "  [*] Router dnsmasq (${ROUTER_IP}): "
dig @${ROUTER_IP} +short +time=3 +tries=2 cloudflare.com | head -n 1 || echo "FAILED"

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
