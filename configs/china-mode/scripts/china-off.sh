#!/usr/bin/env bash
# china-off.sh — Disable China Mode on VLAN 20
# Run from SillyProxmox or any host with SSH access to 172.16.67.3
#
# What this does:
#   1. Stops CT 200 (china-mode) on Proxmox
#   2. Prints router config changes to apply manually
#
# Usage: bash china-off.sh [proxmox_host]

set -euo pipefail

PROXMOX_HOST="${1:-172.16.67.3}"
CT_ID=200

echo "=== China Mode: DISABLING ==="

# ---- Step 1: Stop CT 200 ----
echo "[1/2] Stopping CT $CT_ID on Proxmox ($PROXMOX_HOST)..."
ssh "root@${PROXMOX_HOST}" "pct status ${CT_ID}" | grep -q "stopped" && {
    echo "      CT $CT_ID already stopped."
} || {
    ssh "root@${PROXMOX_HOST}" "pct stop ${CT_ID}"
    echo "      CT $CT_ID stopped."
}

# ---- Step 2: Router config instructions ----
echo ""
echo "[2/2] Apply the following config to SillyRouter:"
echo "------------------------------------------------------------"
cat << 'ROUTER_CONFIG'
conf t
!
! --- China Mode OFF: Restore VLAN 20 DNS ---
ip dhcp pool CLASSROOM
 no dns-server
 dns-server 1.1.1.1 8.8.8.8
!
interface Vlan20
 no ip access-group CHINA-MODE-DNS-LOCK in
!
end
clear ip dhcp binding *
wr mem
ROUTER_CONFIG
echo "------------------------------------------------------------"
echo ""
echo "=== China Mode: DISABLED ==="
echo "    VLAN 20 DNS restored to 1.1.1.1 / 8.8.8.8"
echo "    CT $CT_ID is stopped (onboot=0, will not restart)"
echo ""
echo "Note: The CHINA-MODE-DNS-LOCK ACL remains defined but is"
echo "      no longer applied to Vlan20. Safe to leave in place."
