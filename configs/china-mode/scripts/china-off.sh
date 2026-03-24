#!/usr/bin/env bash
# china-off.sh — Disable China Mode on VLAN 20
#
# Run from any machine with SSH access to Proxmox (172.16.67.3).
# router_toggle.py runs ON Proxmox (in MGMT VLAN) — no local dependencies needed.
#
# Credentials: set env vars to skip prompts
#   export ROUTER_USER=admin
#   export ROUTER_PASS=yourpassword
#   export ROUTER_ENABLE=yourenablesecret

set -euo pipefail

PROXMOX_HOST="${1:-172.16.67.3}"
CT_ID=200

echo "=== China Mode: DISABLING ==="

# ---- Collect router credentials (once) ----
if [ -z "${ROUTER_USER:-}" ]; then
    read -rp "  Router username: " ROUTER_USER
fi
if [ -z "${ROUTER_PASS:-}" ]; then
    read -rsp "  Router password: " ROUTER_PASS; echo
fi
if [ -z "${ROUTER_ENABLE:-}" ]; then
    read -rsp "  Router enable secret: " ROUTER_ENABLE; echo
fi

# ---- Step 1: Restore router config FIRST (clients get real DNS immediately) ----
echo "[1/2] Restoring router config via Proxmox..."
ssh "root@${PROXMOX_HOST}" \
    "ROUTER_USER='${ROUTER_USER}' ROUTER_PASS='${ROUTER_PASS}' ROUTER_ENABLE='${ROUTER_ENABLE}' \
     python3 /opt/china-mode/scripts/router_toggle.py off"

# ---- Step 2: Stop CT 200 ----
echo "[2/2] Stopping CT $CT_ID on Proxmox ($PROXMOX_HOST)..."
STATUS=$(ssh "root@${PROXMOX_HOST}" "pct status ${CT_ID}" | awk '{print $2}')
if [ "$STATUS" = "stopped" ]; then
    echo "      CT $CT_ID already stopped."
else
    ssh "root@${PROXMOX_HOST}" "pct stop ${CT_ID}"
    echo "      CT $CT_ID stopped."
fi

echo ""
echo "=== China Mode: DISABLED ==="
echo "  VLAN 20 DNS restored: 172.16.20.20 (DC), 8.8.8.8, 1.1.1.1"
echo "  CT $CT_ID stopped."
