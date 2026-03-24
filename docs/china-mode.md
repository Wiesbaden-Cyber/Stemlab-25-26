# China Mode — GFW Simulation for VLAN 20

**Purpose:** Simulate the Great Firewall of China on VLAN 20 (Classroom) for educational/CTF use.
**Scope:** VLAN 20 only. VLANs 10, 30, and 67 are completely unaffected.
**Implemented:** 2026-03-24

---

## Architecture

```
VLAN 20 Client
     │
     ▼ DNS query
CT 200: Pi-hole (172.16.20.50:53)
  ├── Upstream: Alibaba DNS (223.5.5.5, 223.6.6.6)
  ├── Blocks: ~86K default domains + 200+ GFW-specific domains
  └── Allows: Chinese services (Baidu, JD, Taobao, WeChat, etc.)
     │
     ▼ HTTP traffic (port 80)
CT 200: nginx (172.16.20.50:80)
  └── Injects geo-spoof headers:
      X-Forwarded-For: 61.135.169.125 (Beijing IP)
      Accept-Language: zh-CN,zh;q=0.9
      CF-IPCountry: CN
     │
     ▼ HTTP responses
CT 200: mitmproxy (172.16.20.50:8081)
  └── inject_ads.py: Injects Baidu-style ad banner into HTML pages
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
| Network | vmbr1, VLAN tag 20, static 172.16.20.50/24, GW 172.16.20.1 |
| onboot | **0** (does NOT start automatically) |

### Services inside CT 200

| Service | Port | Purpose |
|---------|------|---------|
| pihole-FTL | :53 UDP/TCP | DNS filtering, upstream Alibaba 223.5.5.5 |
| pihole-FTL | :8080 | Pi-hole web admin |
| nginx | :80 | Transparent HTTP proxy with CN header injection |
| nginx | :8888 | China Mode status page |
| mitmproxy | :8081 | HTTP ad injection (Baidu banner) |

---

## Toggle: Enabling China Mode

### Step 1 — Start CT 200
Run on Proxmox or any machine with SSH access:
```bash
bash configs/china-mode/scripts/china-on.sh
```
Or manually:
```bash
ssh root@172.16.67.3 "pct start 200"
```

### Step 2 — Apply router config (on SillyRouter)
```
conf t
!
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
```

---

## Toggle: Disabling China Mode

### Step 1 — Stop CT 200
```bash
bash configs/china-mode/scripts/china-off.sh
```
Or manually:
```bash
ssh root@172.16.67.3 "pct stop 200"
```

### Step 2 — Apply router config (on SillyRouter)
```
conf t
!
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
```

> Note: The `CHINA-MODE-DNS-LOCK` ACL definition remains on the router but is not applied. Safe to leave.

---

## GFW Blocklist

File: `configs/china-mode/pihole/blocklist-gfw.txt`

Covers:
- **Search/Productivity:** Google (all services), Gmail
- **Social media:** Facebook, Instagram, WhatsApp, Twitter/X, Telegram, Discord, Snapchat, Reddit, Weibo (external)
- **Video:** YouTube, Netflix, Twitch, TikTok (international)
- **Reference:** Wikipedia, Wikimedia
- **Messaging:** Signal, WhatsApp, Telegram
- **VPNs:** NordVPN, ExpressVPN, ProtonVPN, Mullvad, Tor Project, and 10+ others
- **News:** NYT, BBC, Guardian, WSJ, CNN, Reuters, Bloomberg, DW, RFA, VOA
- **Human rights:** Amnesty, HRW, Falun Dafa, Epoch Times, Free Tibet
- **Dev tools:** GitHub (raw/gist), some cloud providers
- **Alternative DNS:** 8.8.8.8, 1.1.1.1, 9.9.9.9 (force use of Pi-hole)
- **Cloud storage:** Dropbox, Slack
- **Music:** Spotify

Allowed (resolves normally via Alibaba DNS):
- Baidu, JD.com, Taobao, Alibaba, Tencent, WeChat, Weibo (domestic), Bilibili, iQiyi, Youku, NetEase, Sina, Sohu

---

## Cisco ACL Reference

Applied to `interface Vlan20 inbound` when China Mode is ON:

```
ip access-list extended CHINA-MODE-DNS-LOCK
 10 permit udp any host 172.16.20.50 eq 53   ! Allow Pi-hole DNS only
 20 permit tcp any host 172.16.20.50 eq 53
 30 deny   udp any any eq 53 log             ! Block all other DNS (bypass prevention)
 40 deny   tcp any any eq 53 log
 50 permit ip any any                        ! All other traffic passes
```

This prevents clients from bypassing Pi-hole by manually setting DNS to 8.8.8.8 or 1.1.1.1.

---

## Verification

After enabling China Mode, from a VLAN 20 client:

```bash
# DNS check — should be blocked (returns 0.0.0.0)
nslookup google.com
nslookup youtube.com
nslookup github.com

# DNS check — should resolve
nslookup baidu.com
nslookup jd.com

# Pi-hole admin
http://172.16.20.50/admin

# Status page
http://172.16.20.50:8888
```

---

## File Structure

```
configs/china-mode/
├── pihole/
│   └── blocklist-gfw.txt       GFW domain blocklist (loaded into Pi-hole gravity)
├── nginx/
│   └── nginx.conf              CN geo-spoof proxy config
├── mitmproxy/
│   └── inject_ads.py           Baidu ad injection mitmproxy addon
└── scripts/
    ├── china-on.sh             Enable China Mode (starts CT, prints router config)
    └── china-off.sh            Disable China Mode (stops CT, prints router config)
```

---

## Maintenance

**Update blocklist:**
```bash
# Edit configs/china-mode/pihole/blocklist-gfw.txt, then:
scp configs/china-mode/pihole/blocklist-gfw.txt root@172.16.67.3:/tmp/
ssh root@172.16.67.3 "pct push 200 /tmp/blocklist-gfw.txt /opt/china-mode/blocklist-gfw.txt"
ssh root@172.16.67.3 "pct exec 200 -- /usr/local/bin/pihole updateGravity"
```

**Check Pi-hole stats:**
```bash
ssh root@172.16.67.3 "pct exec 200 -- pihole-FTL --stats"
```

**View mitmproxy injection logs:**
```bash
ssh root@172.16.67.3 "pct exec 200 -- journalctl -u mitmproxy-china -f"
```
