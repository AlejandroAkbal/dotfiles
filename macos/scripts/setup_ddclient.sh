#!/usr/bin/env bash
set -e

# Configuration variables
DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-}"
DUCKDNS_HOSTNAME="${DUCKDNS_HOSTNAME:-}"

if [[ -z "$DUCKDNS_TOKEN" || -z "$DUCKDNS_HOSTNAME" ]]; then
    echo "Skipping ddclient setup. Set DUCKDNS_TOKEN and DUCKDNS_HOSTNAME to configure."
    exit 0
fi

echo "Setting up ddclient for DuckDNS..."

# Create config directory if it doesn't exist
sudo mkdir -p /opt/homebrew/etc/ddclient

# Write configuration file
sudo tee /opt/homebrew/etc/ddclient/ddclient.conf > /dev/null << CONFIG
######################################################################
# ddclient configuration for DuckDNS
######################################################################

daemon=300                          # check every 5 minutes
syslog=yes                          # log to syslog
pid=/opt/homebrew/var/run/ddclient.pid
ssl=yes                             # use TLS

use=web, web=checkip.dyndns.org

protocol=duckdns
password='${DUCKDNS_TOKEN}'
${DUCKDNS_HOSTNAME}
CONFIG

# Secure the file
sudo chmod 600 /opt/homebrew/etc/ddclient/ddclient.conf

# Start the service
echo "Starting ddclient service..."
sudo brew services restart ddclient

echo "ddclient setup complete!"
