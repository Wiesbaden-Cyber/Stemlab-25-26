# China Mode — GFW Simulation for VLAN 20

**Purpose:** Simulate the Great Firewall of China on VLAN 20 (Classroom) for educational/CTF use.
**Scope:** VLAN 20 only. VLANs 10, 30, and 67 are completely unaffected.
**Implemented:** 2026-03-24

---

## Architecture

```
VLAN 20 Client
     │
     ▼ DNS query → 172.16.20.21 (Pi-hole)
     │
     ├─ stemlab.lan / reverse .20.x → forwarded to DC (172.16.20.20)
     │  (AD/domain joins, internal services continue to work)
     │
     └─ everything else:
          ├─ GFW blocklist → 0.0.0.0 (blocked)
          └─ allowed → Alibaba DNS 223.5.5.5 / 223.6.6.6

     ▼ HTTP traffic (port 80)
CT 200: nginx (172.16.20.21:80)
  └── Injects geo-spoof headers:
      X-Forwarded-For: 61.135.169.125 (Beijing IP)
      Accept-Language: zh-CN,zh;q=0.9
      CF-IPCountry: CN

     ▼ HTTP responses (mitmproxy port 8081)
CT 200: mitmproxy
  └── inject_ads.py: Baidu-style ad banner into HTML pages
```

---

## Container: CT 200

| Property | Value |
|----------|-------|
| VMID | 200 |
| Hostname | china-mode |
| OS | Debian 13 |
| vCPU | 2 |
| RAM | 1 GB |
| Disk | 8 GB (local-zfs) |
| Network | vmbr1, VLAN tag 20, static **172.16.20.21**/24, GW 172.16.20.1 |
| onboot | **0** — never starts automatically; only via china-on.sh |

> **IP note:** 172.16.20.21 is within the router's DHCP excluded range (`172.16.20.1–172.16.20.25`), so it can never be assigned to a DHCP client.

### Services inside CT 200

| Service | Port | Purpose |
|---------|------|---------|
| pihole-FTL | :53 UDP/TCP | DNS filtering; upstream Alibaba 223.5.5.5; AD queries → DC |
| pihole-FTL | :8080 | Pi-hole web admin |
| nginx | :80 | Transparent HTTP proxy with CN header injection |
| nginx | :8888 | China Mode status page |
| mitmproxy | :8081 | HTTP ad injection (Baidu banner) |

---

## Toggling China Mode

Both scripts live on Proxmox at `/opt/china-mode/scripts/` and in this repo at `configs/china-mode/scripts/`.

They **fully automate** the router config change via `router_toggle.py` (Python/netmiko). No manual CLI required.

### Enable China Mode

```bash
bash configs/china-mode/scripts/china-on.sh
```

Prompts for router credentials once (or set env vars to skip prompts):
```bash
export ROUTER_USER=admin
export ROUTER_PASS=yourpassword
export ROUTER_ENABLE=yourenablesecret
bash configs/china-mode/scripts/china-on.sh
```

**What it does:**
1. Starts CT 200 on Proxmox
2. Waits for Pi-hole to be healthy
3. SSHes to SillyRouter via netmiko and applies:
   - CLASSROOM DHCP pool DNS → `172.16.20.21` (Pi-hole only)
   - Adds ACL `CHINA-MODE-DNS-LOCK` to Vlan20 (prevents DNS bypass)
   - Clears DHCP bindings → clients renew with new DNS
   - `wr mem`

### Disable China Mode

```bash
bash configs/china-mode/scripts/china-off.sh
```

**What it does:**
1. SSHes to SillyRouter and restores:
   - CLASSROOM DHCP pool DNS → `172.16.20.20 8.8.8.8 1.1.1.1` (DC + public)
   - Removes ACL from Vlan20
   - Clears DHCP bindings
   - `wr mem`
2. Stops CT 200

---

## Router Config Reference

These are the exact changes `router_toggle.py` applies. For manual override:

### China Mode ON
```
conf t
ip dhcp pool CLASSROOM
 no dns-server
 dns-server 172.16.20.21
!
ip access-list extended CHINA-MODE-DNS-LOCK
 10 permit udp any host 172.16.20.21 eq 53
 20 permit tcp any host 172.16.20.21 eq 53
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
```

### China Mode OFF
```
conf t
ip dhcp pool CLASSROOM
 no dns-server
 dns-server 172.16.20.20 8.8.8.8 1.1.1.1
!
interface Vlan20
 no ip access-group CHINA-MODE-DNS-LOCK in
!
end
clear ip dhcp binding *
wr mem
```

