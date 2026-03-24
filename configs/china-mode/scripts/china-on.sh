#!/usr/bin/env bash
# china-on.sh — Enable China Mode on VLAN 20
#
# Run from SillyProxmox (172.16.67.3) or any host that:
#   a) has SSH access to Proxmox to manage CT 200
#   b) is in the MGMT VLAN (172.16.67.0/28) to SSH to SillyRouter
#
# Credentials: set env vars to skip interactive prompts
#   export ROUTER_USER=admin
#   export ROUTER_PASS=yourpassword
#   export ROUTER_ENABLE=yourenablesecret
#
# Usage: bash china-on.sh [proxmox_host]

set -euo pipefail

PROXMOX_HOST="${1:-172.16.67.3}"
CT_ID=200
PIHOLE_IP="172.16.20.21"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== China Mode: ENABLING ==="

# ---- Step 1: Start CT 200 ----
echo "[1/3] Starting CT $CT_ID on Proxmox ($PROXMOX_HOST)..."
STATUS=$(ssh "root@${PROXMOX_HOST}" "pct status ${CT_ID}" 2>/dev/null | awk '{print $2}')
if [ "$STATUS" = "running" ]; then
    echo "      CT $CT_ID already running."
else
    ssh "root@${PROXMOX_HOST}" "pct start ${CT_ID}"
    echo "      CT $CT_ID started."
fi

# ---- Step 2: Wait for Pi-hole ----
echo "[2/3] Waiting for Pi-hole DNS at ${PIHOLE_IP}:53..."
TIMEOUT=60
ELAPSED=0
until ssh "root@${PROXMOX_HOST}" "pct exec ${CT_ID} -- systemctl is-active pihole-FTL" 2>/dev/null | grep -q "^active$"; do
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "ERROR: Pi-hole didn't come up within ${TIMEOUT}s."
        echo "Check logs: ssh root@${PROXMOX_HOST} 'pct exec ${CT_ID} -- journalctl -u pihole-FTL -n 20'"
        exit 1
    fi
    echo "      Waiting... (${ELAPSED}s)"
done
echo "      Pi-hole is up."

# ---- Step 3: Router config via netmiko ----
echo "[3/3] Applying router config (China Mode ON)..."
python3 "${SCRIPT_DIR}/router_toggle.py" on

echo ""
echo "=== China Mode: ACTIVE ==="
echo "  Pi-hole:    http://${PIHOLE_IP}/admin"
echo "  Status:     http://${PIHOLE_IP}:8888"
echo "  Upstream:   Alibaba 223.5.5.5 (non-AD queries)"
echo "  AD/DC DNS:  Forwarded to 172.16.20.20 (stemlab.lan)"
echo ""
echo "Quick test (from this host):"
echo "  nslookup google.com ${PIHOLE_IP}     # should return 0.0.0.0"
echo "  nslookup baidu.com ${PIHOLE_IP}      # should resolve"
echo "  nslookup stemlab.lan ${PIHOLE_IP}    # should resolve via DC"
