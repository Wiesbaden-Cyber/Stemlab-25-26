# StemLab Network Overview
**Last updated:** 2026-03-25
**Domain:** `stemlab.lan`
**Internet:** Starlink (CGNAT — no inbound port forwarding)
**Remote access:** Tailscale VPN

---

## VLANs

| VLAN | Name | Subnet | Gateway | Notes |
|------|------|--------|---------|-------|
| 10 | Lab | 172.16.10.0/24 | 172.16.10.1 | Lab devices and servers. PXE boot via DHCP option 66/67 (iPXE). |
| 20 | Classroom | 172.16.20.0/24 | 172.16.20.1 | Student PCs, Windows Server, FreeRADIUS. DNS via 172.16.20.20. |
| 30 | Guest | 172.16.30.0/24 | 172.16.30.1 | Guest WiFi, internet only. |
| 67 | Management | 172.16.67.0/28 | 172.16.67.1 | Infrastructure SSH/management. Restricted to mgmt subnet + Tailscale. |

---

## Topology Diagram

```
                     ┌──────────────────────────────────┐
                     │       INTERNET (Starlink)         │
                     │            CGNAT                  │
                     └─────────────────┬────────────────┘
                                       │ WAN (DHCP) — Gi0/0/0
                            ┌──────────▼──────────┐
                            │      SillyRouter      │
                            │  Cisco ISR C1112      │
                            │   172.16.67.1/28      │
                            │  IOS XE 17.06.01a     │
                            │                       │
                            │ VLAN10: 172.16.10.1   │
                            │ VLAN20: 172.16.20.1   │
                            │ VLAN30: 172.16.30.1   │
                            │ VLAN67: 172.16.67.1   │
                            └──────────┬────────────┘
                                       │ Trunk VLANs 10,20,30,67
                                       │ Gi0/1/0 ↔ Gi1/0/48
                            ┌──────────▼──────────┐
                            │      SillySwitch      │
                            │ Cisco C3750X-48P PoE  │
                            │   172.16.67.2/28      │
                            │  IOS 15.0(2)SE        │
                            └──┬────────┬───────────┘
                               │        │
            ┌──────────────────┘        └──────────────────────────┐
            │ Gi1/0/25                  Gi1/0/26            Other  │
            │ Trunk (VLANs 10,20,30,67) Trunk (NAS)               │
            │                           VLANs 10,20,30,67          │
 ┌──────────▼──────────┐   ┌────────────▼──────────┐              │
 │     SillyProxmox     │   │       SillyNAS         │              │
 │  Proxmox VE 9.1.4    │   │  TrueNAS 25.04.2.6    │              │
 │   172.16.67.3/28     │   │  Mgmt:  172.16.67.4   │              │
 │  vmbr1 (VLAN-aware)  │   │  Data:  172.16.20.25  │              │
 └──────────┬───────────┘   └───────────────────────┘              │
            │                                                       │
            │ VMs & Containers:                         Gi1/0/27   │
            │ ┌────────────────────────────────────┐   VLAN 20     │
            │ │ CT100  Tailscale       (running)   │       │        │
            │ │ VM101  OPNsense-Redstone (running) │       ▼        │
            │ │ VM102  Worker-1          (stopped) │  SillyEdge-    │
            │ │ VM103  PXE               (stopped) │  Switch        │
            │ │ VM104  DO-Local-Ubuntu   (running) │  Cisco 2960    │
            │ │ VM105  WindowsServer1776 (running) │  172.16.67.5   │
            │ │ VM106  ADDC              (stopped) │  IOS 15.0(2)   │
            │ │ VM107  FreeRADIUS-CA     (running) │  SE11          │
            │ │ VM108  VM 108            (running) │       │        │
            │ │ VM109  CDS-n8n           (running) │  Fa0/1-8       │
            │ └────────────────────────────────────┘  Classroom PCs │
            │                                         (VLAN 20)     │
            │ AP Trunks (Gi1/0/1-4, Gi1/0/43):                     │
            └───────────────────────────────────────────────────────►
                                                      WiFi APs
                                                 (VLANs 10,20,30,67)

  ─ ─ ─ ─ ─ ─ ─ ─ ─  Tailscale Overlay (100.x.x.x)  ─ ─ ─ ─ ─ ─
  100.83.36.66    indasky314-latitude-5400   Linux    online
  100.101.252.125 glkvm                      Linux    online
  100.112.34.75   lab-access-pve-ct100       Linux    active (→ 172.16.67.9)
  100.99.26.112   desktop-d5qip0j            Windows  offline
  100.68.15.46    indasky314-windows-desktop Windows  offline
  100.89.46.114   google-pixel-7-pro         Android  offline
  100.114.69.1    samsung-sm-s906u1          Android  offline
  100.112.147.101 google-pixel-8a            Android  offline
  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
```

---

## DHCP Reservations / Excluded Statics

| IP | Device |
|----|--------|
| 172.16.10.58 | dolus (stemlab-drinks server, Ubuntu 24.04) |
| 172.16.10.175 | Home Assistant (HAOS, port 8123) |
| 172.16.10.91 | Reserved |
| 172.16.10.1–.25 | Infrastructure reserved |
| 172.16.20.1–.25 | Infrastructure reserved |
| 172.16.20.100 | Reserved |
| 172.16.20.20 | Classroom DNS server |
| 172.16.67.1–.5 | Infrastructure static IPs |

---

## Security Notes

- All management SSH restricted to `172.16.67.0/28` and Tailscale IP `100.83.36.66`
- Router: `login block-for 60 attempts 3 within 30`
- All VTY lines: SSH only, no telnet
- HTTP disabled on switches; HTTPS on router restricted to MGMT VLAN
- NTP synced to pool.ntp.org (router only — switch clocks are not synced)
