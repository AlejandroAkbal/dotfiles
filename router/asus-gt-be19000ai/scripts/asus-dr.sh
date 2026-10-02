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
SINGBOX_IP="${SINGBOX_IP:-100.95.204.62}"

# TCP reachability probe. On macOS `ping -W` is MILLISECONDS, not seconds, so the old
# `ping -c 1 -W 2` gates were really "give up after 2ms" and reported every LAN peer as
# dead. /dev/tcp is a bash builtin and needs no extra dependency, so use it as the gate
# for the services this script actually talks to over TCP (SSH/RPC), not ICMP.
tcp_probe() {
    local host="$1" port="$2"
    (exec 3<>"/dev/tcp/${host}/${port}") >/dev/null 2>&1
}

SINGBOX_AUTH=""
if [ -n "${SINGBOX_AUTH_OVERRIDE:-}" ]; then
    SINGBOX_AUTH="${SINGBOX_AUTH_OVERRIDE}"
elif [ -n "${SINGBOX_AUTH_FILE:-}" ] && [ -r "${SINGBOX_AUTH_FILE}" ]; then
    SINGBOX_AUTH="$(head -n 1 "${SINGBOX_AUTH_FILE}")"
elif [ -f "${HOME}/.hermes/.env" ] && grep -q '^SINGBOX_AUTH=' "${HOME}/.hermes/.env" 2>/dev/null; then
    SINGBOX_AUTH="$(sed -n 's/^SINGBOX_AUTH=//p' "${HOME}/.hermes/.env" | head -n 1)"
fi
if [ -z "${SINGBOX_AUTH}" ]; then
    echo "  [!] WARNING: sing-box credentials not found (set SINGBOX_AUTH_OVERRIDE, SINGBOX_AUTH_FILE," >&2
    echo "      or SINGBOX_AUTH= in ${HOME}/.hermes/.env). Step [4/5] will be skipped." >&2
fi

echo "=== [1/5] Checking Host Router (${ROUTER_IP}) ==="
if tcp_probe "${ROUTER_IP}" 22 || ping -c 1 -W 2000 "${ROUTER_IP}" >/dev/null 2>&1; then
    echo "  [+] Router is reachable."
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
        echo '  [*] Verifying Wi-Fi stability settings (pinned non-DFS channels, boot-only ACS)...'
        WIFI_CHANGED=0
        # Wedge containment after the 2026-10-02 recurrence (mass broadcast deauth on wl0+wl2, no ACS
        # signature; wl1 had auto-selected DFS ch 60/160 at boot). Channels are PINNED to non-DFS:
        # wl0=6 (2.4G) and wl1=149/80 (5G). wl2 (6G) stays Auto but ACS is boot-only, and wl*_acs_dfs=0
        # keeps auto mode off DFS entirely. Revert by setting chanspecs to 0, acs_dfs to 1 and
        # acs_boot_only to 0, then commit + service restart_wireless.
        for pair in 'wl0_chanspec 6' 'wl1_chanspec 149/80' 'wl2_chanspec 0' 'wl0_acs_boot_only 1' 'wl1_acs_boot_only 1' 'wl2_acs_boot_only 1' 'wl0_acs_dfs 0' 'wl1_acs_dfs 0'; do
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
# The board does not always answer ICMP even when SSH works fine, and this step needs
# SSH anyway. Gate on TCP/22 so restore.sh actually runs instead of being skipped.
if tcp_probe "${BOARD_IP}" 22; then
    echo "  [+] Daughterboard is reachable (TCP/22)."
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
if [ -z "${SINGBOX_AUTH}" ]; then
    echo "  [*] SKIPPED: no sing-box credentials available."
elif ssh hetzner-de-1 "curl -s -x http://${SINGBOX_AUTH}@${SINGBOX_IP}:1080 --connect-timeout 5 https://ifconfig.me" > /tmp/singbox_out 2>/dev/null && [ -s /tmp/singbox_out ]; then
    echo "  [+] Egress successful via IP: $(cat /tmp/singbox_out)"
else
    echo "  [-] ERROR: SingBox egress test failed."
fi
rm -f /tmp/singbox_out

echo "=== [5/5] Checking Shelly Watchdog (${SHELLY_IP}) ==="
# NOTE: this step must not use python3. macOS treats each binary as a separate app for
# Local Network privacy, and the system python here is denied, so urllib fails with
# "No route to host" on every LAN peer while curl/ssh work fine on the same host at the
# same moment. curl --digest is therefore the transport: it does the same SHA-256 digest
# auth and is proven to reach 192.168.50.60. A GET with ?id= is required; a POST without a
# body is rejected with HTTP 400 "Content-Length required".
if ! tcp_probe "${SHELLY_IP}" 80; then
    echo "  [-] ERROR: Shelly ${SHELLY_IP} not answering on TCP/80."
elif ! SHELLY_PW="$(USER="${USER:-$(id -un)}" "${HOME}/.hermes/scripts/shelly-rpc.py" --password-only 2>/dev/null)"; then
    echo "  [-] ERROR: could not read the Shelly password from Bitwarden."
    echo "      bw-session.sh needs \$USER and the macOS Keychain; a non-interactive run may lack them."
elif [ -z "${SHELLY_PW}" ]; then
    echo "  [-] ERROR: Bitwarden returned an empty Shelly password."
else
    SHELLY_OUT="$(printf 'user = "admin:%s"\n' "${SHELLY_PW}" | \
        curl -s -m 8 --digest -K - -o /dev/stdout \
             "http://${SHELLY_IP}/rpc/Switch.GetStatus?id=0" 2>/dev/null)"
    if [ -z "${SHELLY_OUT}" ] || echo "${SHELLY_OUT}" | grep -q 'Unauthorized\|401'; then
        echo "  [-] ERROR: Shelly RPC auth failed (HTTP 401) or empty response."
    else
        echo "${SHELLY_OUT}" | jq -r '"  [+] Shelly Relay: output=" + (.output|tostring) + ", power=" + (.apower|tostring) + "W, source=" + (.source|tostring)' 2>/dev/null \
            || echo "  [*] Shelly responded but the payload was not parseable JSON."
    fi
fi
unset SHELLY_PW SHELLY_OUT

echo "=== Disaster Recovery Verification Completed ==="
