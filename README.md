# Stemlab 25-26

After the 2024-2025 school year, the leading members of WHS Cyber collectively decided to purge the former Stemlab network and services and build from the ground up. This repository contains the progress, configurations, and topology of the new network so it will be easier for future generations of WHS Cyber to maintain.

**Equipment Inventory:** https://docs.google.com/spreadsheets/d/1aUcI05Rr5SPrz92-eQHCEz22Fs3st3txNgSH49QERJQ/edit?gid=1553455283#gid=1553455283

**Robotics Laptop Inventory:** https://docs.google.com/spreadsheets/d/10iJD4ZSQDPhJi8wSGX7vu1GKLMVjeyPoqO32ILrjyg4/edit?gid=1050636524#gid=1050636524

**Cyber Laptops Inventory:** https://docs.google.com/spreadsheets/d/19fo2TNyiHjBWy3HBkygxVRyiggmL0TBg1rgQep-RWFk/edit?gid=1975505725#gid=1975505725

---

## Network Summary

**Domain:** `silly.lab.local`
**Internet:** Starlink (CGNAT — no inbound port forwarding)
**Remote access:** Tailscale VPN overlay

### VLANs

| VLAN | Name | Subnet | Gateway |
|------|------|--------|---------|
| 10 | Lab | 172.16.10.0/24 | 172.16.10.1 |
| 20 | Classroom | 172.16.20.0/24 | 172.16.20.1 |
| 30 | Guest | 172.16.30.0/24 | 172.16.30.1 |
| 67 | Management | 172.16.67.0/28 | 172.16.67.1 |

### Infrastructure

| Device | Role | IP | Hardware | OS/Version |
|--------|------|----|----------|------------|
| SillyRouter | WAN edge, NAT, DHCP | 172.16.67.1 | Cisco ISR C1112-8PLTEEA | IOS XE 17.06.01a |
| SillySwitch | Core L2 switch, 48-port PoE | 172.16.67.2 | Cisco Catalyst WS-C3750X-48P | IOS 15.0(2)SE |
| SillyProxmox | Hypervisor | 172.16.67.3 | 24-core, 96 GB RAM, ~2.6 TB ZFS | Proxmox VE 9.1.4 |
| SillyNAS | Network storage | 172.16.67.4 | 4-NIC, RAIDZ1 + single disk | TrueNAS 25.04.2.6 |
| SillyEdgeSwitch | Classroom edge switch | 172.16.67.5 | Cisco Catalyst 2960 | IOS 15.0(2)SE11 |

For full topology and details see [`docs/network-overview.md`](docs/network-overview.md).

---

## Repository Structure

```
configs/
├── SillyRouter.cfg                    # Cisco ISR 1100 running config
├── SillySwitch.cfg                    # Cisco C3750X running config (core)
├── SillyEdgeSwitch.cfg                # Cisco 2960 running config (classroom)
├── proxmox/
│   ├── network-interfaces.conf        # /etc/network/interfaces
│   ├── storage.cfg                    # Proxmox storage pools
│   └── vms-and-containers.md          # VM/CT inventory
└── nas/
    └── SillyNAS.md                    # TrueNAS network, pools & shares
docs/
└── network-overview.md                # Full topology diagram & notes
```