---

## DNS Behavior

| Query | China Mode ON | China Mode OFF |
|-------|--------------|----------------|
| `google.com` | `0.0.0.0` (blocked by Pi-hole) | Resolves normally |
| `youtube.com` | `0.0.0.0` (blocked) | Resolves normally |
| `baidu.com` | Resolves via Alibaba DNS | Resolves via DC/public |
| `stemlab.lan` | Forwarded to DC `.20` ✓ | Handled by DC `.20` ✓ |
| `win-upu3jkf7n79.stemlab.lan` | Resolves via DC `.20` ✓ | Resolves via DC `.20` ✓ |
| Reverse DNS `.20.x` | Forwarded to DC `.20` ✓ | Handled by DC `.20` ✓ |
| VPN domains | `0.0.0.0` (blocked) | Resolves normally |

AD domain joins, GPOs, Kerberos, and internal services **continue to work** when China Mode is ON.

---

## GFW Blocklist

File: `configs/china-mode/pihole/blocklist-gfw.txt`

Loaded into Pi-hole gravity DB. Categories:

- Google (all services), Gmail, YouTube
- Social: Facebook, Instagram, WhatsApp, Twitter/X, Telegram, Discord, Snapchat, Reddit
- Reference: Wikipedia
- Messaging: Signal
- Video: Netflix, Twitch, TikTok (international)
- VPNs: NordVPN, ExpressVPN, ProtonVPN, Mullvad, Tor, 10+ others
- News: NYT, BBC, Guardian, WSJ, CNN, Reuters, Bloomberg, DW, RFA, VOA, etc.
- Human rights: Amnesty, HRW, Falun Dafa, Free Tibet, Epoch Times
- Dev: GitHub (raw/gist)
- Alt DNS: 8.8.8.8, 1.1.1.1, 9.9.9.9 (forces use of Pi-hole)

---

## Cisco ACL

Applied to `interface Vlan20 inbound` when China Mode is ON:

```
ip access-list extended CHINA-MODE-DNS-LOCK
 10 permit udp any host 172.16.20.21 eq 53   ! Only Pi-hole can serve DNS
 20 permit tcp any host 172.16.20.21 eq 53
 30 deny   udp any any eq 53 log             ! Block DNS bypass attempts
 40 deny   tcp any any eq 53 log
 50 permit ip any any                        ! All other traffic unaffected
```

When China Mode is OFF, the ACL definition is left on the router but is **not applied** to any interface.

---

## Verification

After enabling, from a VLAN 20 client:

```bash
nslookup google.com          # → 0.0.0.0 (blocked)
nslookup baidu.com           # → resolves
nslookup stemlab.lan         # → resolves via DC
nslookup 172.16.20.20        # → reverse DNS via DC
```

From Proxmox:
```bash
# Quick DNS check
dig +short google.com @172.16.20.21     # 0.0.0.0
dig +short baidu.com @172.16.20.21      # resolves
dig +short stemlab.lan @172.16.20.21    # resolves via DC

# Pi-hole admin
http://172.16.20.21/admin

# Status page
http://172.16.20.21:8888
```

---

## File Structure

```
configs/china-mode/
├── pihole/
│   └── blocklist-gfw.txt       GFW domain blocklist
├── nginx/
│   └── nginx.conf              CN geo-spoof proxy
├── mitmproxy/
│   └── inject_ads.py           Baidu ad injection addon
└── scripts/
    ├── china-on.sh             Enable (starts CT + auto-configures router)
    ├── china-off.sh            Disable (auto-configures router + stops CT)
    └── router_toggle.py        Python/netmiko router automation
```

Deployed to Proxmox at `/opt/china-mode/scripts/`.

---

## Maintenance

**Update blocklist:**
```bash
scp configs/china-mode/pihole/blocklist-gfw.txt root@172.16.67.3:/tmp/
ssh root@172.16.67.3 "pct push 200 /tmp/blocklist-gfw.txt /opt/china-mode/blocklist-gfw.txt"
ssh root@172.16.67.3 "pct exec 200 -- /usr/local/bin/pihole updateGravity"
```

**View Pi-hole query log:**
```bash
ssh root@172.16.67.3 "pct exec 200 -- pihole-FTL --stats"
```

**View mitmproxy logs:**
```bash
ssh root@172.16.67.3 "pct exec 200 -- journalctl -u mitmproxy-china -f"
```
