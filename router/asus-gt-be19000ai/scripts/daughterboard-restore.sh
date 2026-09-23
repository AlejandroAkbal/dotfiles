#!/bin/sh
set -e

# Self-healing restoration script for ASUS GT-BE19000AI AI Daughterboard (SL1680)
# Deployed to persistent partition: /home/persist/restore.sh

echo "[1/10] Restoring /etc/os-release for Coolify compatibility..."
cp -f /home/persist/etc/os-release /etc/os-release

echo "[2/10] Restoring systemd-resolved override (DNSStubListener=no)..."
mkdir -p /etc/systemd/resolved.conf.d
cp -f /home/persist/etc/systemd/resolved.conf.d/adguardhome.conf /etc/systemd/resolved.conf.d/

echo "[3/10] Restoring static binaries..."
cp -f /home/persist/bin/docker /usr/bin/docker
cp -f /home/persist/bin/dockerd /usr/bin/dockerd
cp -f /home/persist/bin/tailscale /usr/sbin/tailscale
cp -f /home/persist/bin/tailscaled /usr/sbin/tailscaled
if [ -f /home/persist/bin/jq-linux-arm64 ]; then
    cp -f /home/persist/bin/jq-linux-arm64 /usr/bin/jq-linux-arm64
fi
ln -sf /usr/bin/jq-linux-arm64 /usr/bin/jq
mkdir -p /usr/local/bin
if [ -f /home/persist/bin/git ]; then
    cp -f /home/persist/bin/git /usr/local/bin/git
    chmod +x /usr/local/bin/git
fi

echo "[4/10] Restoring Tailscale state & service..."
mkdir -p /var/lib/tailscale
cp -f /home/persist/tailscale/tailscaled.state /var/lib/tailscale/tailscaled.state
chmod 600 /var/lib/tailscale/tailscaled.state
cp -f /home/persist/etc/systemd/system/tailscaled.service /lib/systemd/system/tailscaled.service

echo "[5/10] Restoring /data symlink/directory..."
if [ ! -d /data/coolify ] && [ -d /home/persist/data/coolify ]; then
    mkdir -p /data
    cp -a /home/persist/data/coolify /data/
fi

echo "[6/10] Restoring SSH host keys, Dropbear config, and authorized_keys..."
mkdir -p /etc/dropbear /etc/default
cp -f /home/persist/etc/dropbear /etc/default/dropbear 2>/dev/null || true
if [ -d /home/persist/etc/dropbear_keys ]; then
    cp -p /home/persist/etc/dropbear_keys/* /etc/dropbear/ 2>/dev/null || true
    chmod 700 /etc/dropbear
    chmod 600 /etc/dropbear/*
fi
mkdir -p /root/.ssh /home/root/.ssh
chmod 700 /root/.ssh /home/root/.ssh
if [ -f /home/root/.ssh/authorized_keys ]; then
    cp -f /home/root/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

echo "[7/10] Reloading systemd daemons..."
systemctl daemon-reload

echo "[8/10] Enabling and restarting systemd-resolved..."
systemctl enable systemd-resolved
systemctl restart systemd-resolved

echo "[9/10] Enabling and restarting tailscaled..."
systemctl enable tailscaled
systemctl restart tailscaled

echo "[10/10] Enabling and restarting docker..."
systemctl enable docker
systemctl restart docker

echo "[*] Waiting for container services to initialize..."
for i in $(seq 1 15); do
    if docker ps | grep -q 'adguardhome.*healthy'; then
        break
    fi
    sleep 1
done

echo "=== Restoration Complete ==="
/usr/sbin/tailscale ip -4 || true
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
