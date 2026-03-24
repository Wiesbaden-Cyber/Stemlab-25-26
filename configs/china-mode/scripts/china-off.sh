#!/usr/bin/env bash
# china-off.sh — Disable China Mode on VLAN 20
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
# Usage: bash china-off.sh [proxmox_host]

set -euo pipefail

PROXMOX_HOST="${1:-172.16.67.3}"
CT_ID=200
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== China Mode: DISABLING ==="

# ---- Step 1: Router config via netmiko ----
# Do this FIRST so VLAN 20 clients immediately get real DNS back
echo "[1/2] Restoring router config (China Mode OFF)..."
python3 "${SCRIPT_DIR}/router_toggle.py" off

# ---- Step 2: Stop CT 200 ----
echo "[2/2] Stopping CT $CT_ID on Proxmox ($PROXMOX_HOST)..."
STATUS=$(ssh "root@${PROXMOX_HOST}" "pct status ${CT_ID}" 2>/dev/null | awk '{print $2}')
if [ "$STATUS" = "stopped" ]; then
    echo "      CT $CT_ID already stopped."
else
    ssh "root@${PROXMOX_HOST}" "pct stop ${CT_ID}"
    echo "      CT $CT_ID stopped."
fi

echo ""
echo "=== China Mode: DISABLED ==="
echo "  VLAN 20 DNS restored to: 172.16.20.20 (DC), 8.8.8.8, 1.1.1.1"
echo "  CT $CT_ID stopped (onboot=0, will not restart automatically)"
