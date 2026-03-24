#!/usr/bin/env bash
# china-on.sh — Enable China Mode on VLAN 20
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
PIHOLE_IP="172.16.20.21"

echo "=== China Mode: ENABLING ==="

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

# ---- Step 1: Start CT 200 ----
echo "[1/3] Starting CT $CT_ID on Proxmox ($PROXMOX_HOST)..."
STATUS=$(ssh "root@${PROXMOX_HOST}" "pct status ${CT_ID}" | awk '{print $2}')
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
        echo "  ssh root@${PROXMOX_HOST} 'pct exec ${CT_ID} -- journalctl -u pihole-FTL -n 20'"
        exit 1
    fi
    echo "      Waiting... (${ELAPSED}s)"
done
echo "      Pi-hole is up."

# ---- Step 3: Apply router config (runs on Proxmox, which is in MGMT VLAN) ----
echo "[3/3] Applying router config via Proxmox..."
ssh "root@${PROXMOX_HOST}" \
    "ROUTER_USER='${ROUTER_USER}' ROUTER_PASS='${ROUTER_PASS}' ROUTER_ENABLE='${ROUTER_ENABLE}' \
     python3 /opt/china-mode/scripts/router_toggle.py on"

echo ""
echo "=== China Mode: ACTIVE ==="
echo "  Pi-hole admin:  http://${PIHOLE_IP}/admin"
echo "  Status page:    http://${PIHOLE_IP}:8888"
echo "  GFW DNS:        Alibaba 223.5.5.5 (blocked sites → 0.0.0.0)"
echo "  AD/DC DNS:      Forwarded to 172.16.20.20 (stemlab.lan works)"
