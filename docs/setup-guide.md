# StemLab 25-26 — From-Scratch Setup Guide

**Maintainers:** WHS Cyber Club
**Last updated:** 2026-03-23
**Scope:** Complete rebuild of the StemLab network and services from bare hardware.

This guide walks through rebuilding every layer of the StemLab environment in dependency order — physical infrastructure first, then networking, then virtualization and services. Follow sections in sequence. Cross-references to companion docs are provided wherever full details live in a dedicated file.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites and Inventory](#2-prerequisites-and-inventory)
3. [Physical Setup](#3-physical-setup)
4. [Router Setup — SillyRouter](#4-router-setup--sillyrouter)
5. [Core Switch Setup — SillySwitch](#5-core-switch-setup--sillyswitch)
6. [Classroom Edge Switch — SillyEdgeSwitch](#6-classroom-edge-switch--sillyedgeswitch)
7. [Proxmox Hypervisor Setup — SillyProxmox](#7-proxmox-hypervisor-setup--sillyproxmox)
8. [TrueNAS Setup — SillyNAS](#8-truenas-setup--sillynas)
9. [Windows Domain Controller — VM105](#9-windows-domain-controller--vm105)
10. [FreeRADIUS Setup — VM107](#10-freeradius-setup--vm107)
11. [Wireless AP Setup](#11-wireless-ap-setup)
12. [stemlab-drinks Service](#12-stemlab-drinks-service)
13. [Joining Clients to the Domain](#13-joining-clients-to-the-domain)
14. [Verification Checklist](#14-verification-checklist)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Overview

StemLab is the network infrastructure operated by WHS Cyber at Wiesbaden High School. It provides a hands-on networking and IT environment for Cyber, Robotics, and Coding students. The lab was fully rebuilt from scratch for the 2025-2026 school year after the previous environment was decommissioned.

**What the lab provides:**

- A segmented VLAN network with separate Lab, Classroom, Guest, and Management zones
- A Windows Active Directory domain (`stemlab.lan`) with ~500+ student accounts, home drives, and GPOs
- Wireless access via Aruba APs with WPA2-Enterprise (RADIUS), a student/staff SSID, and a guest SSID
- A Proxmox hypervisor running all server VMs and containers
- A TrueNAS storage server providing SMB home drives and shared storage
- The `stemlab-drinks` drink ordering service, publicly accessible at `https://drinks.velocit.ee`
- Remote management access via Tailscale VPN (required because Starlink uses CGNAT)

**Who maintains it:**

Senior members of the WHS Cyber Club are responsible for infrastructure upkeep. Student guidelines, equipment inventory, and laptop inventories are tracked in [`resources/`](../resources/).

---

## 2. Prerequisites and Inventory

### 2.1 Hardware Required

Refer to [`resources/WHS-Cyber-Donated-Resources.xlsx`](../resources/WHS-Cyber-Donated-Resources.xlsx) for the full donated equipment inventory.

| Device | Hardware | Minimum Requirements |
|--------|----------|----------------------|
| SillyRouter | Cisco ISR C1112-8PLTEEA | IOS XE 17.x, console cable (USB-to-RJ45) |
| SillySwitch | Cisco Catalyst WS-C3750X-48P | IOS 15.0(2)SE or later, console cable |
| SillyEdgeSwitch | Cisco Catalyst 2960 | IOS 15.0(2)SE11 or later, console cable |
| SillyProxmox | Any x86-64 server | 24+ cores, 96 GB RAM, ~3 TB storage, dual-port NIC |
| SillyNAS | Any x86-64 with 4 NICs | 4 drives (RAIDZ1 min), TrueNAS-compatible NICs |
| AP x3+ | Aruba APIN0205 | Console cable (USB-to-serial), TFTP host, firmware image |

### 2.2 Software and Accounts

Before starting, download and have ready:

| Item | Source / Notes |
|------|---------------|
| Proxmox VE ISO (9.x) | https://www.proxmox.com/en/downloads |
| TrueNAS SCALE ISO (25.x) | https://www.truenas.com/download-truenas-scale/ |
| Windows Server 2025 Evaluation ISO | https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025 |
| Ubuntu Server 24.04 LTS ISO | https://ubuntu.com/download/server |
| Aruba Instant firmware: `ArubaInstant_Taurus_6.5.4.15_73677` | Aruba support portal or internal archive |
| Cloudflare account (free tier) | https://dash.cloudflare.com |
| Tailscale account | https://tailscale.com |
| Domain `velocit.ee` (for drinks service) | Namecheap or iwantmyname — add to Cloudflare after purchase |

### 2.3 Credentials and Secrets

Do not store credentials in this repository. Before starting, prepare:

- Router enable secret and local usernames (`admin`, `readonly`)
- Switch local usernames (`admin`, `readonly`)
- Proxmox root password
- TrueNAS admin password
- Windows Server 2025 local Administrator password
- Domain Administrator password (used for domain joins)
- stemlab-drinks `ADMIN_PIN` and Postgres password (stored in `.env` on dolus)
- Tailscale auth key for adding new nodes
- Cloudflare API token or tunnel credentials

### 2.4 Workstation Requirements

You will need a workstation with:

- A USB-to-RJ45 console cable (Cisco rollover)
- A USB-to-serial adapter if using older console ports
- Terminal emulator: PuTTY, minicom, or `screen` (9600 baud, 8N1)
- SSH client
- A way to serve files over TFTP (see Section 11 and [`docs/guides/aruba-tftp-server.md`](guides/aruba-tftp-server.md))

---

## 3. Physical Setup

### 3.1 Rack / Bench Layout

Recommended top-to-bottom order for a standard rack or bench:

1. Starlink dish (wall or ceiling mount) — coax/ethernet to router WAN
2. **SillyRouter** (Cisco ISR C1112) — 1U
3. **SillySwitch** (Cisco C3750X) — 1U, PoE
4. **SillyProxmox** — 2U server
5. **SillyNAS** — 2U server
6. Patch panel (optional but recommended)

SillyEdgeSwitch lives in the classroom, connected back to SillySwitch via a trunk cable.

### 3.2 Cabling

| From | Port | To | Port | Type | VLAN(s) |
|------|------|----|------|------|---------|
| Starlink | Ethernet out | SillyRouter | Gi0/0/0 (WAN) | CAT6 | — |
| SillyRouter | Gi0/1/0 | SillySwitch | Gi1/0/48 | CAT6 | Trunk: 10,20,30,67 |
| SillySwitch | Gi1/0/25 | SillyProxmox | enp8s0f1 | CAT6 | Trunk: 10,20,30,67 |
| SillySwitch | Gi1/0/26 | SillyNAS | enp15s0 | CAT6 | Trunk: 10,20,30,67 |
| SillySwitch | Gi1/0/27 | SillyEdgeSwitch | Gi0/1 (uplink) | CAT6 | Trunk: 20 |
| SillySwitch | Gi1/0/1–4 | Aruba APs | Ethernet | CAT6 | Trunk: 10,20,30,67 |
| SillySwitch | Gi1/0/43 | Aruba AP | Ethernet | CAT6 | Trunk: 10,20,30,67 |
| SillySwitch | Mgmt VLAN | SillyNAS | enp14s0 | CAT6 | VLAN 67 (Mgmt) |
| SillyProxmox | enp8s0f0 | SillySwitch | Any VLAN10 port | CAT6 | VLAN 10 (untagged) |

> Note: SillyProxmox uses a dual-port NIC. `enp8s0f0` provides untagged VLAN 10 access (vmbr0/DHCP). `enp8s0f1` carries the tagged VLAN trunk (vmbr1, Management IP 172.16.67.3).

### 3.3 Power-On Order

Power on devices in this order to avoid DHCP/spanning-tree issues:

1. Starlink dish (allow 2-3 min to acquire satellite lock)
2. SillyRouter
3. SillySwitch
4. SillyNAS
5. SillyProxmox
6. SillyEdgeSwitch
7. Aruba APs (PoE from SillySwitch)

### 3.4 Connecting to Starlink

Starlink uses CGNAT — there is no public IP and no inbound port forwarding. The WAN interface on SillyRouter receives a DHCP address from Starlink. This is normal and expected. All external access to internal services uses Cloudflare Tunnel (for drinks.velocit.ee) or Tailscale VPN (for management).

---

## 4. Router Setup — SillyRouter

**Hardware:** Cisco ISR C1112-8PLTEEA
**Target OS:** IOS XE 17.06.01a
**Management IP:** 172.16.67.1

### 4.1 Initial Console Access

1. Connect a USB-to-RJ45 console cable from your workstation to the router's console port.
2. Open a terminal at 9600 baud, 8N1, no flow control:
   ```
   screen /dev/ttyUSB0 9600
   ```
   On Windows, use PuTTY with the appropriate COM port.
3. Power on the router. You will see IOS XE boot output.

### 4.2 Factory Reset (if needed)

If the router has a prior config, reset it before applying the StemLab config:

```
Router> enable
Router# write erase
Router# reload
```

At the "Would you like to enter the initial configuration dialog?" prompt, answer **no**.

### 4.3 Applying the SillyRouter Config

The full running config is stored at [`configs/SillyRouter.cfg`](../configs/SillyRouter.cfg).

**Method 1: Paste directly via console**

1. Enter global configuration mode:
   ```
   Router# configure terminal
   ```
2. Copy the contents of `configs/SillyRouter.cfg` (excluding the comment header lines starting with `!` that are purely informational) and paste them into the terminal session in blocks. IOS XE accepts pasted config well, but paste in sections of ~20 lines to avoid buffer overflows.
3. Exit and save:
   ```
   Router(config)# end
   Router# write memory
   ```

**Method 2: TFTP (if TFTP server is available)**

```
Router# copy tftp running-config
Address or name of remote host? 192.168.1.10
Source filename? SillyRouter.cfg
Destination filename? running-config
```

### 4.4 Key Config Elements

After applying the config, verify these are in place:

**DHCP pools:**

| Pool | Network | Gateway | DNS |
|------|---------|---------|-----|
| LAB | 172.16.10.0/24 | 172.16.10.1 | 8.8.8.8 (+ TFTP option 66/67 for PXE) |
| CLASSROOM | 172.16.20.0/24 | 172.16.20.1 | 172.16.20.20 (DC), 8.8.8.8 |
| GUEST | 172.16.30.0/24 | 172.16.30.1 | 8.8.8.8 |
| MANAGEMENT | 172.16.67.0/28 | 172.16.67.1 | 8.8.8.8 |

**DHCP excluded addresses** (static reservations):

```
172.16.10.1–10.25      Infrastructure reserved
172.16.10.58           dolus (stemlab-drinks)
172.16.10.91           Reserved
172.16.20.1–20.25      Infrastructure reserved
172.16.20.100          FreeRADIUS
172.16.30.1–30.5       Infrastructure reserved
172.16.67.1–67.5       Infrastructure statics
```

**NAT:** PAT (overload) on `GigabitEthernet0/0/0` for all internal VLANs (`LAN-NETS` ACL).

**VLAN SVIs:**

```
Vlan10 — 172.16.10.1/24
Vlan20 — 172.16.20.1/24
Vlan30 — 172.16.30.1/24
Vlan67 — 172.16.67.1/28
```

**Access Control:**

```
MGMT-ONLY ACL — permits 172.16.67.0/28 and Tailscale IP 100.83.36.66
DOLUS-RESTRICT — blocks dolus (172.16.10.58) from reaching Proxmox port 8006
```

**SSH and login hardening:**

```
ip ssh version 2
ip ssh time-out 60
ip ssh authentication-retries 2
login block-for 60 attempts 3 within 30
```

### 4.5 Verifying the Router

After applying config and saving:

```
SillyRouter# show ip interface brief
SillyRouter# show ip dhcp binding
SillyRouter# show ip route
SillyRouter# show ip nat translations
```

Verify:
- `GigabitEthernet0/0/0` has a DHCP address from Starlink (will be in 100.x.x.x range)
- All four VLAN SVIs show `up/up` in the interface brief
- Default route (`0.0.0.0/0`) appears in the routing table via the WAN interface
- After connecting a test client to VLAN 10, it should receive a 172.16.10.x DHCP address and be able to ping 8.8.8.8

**Test SSH access from management VLAN:**

```bash
ssh admin@172.16.67.1
```

---

## 5. Core Switch Setup — SillySwitch

**Hardware:** Cisco Catalyst WS-C3750X-48P (48-port PoE)
**Target OS:** IOS 15.0(2)SE
**Management IP:** 172.16.67.2 (SVI Vlan67)

### 5.1 Console Access

Connect a console cable as described in Section 4.1. Baud rate is 9600.

### 5.2 Factory Reset (if needed)

```
Switch> enable
Switch# write erase
Switch# delete flash:vlan.dat
Switch# reload
```

Answer **no** to the initial configuration dialog.

### 5.3 Applying the SillySwitch Config

The full config is at [`configs/SillySwitch.cfg`](../configs/SillySwitch.cfg).

1. Enter global config mode:
   ```
   Switch# configure terminal
   ```
2. Paste the config in sections. Key items to apply first:
   - Hostname
   - AAA and usernames
   - VLANs (10, 20, 30, 67)
   - VTP mode transparent
   - SSH version 2
   - Interface configs
   - Management SVI and default route

3. Save:
   ```
   Switch(config)# end
   Switch# write memory
   ```

### 5.4 Key Config Elements

**VTP:** Transparent mode — VLANs are defined locally, not distributed via VTP.

**VLANs defined:**

```
vlan 10 — Lab
vlan 20 — Classroom
vlan 30 — Guest
vlan 67 — Management
```

**Port assignments:**

| Ports | Mode | VLAN(s) | Notes |
|-------|------|---------|-------|
| Gi1/0/1–4, Gi1/0/43 | Trunk | 10,20,30,67 | AP uplinks (PoE), native VLAN 67 |
| Gi1/0/13–24 | Access | 10 | Lab devices |
| Gi1/0/25 | Trunk | 10,20,30,67 | SillyProxmox uplink |
| Gi1/0/26 | Trunk | 10,20,30,67 | SillyNAS uplink |
| Gi1/0/27 | Trunk | 20 | SillyEdgeSwitch uplink |
| Gi1/0/28–42 | Access | 20 | Classroom devices |
| Gi1/0/48 | Trunk | 10,20,30,67 | SillyRouter uplink |

**Spanning tree:** PVST, portfast enabled on all access ports, bpduguard on access ports, errdisable recovery for bpduguard.

**PoE:** PoE enabled on AP trunk ports (Gi1/0/1–4, Gi1/0/43) by default on the 3750X-48P.

### 5.5 Verifying the Switch

```
SillySwitch# show vlan brief
SillySwitch# show interfaces trunk
SillySwitch# show spanning-tree summary
SillySwitch# show power inline
```

Verify:
- All four VLANs (10, 20, 30, 67) appear as active in `show vlan brief`
- Trunk ports show the correct allowed VLANs
- PoE ports show power being delivered to connected APs

**Test SSH:**

```bash
ssh admin@172.16.67.2
```

---

## 6. Classroom Edge Switch — SillyEdgeSwitch

**Hardware:** Cisco Catalyst 2960
**Target OS:** IOS 15.0(2)SE11
**Management IP:** 172.16.67.5 (SVI Vlan67)

### 6.1 Console Access and Factory Reset

Same procedure as SillySwitch (Section 5.1–5.2). The 2960 also uses `write erase` and `delete flash:vlan.dat`.

### 6.2 Applying the SillyEdgeSwitch Config

The full config is at [`configs/SillyEdgeSwitch.cfg`](../configs/SillyEdgeSwitch.cfg).

Apply via console paste or TFTP as described for SillySwitch.

### 6.3 Key Config Elements

The 2960 is a simpler access-layer switch. All classroom PC ports are VLAN 20 access ports with portfast and bpduguard. The uplink to SillySwitch is a VLAN 20 trunk.

**Port assignments:**

| Ports | Mode | VLAN | Notes |
|-------|------|------|-------|
| Fa0/1–Fa0/8+ | Access | 20 | Classroom PCs, portfast + bpduguard |
| Gi0/1 (uplink) | Trunk | 20 | Uplink to SillySwitch Gi1/0/27 |

**VTP:** Transparent mode (VTP domain: TMW).

### 6.4 Verifying the Edge Switch

```
SillyEdgeSwitch# show vlan brief
SillyEdgeSwitch# show interfaces trunk
SillyEdgeSwitch# show cdp neighbors
```

A classroom PC connected to a Fa0/x port should receive a 172.16.20.x DHCP address and be able to reach the domain controller at 172.16.20.20.

**Test SSH:**

```bash
ssh admin@172.16.67.5
```

---

## 7. Proxmox Hypervisor Setup — SillyProxmox

**Hardware:** 24-core, 96 GB RAM, ~2.6 TB ZFS
**Target OS:** Proxmox VE 9.1.4
**Management IP:** 172.16.67.3 (vmbr1, VLAN 67)

### 7.1 Installing Proxmox VE

1. Download the Proxmox VE 9.x ISO from https://www.proxmox.com/en/downloads.
2. Write it to a USB drive:
   ```bash
   dd if=proxmox-ve_9.x.iso of=/dev/sdX bs=4M status=progress
   ```
3. Boot the server from the USB drive.
4. In the Proxmox installer:
   - Accept the EULA.
   - Select the target disk(s). For ZFS, select all drives that will form the pool and choose `ZFS (RAID-Z1)` or your preferred layout.
   - Set country, timezone, and keyboard layout.
   - Set the management IP. During install, use any temporary IP — you will reconfigure networking after.
   - Set the root password and admin email.
5. Complete the installation and reboot.

### 7.2 Initial Access

Access the Proxmox web UI at `https://<installer-IP>:8006` from a machine on the same VLAN. Log in as `root`.

### 7.3 Applying the Network Configuration

The network config is stored at [`configs/proxmox/network-interfaces.conf`](../configs/proxmox/network-interfaces.conf).

1. SSH to the Proxmox host:
   ```bash
   ssh root@<current-IP>
   ```
2. Back up the existing network config:
   ```bash
   cp /etc/network/interfaces /etc/network/interfaces.bak
   ```
3. Replace it with the repo config. The target state is:

   ```
   auto lo
   iface lo inet loopback

   auto enp8s0f0
   iface enp8s0f0 inet manual

   auto enp8s0f1
   iface enp8s0f1 inet manual

   # vmbr0 — DHCP, VLAN 10 untagged access
   auto vmbr0
   iface vmbr0 inet dhcp
       bridge-ports enp8s0f0
       bridge-stp off
       bridge-fd 0

   # vmbr1 — VLAN-aware trunk, Management IP
   auto vmbr1
   iface vmbr1 inet static
       address 172.16.67.3/28
       gateway 172.16.67.1
       bridge-ports enp8s0f1
       bridge-stp off
       bridge-fd 0
       bridge-vlan-aware yes
       bridge-vids 2-4094

   # vmbr2 — Isolated internal bridge (OPNsense testing)
   auto vmbr2
   iface vmbr2 inet manual
       bridge-ports none
       bridge-stp off
       bridge-fd 0
       bridge-vlan-aware yes
       bridge-vids 2-4094
   ```

4. Adjust `enp8s0f0` and `enp8s0f1` to match the actual NIC names on your hardware (check with `ip link`).

5. Apply the config:
   ```bash
   ifreload -a
   ```
   Or reboot: `reboot`

6. Verify connectivity: `ping 172.16.67.1`

### 7.4 Storage Configuration

The storage config is at [`configs/proxmox/storage.cfg`](../configs/proxmox/storage.cfg).

Proxmox uses:
- `local` — `/var/lib/vz` — for ISOs, backups, CT templates
- `local-zfs` — ZFS pool `rpool/data` — for VM disk images and CT rootdirs

If the ZFS pool was created during install as `rpool`, this should already be configured. Verify in the UI under **Datacenter → Storage** or:

```bash
pvesm status
zpool status rpool
```

To add additional storage (e.g., a second ZFS pool), use the Proxmox UI: **Datacenter → Storage → Add → ZFS**.

### 7.5 Uploading ISOs

Upload ISOs needed for VMs:
1. In the Proxmox UI, go to **pve → local → ISO Images → Upload**.
2. Upload Windows Server 2025 Eval ISO and Ubuntu Server 24.04 ISO.

Alternatively, from the Proxmox shell:
```bash
wget -O /var/lib/vz/template/iso/ubuntu-24.04-server.iso <URL>
```

### 7.6 Creating VMs and Containers

Refer to [`configs/proxmox/vms-and-containers.md`](../configs/proxmox/vms-and-containers.md) for the full inventory of VMs and containers. The critical ones for this setup are:

| VMID | Name | Purpose | Section |
|------|------|---------|---------|
| 100 | Tailscale | Remote access CT | 7.7 |
| 105 | WindowsServer1776 | Domain Controller | Section 9 |
| 107 | FreeRADIUS-CA-Ubuntu-Server | FreeRADIUS | Section 10 |
| dolus (CT) | stemlab-drinks | Drinks service | Section 12 |

### 7.7 Tailscale Container (CT100)

The Tailscale container provides remote access to the management network when you are off-site.

1. Download an Ubuntu 24.04 LXC template:
   ```bash
   pveam update
   pveam available | grep ubuntu-24
   pveam download local ubuntu-24.04-standard_*.tar.zst
   ```

2. Create the container in the Proxmox UI:
   - **CT ID:** 100
   - **Template:** ubuntu-24.04-standard
   - **Storage:** local-zfs, 12 GB
   - **CPU:** 1 core
   - **Memory:** 256 MB
   - **Network:** vmbr1, DHCP
   - **Unprivileged:** yes
   - **onboot:** yes

3. **Enable TUN device access** (required for Tailscale in LXC):
   In `/etc/pve/lxc/100.conf` add:
   ```
   lxc.cgroup2.devices.allow: c 10:200 rwm
   lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
   ```

4. Start the container and enter it:
   ```bash
   pct start 100
   pct exec 100 -- bash
   ```

5. Install Tailscale:
   ```bash
   apt update && apt install -y curl
   curl -fsSL https://tailscale.com/install.sh | sh
   tailscale up --advertise-routes=172.16.67.0/28 --accept-routes
   ```

6. Authenticate in your Tailscale dashboard and approve the subnet route `172.16.67.0/28`.

---

## 8. TrueNAS Setup — SillyNAS

**Hardware:** 4-NIC server, 4 drives (RAIDZ1) + 1 single disk
**Target OS:** TrueNAS SCALE 25.04.2.6
**Management IP:** 172.16.67.4 (enp14s0)
**Data IP:** 172.16.20.25 (enp15s0)

Full TrueNAS configuration is documented in [`configs/nas/SillyNAS.md`](../configs/nas/SillyNAS.md).

### 8.1 Installing TrueNAS SCALE

1. Write the TrueNAS SCALE ISO to a USB drive and boot the server from it.
2. Follow the installer:
   - Select the boot drive (a separate SSD or USB drive, NOT one of the storage drives).
   - Set the admin password.
3. After install, the system will reboot. Note the IP address shown on the console — this is used to access the web UI.

### 8.2 Network Configuration

1. Open the TrueNAS web UI at `http://<installer-IP>`.
2. Go to **Network → Interfaces**. Configure:

   | Interface | IP Address | Subnet |
   |-----------|-----------|--------|
   | enp14s0 | 172.16.67.4 | /28 |
   | enp15s0 | 172.16.20.25 | /24 |

3. Set the default gateway to `172.16.67.1`.
4. Set DNS servers: `8.8.8.8`, `1.1.1.1`.
5. Apply changes — the UI will reconnect at the new management IP.

### 8.3 Storage Pools

Create two pools:

**STUDENT_STORAGE (RAIDZ1):**
1. Go to **Storage → Create Pool**.
2. Name: `STUDENT_STORAGE`
3. Layout: RAIDZ1, add all four data drives (`sda`, `sdb`, `sdc`, `sdd`).
4. Create.

**CYBER_LAB (single disk):**
1. Go to **Storage → Create Pool**.
2. Name: `CYBER_LAB`
3. Layout: Stripe (single disk), add the fifth drive.
4. Create.

### 8.4 Datasets

Under STUDENT_STORAGE, create:

```
STUDENT_STORAGE/homes
STUDENT_STORAGE/shared
```

Under CYBER_LAB, create:

```
CYBER_LAB/APT_CACHE
```

Set permissions on `homes` to allow AD users to create and own their own home directories. This is managed via SMB home directories (see 8.5).

### 8.5 SMB Shares

1. Go to **Shares → Windows (SMB) Shares → Add**:

   | Share Name | Path | Notes |
   |------------|------|-------|
   | student_homes | /mnt/STUDENT_STORAGE/homes | Home directories for AD students |
   | shared | /mnt/STUDENT_STORAGE/shared | Shared class files |

2. For `student_homes`, enable **Use as Home Share** so each user gets a personal folder automatically.

3. Start the SMB service: **Services → SMB → Start**.

### 8.6 NFS Share (APT Cache)

1. Go to **Shares → Unix (NFS) Shares → Add**:
   - Path: `/mnt/CYBER_LAB/APT_CACHE`
   - Authorized networks: `172.16.10.0/24` (Lab VLAN)

2. Start the NFS service: **Services → NFS → Start**.

### 8.7 SMB Transport Encryption

Enforce SMB3 signing and encryption on all connections:

1. Go to **Shares → Windows (SMB) Shares**.
2. Click the three-dot menu next to each share → **Edit**.
3. Under **Advanced Options**, set **Transport Encryption Behavior** to **Required**.

This requires SMB3 from all clients. Windows 10/11 and modern macOS support this by default.

### 8.8 Domain Join (Optional)

For AD-integrated share permissions, join TrueNAS to the `stemlab.lan` domain:

1. Go to **Credentials → Directory Services → Active Directory**.
2. Enter:
   - Domain: `stemlab.lan`
   - Account: `Administrator`
   - Password: *(domain admin password)*
3. Click **Save and Enable**.

---

## 9. Windows Domain Controller — VM105

**Proxmox VMID:** 105
**Hostname:** WIN-UPU3JKF7N79
**IP:** 172.16.20.20 (static)
**VLAN:** 20 (Classroom)

Full domain documentation is in [`docs/windows-domain.md`](windows-domain.md).

### 9.1 Creating the VM in Proxmox

1. In the Proxmox UI, click **Create VM**.
2. Configure:

   | Setting | Value |
   |---------|-------|
   | VM ID | 105 |
   | Name | WindowsServer1776 |
   | ISO | Windows Server 2025 Eval |
   | OS Type | Microsoft Windows, 11/2022 |
   | BIOS | OVMF (UEFI) |
   | Add TPM | Yes, TPM 2.0 |
   | CPU | 3 sockets × 3 cores (9 vCPU total) |
   | RAM | 8 GB |
   | Disk | 70 GB on local-zfs |
   | Network | vmbr1, VLAN Tag 20 |

3. Before starting, also add a VirtIO SCSI controller and download the VirtIO drivers ISO from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/ — attach it as a second CD drive. Windows Server 2025 needs VirtIO drivers to see the disk during install.

4. Start the VM and open the Proxmox console (noVNC).

### 9.2 Installing Windows Server 2025

1. Boot from the ISO.
2. Select language and keyboard settings.
3. Choose **Windows Server 2025 Standard (Desktop Experience)**.
4. Select **Custom: Install Windows only**.
5. When no drives appear, click **Load driver** → browse the VirtIO ISO → `viostor/2k25/amd64` → select the driver.
6. Complete the installation. Set the local Administrator password.

### 9.3 Post-Install Configuration

1. In Windows Server, open **Server Manager → Local Server**.
2. Set a static IP:
   - IP: `172.16.20.20`
   - Subnet: `255.255.255.0`
   - Gateway: `172.16.20.1`
   - DNS: `127.0.0.1` (will point to itself after DC promotion)

3. Set the hostname to `WIN-UPU3JKF7N79`:
   ```powershell
   Rename-Computer -NewName "WIN-UPU3JKF7N79" -Restart
   ```

### 9.4 Installing AD DS and Promoting to DC

1. In **Server Manager → Add Roles and Features**, install:
   - Active Directory Domain Services
   - DNS Server
   - File Server
   - Group Policy Management

2. After the roles install, click **Promote this server to a domain controller**.

3. Select **Add a new forest** and set the root domain name:
   ```
   Root domain name: stemlab.lan
   ```

4. On the **Domain Controller Options** page:
   - Forest functional level: Windows Server 2025
   - Domain functional level: Windows Server 2025
   - Check **DNS Server** and **Global Catalog**
   - Set the DSRM (Directory Services Restore Mode) password

5. Accept defaults for DNS delegation and NetBIOS name (`STEMLAB`).

6. Complete the wizard and allow the server to restart.

### 9.5 Verifying AD DS and DNS

After reboot, log in as `STEMLAB\Administrator`:

```powershell
# Verify domain
Get-ADDomain

# Verify DNS zones
Get-DnsServerZone

# Verify FSMO roles
netdom query fsmo
```

All five FSMO roles should be held by WIN-UPU3JKF7N79.

### 9.6 Creating Student Accounts

Student accounts follow the pattern `[first initial][3-char surname][4-digit number]` (e.g., `arin3449`, `jdav8803`).

To create accounts in bulk from a CSV, use PowerShell:

```powershell
Import-Csv "students.csv" | ForEach-Object {
    $username = $_.Username
    $fullname = $_.FullName
    $password = ConvertTo-SecureString "InitialPassword123!" -AsPlainText -Force
    New-ADUser -Name $fullname `
               -SamAccountName $username `
               -UserPrincipalName "$username@stemlab.lan" `
               -AccountPassword $password `
               -Enabled $true `
               -ChangePasswordAtLogon $true
}
```

The lab currently has ~500+ accounts. Verify count:
```powershell
(Get-ADUser -Filter *).Count
```

### 9.7 Configuring Group Policy

The following GPOs are active (linked at the domain level unless noted):

| GPO | Linked To | Purpose |
|-----|-----------|---------|
| Default Domain Policy | stemlab.lan | Password policy, account lockout |
| Default Domain Controllers Policy | OU=Domain Controllers | DC security settings |
| Student Home Drive | stemlab.lan | Maps H: drive to `\\SILLYNAS\student_homes` |
| Network File Sharing | stemlab.lan | Enables firewall rules for SMB |

**Creating the Student Home Drive GPO:**

1. Open **Group Policy Management Console**.
2. Right-click `stemlab.lan` → **Create a GPO and Link it here**.
3. Name it `Student Home Drive`.
4. Edit the GPO:
   - Navigate to **User Configuration → Windows Settings → Folder Redirection** (or **Drive Maps**)
   - For Drive Maps: **User Configuration → Preferences → Windows Settings → Drive Maps → New → Map Drive**
   - Drive letter: `H:`
   - Path: `\\SILLYNAS\student_homes\%USERNAME%`
   - Action: Create

5. Create and link `Network File Sharing` GPO:
   - **Computer Configuration → Windows Settings → Security Settings → Windows Firewall → Inbound Rules**
   - Enable the built-in `File and Printer Sharing` rules

### 9.8 DNS Configuration

The DC automatically creates the `stemlab.lan` forward lookup zone. Key static records to add manually:

```powershell
Add-DnsServerResourceRecordA -ZoneName "stemlab.lan" -Name "freeradius" -IPv4Address "172.16.20.100"
Add-DnsServerResourceRecordA -ZoneName "stemlab.lan" -Name "SILLYNAS" -IPv4Address "172.16.20.25"
Add-DnsServerResourceRecordA -ZoneName "stemlab.lan" -Name "SILLYNAS" -IPv4Address "172.16.67.4"
```

Verify DNS resolution from a VLAN 20 client:
```
nslookup stemlab.lan 172.16.20.20
nslookup freeradius.stemlab.lan 172.16.20.20
```

### 9.9 Installing Additional Tools

```powershell
# Install RSAT tools (for remote AD management)
Add-WindowsFeature RSAT-AD-Tools, RSAT-DNS-Server, GPMC

# Install Windows Admin Center
# Download from https://aka.ms/windows-admin-center and run the MSI
```

---

## 10. FreeRADIUS Setup — VM107

**Proxmox VMID:** 107
**Hostname:** freeradius.stemlab.lan
**IP:** 172.16.20.100 (static)
**VLAN:** 20 (Classroom)
**OS:** Ubuntu Server 24.04

Full FreeRADIUS MAC whitelist setup is in [`docs/guides/aruba-radius-whitelist.md`](guides/aruba-radius-whitelist.md).

### 10.1 Creating the VM in Proxmox

1. Create VM 107 in Proxmox:

   | Setting | Value |
   |---------|-------|
   | VM ID | 107 |
   | Name | FreeRADIUS-CA-Ubuntu-Server |
   | ISO | Ubuntu Server 24.04 LTS |
   | CPU | 4 vCPU (2 sockets × 2 cores) |
   | RAM | 8 GB |
   | Disk | 32 GB on local-zfs |
   | Network | vmbr1, VLAN Tag 20 |
   | onboot | yes |

2. Install Ubuntu Server 24.04. During install:
   - Set a static IP: `172.16.20.100/24`, gateway `172.16.20.1`, DNS `172.16.20.20`
   - Enable SSH server
   - Create a local user for administration

### 10.2 Installing FreeRADIUS

SSH to the VM:

```bash
ssh <admin>@172.16.20.100
```

Install FreeRADIUS:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install freeradius freeradius-utils -y
```

### 10.3 Configuring MAC Authentication (Whitelist)

FreeRADIUS authenticates Aruba AP clients by MAC address. MACs are listed in the `users` file without colons.

1. Edit the users file:
   ```bash
   sudo nano /etc/freeradius/3.0/users
   ```

2. Add entries in this format (no colons in MAC, same value for username and password):
   ```
   AABBCCDDEEFF   Cleartext-Password := "AABBCCDDEEFF"
   ```

3. Add the Aruba Virtual Controller as a RADIUS client:
   ```bash
   sudo nano /etc/freeradius/3.0/clients.conf
   ```

   ```
   client ArubaVC {
     ipaddr = 172.16.67.6
     secret = myradiussecret
     require_message_authenticator = no
   }
   ```

   Replace `172.16.67.6` with the actual Aruba VC IP and set a strong shared secret.

### 10.4 Testing and Enabling

Test in debug mode (FreeRADIUS must not already be running):

```bash
sudo freeradius -X
```

Connect a whitelisted device to the SSID and confirm `Access-Accept` appears in the debug output.

Stop debug mode and enable the service:

```bash
sudo pkill -9 freeradius
sudo systemctl enable freeradius
sudo systemctl start freeradius
```

### 10.5 Adding MACs Going Forward

To add a new device MAC without restarting FreeRADIUS:

1. Add the entry to `/etc/freeradius/3.0/users` (format: `AABBCCDDEEFF   Cleartext-Password := "AABBCCDDEEFF"`)
2. Reload without restart:
   ```bash
   sudo systemctl kill -s HUP freeradius
   ```

---

## 11. Wireless AP Setup

**Hardware:** Aruba APIN0205
**Firmware:** ArubaInstant_Taurus_6.5.4.15_73677

Full OS upgrade and IAP configuration guide is in [`docs/guides/aruba-ap-setup.md`](guides/aruba-ap-setup.md).
TFTP server setup (required for firmware flashing) is in [`docs/guides/aruba-tftp-server.md`](guides/aruba-tftp-server.md).

### 11.1 TFTP Server Setup

Before flashing APs, set up a TFTP server on an Ubuntu machine. See [`docs/guides/aruba-tftp-server.md`](guides/aruba-tftp-server.md) for the full walkthrough. Quick summary:

```bash
sudo apt install tftpd-hpa
sudo mkdir -p /tftp
sudo chown -R nobody:nogroup /tftp
sudo mv ~/Downloads/ArubaInstant_Taurus_6.5.4.15_73677 /tftp
sudo chmod 666 /tftp/ArubaInstant_Taurus_6.5.4.15_73677
```

Edit `/etc/default/tftpd-hpa`:
```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
```

```bash
sudo systemctl restart tftpd-hpa
sudo ufw allow 69
```

Set the TFTP server's IP to `192.168.1.10` (static) on its interface.

### 11.2 Flashing Aruba AP Firmware

Perform this procedure for each AP individually. See [`docs/guides/aruba-ap-setup.md`](guides/aruba-ap-setup.md) for full detail.

1. Connect a USB-to-serial console cable to the AP.
2. Connect to the AP console at 9600 baud:
   ```bash
   sudo apt install screen
   sudo screen /dev/ttyUSB0 9600
   ```
3. Power cycle the AP. Interrupt autoboot by pressing **Enter** when prompted. You should reach the `apboot>` prompt.
4. Set network parameters in apboot:
   ```
   setenv ipaddr 192.168.1.20
   setenv netmask 255.255.255.0
   setenv serverip 192.168.1.10
   ```
5. Flash both OS partitions:
   ```
   upgrade os 0 ArubaInstant_Taurus_6.5.4.15_73677
   upgrade os 1 ArubaInstant_Taurus_6.5.4.15_73677
   ```
   Wait for each flash to complete (several minutes per partition).
6. Set the country code, write inventory, and factory reset:
   ```
   proginv system ccode CCODE-RW-de6fdb363ff04c13ee261ec04fbb01bdd482d1cd
   invent -w
   factory_reset
   ```
7. Save and boot:
   ```
   saveenv
   boot
   ```

### 11.3 Initial AP Configuration

After the AP boots:

1. Log in via console or SSH with default credentials: `admin` / `admin`.
2. Designate one AP as the master (Virtual Controller):
   ```
   iap-master
   ```
3. Connect the master AP to the network (DHCP from Management VLAN 67 via PoE trunk port). It will broadcast `SetMeUp-xx:xx:xx`.
4. Connect a workstation to the SetMeUp SSID and navigate to `http://instant.arubanetworks.com` or `https://X.X.X.149`.
5. Default login: `admin` / `admin`. Change the password immediately under **System → Admin**.

### 11.4 SSID Configuration

Configure three SSIDs through the Aruba Instant web UI:

**stemlab (WPA2-Enterprise, RADIUS auth, VLAN 10 or 20):**
1. **New SSID** → Name: `stemlab`
2. Security: WPA2-Enterprise
3. Authentication server: add `freeradius.stemlab.lan` (IP: 172.16.20.100), port 1812, shared secret matching `clients.conf`
4. Enable MAC authentication
5. VLAN: as appropriate (VLAN 10 for lab devices, VLAN 20 for student devices)

**stemlab-guest (WPA2-PSK, VLAN 30):**
1. **New SSID** → Name: `stemlab-guest`
2. Security: WPA2-PSK, set a guest passphrase
3. VLAN: 30

**stemlab-iot (WPA2-PSK, VLAN 10):**
1. **New SSID** → Name: `stemlab-iot`
2. Security: WPA2-PSK, set a passphrase
3. VLAN: 10

### 11.5 Adding Remaining APs

After the master is configured, connect the remaining APs to trunk ports on SillySwitch. They will discover the Virtual Controller and join the cluster automatically. Verify in the Aruba UI under **Access Points**.

---

## 12. stemlab-drinks Service

**Host:** dolus (Ubuntu 24.04 LXC on SillyProxmox)
**Internal IP:** 172.16.10.58 (VLAN 10)
**Public URL:** https://drinks.velocit.ee (Cloudflare Tunnel)
**User:** `ferry`

Full service documentation is in [`docs/stemlab-drinks.md`](stemlab-drinks.md).

### 12.1 Creating the dolus LXC Container

1. In Proxmox, create a new LXC container:
   - **CT ID:** (assign an available ID)
   - **Hostname:** dolus
   - **Template:** ubuntu-24.04-standard
   - **Storage:** local-zfs, 20+ GB
   - **CPU:** 2 cores
   - **Memory:** 1 GB (1024 MB)
   - **Network:** vmbr1, VLAN Tag 10, static IP 172.16.10.58/24, gateway 172.16.10.1
   - **Unprivileged:** yes
   - **onboot:** yes

2. Start the container:
   ```bash
   pct start <CTID>
   ```

3. Enter the container and update:
   ```bash
   pct exec <CTID> -- bash
   apt update && apt upgrade -y
   ```

4. Create the `ferry` user:
   ```bash
   adduser ferry
   usermod -aG sudo ferry
   ```

### 12.2 Installing Docker

SSH to dolus as ferry (`ssh ferry@172.16.10.58`) and install Docker:

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ferry
```

Log out and back in for the group membership to take effect.

### 12.3 Deploying stemlab-drinks

```bash
cd /home/ferry
git clone https://github.com/Wiesbaden-Cyber/stemlab-drinks.git
cd stemlab-drinks
```

Create the `.env` file from the example:

```bash
cp .env.example .env
nano .env
```

Set all required values:

```
POSTGRES_DB=stemlab
POSTGRES_USER=stemlab
POSTGRES_PASSWORD=<choose a strong password>
ADMIN_PIN=<choose a strong PIN — not the default>
ORDER_RETENTION_HOURS=24
```

Secure the file:

```bash
chmod 600 .env
```

Start the stack:

```bash
docker compose up -d
```

Verify both containers are running:

```bash
docker ps
```

You should see `stemlab-drinks-backend-1` and `stemlab-drinks-db-1` both up.

Test the service internally:

```bash
curl http://localhost:3000/api/menu
```

> Note: Port 3000 is bound to `127.0.0.1` only in `compose.yml`. Direct LAN access to 172.16.10.58:3000 is intentionally blocked. All access is via Cloudflare Tunnel.

### 12.4 Setting Up Cloudflare Tunnel

**Prerequisites:** The domain `velocit.ee` must already be purchased and added to Cloudflare. Its nameservers must point to Cloudflare.

1. Install `cloudflared` on dolus:
   ```bash
   curl -L https://pkg.cloudflare.com/cloudflare-main.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
   echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
   sudo apt update && sudo apt install cloudflared
   ```

2. Authenticate (opens a browser link — copy the URL to a browser on your workstation):
   ```bash
   cloudflared tunnel login
   ```
   This saves a certificate to `~/.cloudflared/cert.pem`.

3. Create the tunnel:
   ```bash
   cloudflared tunnel create stemlab-drinks
   ```
   Note the tunnel UUID in the output.

4. Create the config file `~/.cloudflared/config.yml`:
   ```yaml
   tunnel: <your-tunnel-UUID>
   credentials-file: /home/ferry/.cloudflared/<tunnel-UUID>.json

   ingress:
     - hostname: drinks.velocit.ee
       service: http://localhost:3000
     - service: http_status:404
   ```

5. Create the DNS record in Cloudflare (this creates a CNAME pointing to the tunnel):
   ```bash
   cloudflared tunnel route dns stemlab-drinks drinks.velocit.ee
   ```

6. Test the tunnel manually:
   ```bash
   cloudflared tunnel run stemlab-drinks
   ```
   Visit `https://drinks.velocit.ee` to confirm it loads.

7. Set up the tunnel as a systemd user service for auto-start:
   ```bash
   cloudflared service install
   systemctl --user enable cloudflared
   systemctl --user start cloudflared
   ```

8. Harden permissions on the Cloudflare credentials:
   ```bash
   chmod 600 ~/.cloudflared/cert.pem
   chmod 600 ~/.cloudflared/config.yml
   chmod 600 ~/.cloudflared/*.json
   ```

### 12.5 Hardening the dolus Container

Apply these hardening steps (see [`docs/security.md`](security.md) for the full log):

```bash
# Secure project files
chmod o-rwx /home/ferry/stemlab-drinks/backend/
chmod o-rwx /home/ferry/stemlab-drinks/db/
chmod o-rwx /home/ferry/stemlab-drinks/compose.yml

# Disable SSH X11 forwarding
echo "X11Forwarding no" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Ensure `ferry` is NOT in the `lxd` group (LXD group provides a local privilege escalation path):

```bash
sudo deluser ferry lxd 2>/dev/null || true
```

---

## 13. Joining Clients to the Domain

Full step-by-step instructions are in [`docs/guides/domain-join.md`](guides/domain-join.md).

**Prerequisites:**
- Windows 11 Pro (Home edition cannot join a domain)
- Client must be on VLAN 20, or have routed connectivity to `172.16.20.20`
- DNS must be resolving via `172.16.20.20` (set automatically via DHCP on VLAN 20)

**Quick steps:**

1. Open **Settings → System → About**.
2. Click **Domain or workgroup** → **Change**.
3. Select **Domain** and enter `stemlab.lan`.
4. When prompted for credentials:
   - Username: `Administrator`
   - Password: *(domain administrator password)*
5. Click **OK**. After a "Welcome to the stemlab.lan domain" message, restart the computer.
6. Log in with a domain account: `STEMLAB\<username>` or `<username>@stemlab.lan`.

**Verify home drive mapping:**

After login, the H: drive should auto-mount pointing to `\\SILLYNAS\student_homes\<username>`. If it does not, run `gpupdate /force` and re-log.

---

## 14. Verification Checklist

Use this end-to-end checklist after a full rebuild to confirm every layer is functional.

### Network Layer

- [ ] SillyRouter WAN interface has a DHCP address from Starlink
- [ ] Clients on VLAN 10 receive 172.16.10.x addresses via DHCP
- [ ] Clients on VLAN 20 receive 172.16.20.x addresses via DHCP, with DNS 172.16.20.20
- [ ] Clients on VLAN 30 receive 172.16.30.x addresses via DHCP
- [ ] Ping from VLAN 10 client to 8.8.8.8 succeeds (internet via NAT)
- [ ] Ping from VLAN 20 client to 8.8.8.8 succeeds
- [ ] SSH to SillyRouter (172.16.67.1) from management VLAN works
- [ ] SSH to SillySwitch (172.16.67.2) from management VLAN works
- [ ] SSH to SillyEdgeSwitch (172.16.67.5) from management VLAN works
- [ ] All four VLANs (10, 20, 30, 67) appear active on SillySwitch

### Proxmox

- [ ] Proxmox web UI accessible at `https://172.16.67.3:8006`
- [ ] Both bridges (vmbr0, vmbr1) show up in the UI
- [ ] ZFS pool `rpool` shows ONLINE in `zpool status`
- [ ] CT100 (Tailscale) running and appearing in Tailscale dashboard
- [ ] Tailscale subnet route `172.16.67.0/28` active and accessible remotely

### TrueNAS

- [ ] TrueNAS UI accessible at `http://172.16.67.4`
- [ ] Pool STUDENT_STORAGE shows ONLINE
- [ ] Pool CYBER_LAB shows ONLINE
- [ ] SMB shares `student_homes` and `shared` visible in the UI
- [ ] SMB transport encryption set to Required
- [ ] NFS share `/mnt/CYBER_LAB/APT_CACHE` accessible from VLAN 10

### Windows Domain

- [ ] DC (WIN-UPU3JKF7N79) reachable at 172.16.20.20
- [ ] `nslookup stemlab.lan 172.16.20.20` resolves correctly
- [ ] `nslookup freeradius.stemlab.lan 172.16.20.20` returns 172.16.20.100
- [ ] Domain `stemlab.lan` visible in AD Users and Computers
- [ ] Student accounts exist (`Get-ADUser -Filter * | Measure-Object` returns ~500+)
- [ ] GPOs `Student Home Drive` and `Network File Sharing` linked at domain level
- [ ] A test Windows 11 Pro client can join the domain successfully
- [ ] H: drive maps automatically on login for a student account

### FreeRADIUS

- [ ] FreeRADIUS service running: `systemctl status freeradius`
- [ ] A device with a whitelisted MAC can authenticate to the `stemlab` SSID
- [ ] `radtest` command returns `Access-Accept` for a whitelisted MAC

### Wireless

- [ ] All APs visible in the Aruba Instant Virtual Controller UI
- [ ] SSIDs `stemlab`, `stemlab-guest`, and `stemlab-iot` broadcasting
- [ ] A device connecting to `stemlab-guest` receives a 172.16.30.x address
- [ ] A whitelisted device can connect to `stemlab` via MAC auth

### stemlab-drinks

- [ ] `docker ps` on dolus shows both containers running
- [ ] `curl http://localhost:3000/api/menu` returns menu JSON
- [ ] `https://drinks.velocit.ee` loads the customer order page from outside the network
- [ ] Staff PIN authentication works on the `/staff.html` page
- [ ] Order placement creates a record in the database
- [ ] cloudflared systemd user service is enabled and active

---

## 15. Troubleshooting

### Router not NATing / no internet on VLANs

1. Verify `GigabitEthernet0/0/0` is up and has a DHCP address:
   ```
   SillyRouter# show ip interface brief
   ```
2. Verify the NAT ACL includes all VLANs:
   ```
   SillyRouter# show ip access-lists LAN-NETS
   ```
3. Verify NAT translations are being created:
   ```
   SillyRouter# show ip nat translations
   ```
4. Check that all VLAN SVIs are `up/up`.

### DHCP not handing out addresses

1. Check excluded addresses — the range you expect may be excluded:
   ```
   SillyRouter# show ip dhcp pool
   SillyRouter# show ip dhcp conflict
   ```
2. Verify the client is on the correct VLAN: check which switch port it's connected to and what VLAN that port is in.
3. Clear DHCP conflicts: `clear ip dhcp conflict *`

### Cannot SSH to management devices

1. Verify your source IP is in the `MGMT-ONLY` ACL (172.16.67.0/28 or Tailscale IP 100.83.36.66).
2. The router and switches use SSH version 2 only — verify your SSH client is not trying SSHv1.
3. If the router is showing `Login failure`: wait 60 seconds (login block-for 60 is active after 3 failures in 30 seconds).

### VM can't reach its VLAN gateway

1. Verify the VM's VLAN tag matches the bridge config:
   - In Proxmox UI: **VM → Hardware → Network Device** — confirm the VLAN tag.
   - vmbr1 must be the bridge (VLAN-aware trunk).
2. Verify the VLAN is trunked all the way to SillyRouter.

### Windows domain join fails

1. Confirm the client is on VLAN 20 (or has routed access to 172.16.20.20).
2. Confirm DNS resolves `stemlab.lan`: `nslookup stemlab.lan 172.16.20.20`
3. Confirm time sync — Kerberos requires client time to be within 5 minutes of DC time. Set NTP on the client if needed.
4. Check DC event logs under **Applications and Services Logs → Microsoft → Windows → Kerberos-Key-Distribution-Center**.

### Home drive not mapping after domain join

1. Run `gpupdate /force` as the student user and log off/on.
2. Check that SILLYNAS is reachable: `ping 172.16.20.25`
3. Check that the SMB share `student_homes` is online in TrueNAS UI.
4. If SMB transport encryption is set to Required on TrueNAS, ensure the Windows client supports SMB3 (Windows 10/11 does by default).

### FreeRADIUS returning Access-Reject for a known good MAC

1. Verify the MAC is in `/etc/freeradius/3.0/users` without colons, in uppercase.
2. After editing the users file, reload: `sudo systemctl kill -s HUP freeradius`
3. Test in debug mode: `sudo freeradius -X` and watch for the `Access-Accept` or `Access-Reject` message with the reason.
4. Confirm the Aruba VC IP in `clients.conf` matches the actual VC IP and the shared secret matches what's configured in the Aruba UI.

### stemlab-drinks containers not starting

1. Check logs:
   ```bash
   docker logs stemlab-drinks-backend-1
   docker logs stemlab-drinks-db-1
   ```
2. Verify `.env` exists and has all required variables:
   ```bash
   cat /home/ferry/stemlab-drinks/.env
   ```
3. Rebuild the stack:
   ```bash
   cd /home/ferry/stemlab-drinks
   docker compose down && docker compose up -d --build
   ```

### drinks.velocit.ee not loading / Cloudflare Tunnel down

1. Check the cloudflared service status:
   ```bash
   systemctl --user status cloudflared
   ```
2. Check tunnel logs:
   ```bash
   journalctl --user -u cloudflared -n 50
   ```
3. Verify the backend is running locally:
   ```bash
   curl http://localhost:3000/api/menu
   ```
4. If the tunnel credentials expired, re-authenticate:
   ```bash
   cloudflared tunnel login
   cloudflared tunnel run stemlab-drinks
   ```

### AP not broadcasting SSIDs after reboot

1. Verify the AP is getting PoE power (check `show power inline` on SillySwitch).
2. Verify the AP's switch port is a trunk with VLANs 10, 20, 30, 67 allowed and native VLAN 67.
3. APs that are not the master need to discover the Virtual Controller via DHCP. Ensure the master AP is up first.
4. If an AP shows `SetMeUp-xx:xx:xx` instead of the production SSIDs, it has lost its cluster config — connect to it and re-adopt it into the VC.

### Tailscale subnet route not accessible remotely

1. Verify CT100 (Tailscale container) is running: `pct status 100`
2. In the Tailscale admin dashboard, confirm the subnet route `172.16.67.0/28` is approved.
3. On the Tailscale node: `tailscale status` — confirm it shows `online`.
4. If the TUN device is missing (common in LXC): verify the `lxc.mount.entry` and `lxc.cgroup2.devices.allow` lines are in `/etc/pve/lxc/100.conf`.

---

*For questions or corrections, open an issue or pull request in the [Wiesbaden-Cyber/Stemlab-25-26](https://github.com/Wiesbaden-Cyber) repository.*
