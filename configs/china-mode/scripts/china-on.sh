#!/usr/bin/env bash
# china-on.sh — Enable China Mode on VLAN 20
# Run from SillyProxmox or any host with SSH access to 172.16.67.3
#
# What this does:
#   1. Starts CT 200 (china-mode) on Proxmox
#   2. Waits for Pi-hole DNS to come up
#   3. Prints router config changes to apply manually (or via expect/netmiko)
#
# Usage: bash china-on.sh [proxmox_host]

set -euo pipefail

PROXMOX_HOST="${1:-172.16.67.3}"
CT_ID=200
PIHOLE_IP="172.16.20.50"
PIHOLE_DNS_PORT=53

echo "=== China Mode: ENABLING ==="

# ---- Step 1: Start CT 200 ----
echo "[1/3] Starting CT $CT_ID on Proxmox ($PROXMOX_HOST)..."
ssh "root@${PROXMOX_HOST}" "pct status ${CT_ID}" | grep -q "running" && {
    echo "      CT $CT_ID already running, skipping start."
} || {
    ssh "root@${PROXMOX_HOST}" "pct start ${CT_ID}"
    echo "      CT $CT_ID started."
}

# ---- Step 2: Wait for Pi-hole DNS ----
echo "[2/3] Waiting for Pi-hole DNS at ${PIHOLE_IP}:${PIHOLE_DNS_PORT}..."
TIMEOUT=60
ELAPSED=0
until ssh "root@${PROXMOX_HOST}" "pct exec ${CT_ID} -- bash -c 'systemctl is-active pihole-FTL'" 2>/dev/null | grep -q "active"; do
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "ERROR: Pi-hole did not come up within ${TIMEOUT}s. Check CT $CT_ID logs."
        exit 1
    fi
    echo "      Waiting... (${ELAPSED}s)"
done
echo "      Pi-hole is up."

# ---- Step 3: Router config instructions ----
echo ""
echo "[3/3] Apply the following config to SillyRouter:"
echo "------------------------------------------------------------"
cat << 'ROUTER_CONFIG'
conf t
!
! --- China Mode ON: VLAN 20 DNS lockdown ---
ip dhcp pool CLASSROOM
 no dns-server
 dns-server 172.16.20.50
!
ip access-list extended CHINA-MODE-DNS-LOCK
 10 permit udp any host 172.16.20.50 eq 53
 20 permit tcp any host 172.16.20.50 eq 53
 30 deny   udp any any eq 53 log
 40 deny   tcp any any eq 53 log
 50 permit ip any any
!
interface Vlan20
 ip access-group CHINA-MODE-DNS-LOCK in
!
end
clear ip dhcp binding *
wr mem
ROUTER_CONFIG
echo "------------------------------------------------------------"
echo ""
echo "=== China Mode: ENABLED ==="
echo "    Pi-hole admin:  http://${PIHOLE_IP}/admin"
echo "    Status page:    http://${PIHOLE_IP}:8888"
echo "    Upstream DNS:   223.5.5.5 (Alibaba)"
echo ""
echo "Test with: nslookup google.com 172.16.20.50  (should be blocked)"
echo "           nslookup baidu.com 172.16.20.50   (should resolve)"
