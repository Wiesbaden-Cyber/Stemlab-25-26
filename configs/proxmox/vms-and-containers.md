# SillyProxmox — VMs & Containers
**Host:** pve | Proxmox VE 9.1.4 | Kernel 6.17.4-2-pve
**Hardware:** 24 cores, 96 GB RAM, ~2.6 TB ZFS (rpool/data)
**Retrieved:** 2026-03-23

---

## Containers (LXC)

| VMID | Name | Status | vCPU | RAM | Disk | Network | Notes |
|------|------|--------|------|-----|------|---------|-------|
| 100 | Tailscale | Running | 1 | 256 MB | 12 GB | vmbr1 (DHCP) | Tailscale relay/exit node. Unprivileged with TUN passthrough. `onboot: 1` |
| 200 | china-mode | Stopped | 2 | 1 GB | 8 GB | vmbr1 tag=20, 172.16.20.50/24 | China Mode GFW stack. Pi-hole (Alibaba DNS), nginx (CN headers), mitmproxy (ad inject). `onboot: 0` — started manually via china-on.sh |

---

## Virtual Machines (QEMU)

| VMID | Name | Status | vCPU | RAM | Disk | VLAN | Notes |
|------|------|--------|------|-----|------|------|-------|
| 101 | OPNsense-Redstone | Running | 4 (2s×2c) | 16 GB | 64 GB | vmbr0 + vmbr2 | OPNsense 25.7 firewall — dev/testing. `onboot: 1` |
| 102 | Worker-1 | Stopped | 16 | 16 GB | 32 GB | vmbr0 | General purpose worker. Ubuntu 24.04. NUMA enabled. |
| 103 | PXE | Stopped | 1 | 4 GB | 40 GB | vmbr1 tag=10 | PXE boot server. Debian 13. VLAN 10 (Lab). |
| 104 | DO-Local-Ubuntu-Server | Running | 4 (2s×2c) | 8 GB | 40 GB | vmbr1 tag=10 | Ubuntu 24.04. VLAN 10 (Lab). `onboot: 1` |
| 105 | WindowsServer1776 | Running | 9 (3s×3c) | 8 GB | 70 GB | vmbr1 tag=20 | Windows Server. UEFI + TPM. VLAN 20 (Classroom). `onboot: 1` |
| 106 | ADDC | Stopped | 4 (2s×2c) | 4 GB | 32 GB | vmbr0 tag=20 | Active Directory DC. Windows Server 2025. UEFI + TPM. |
| 107 | FreeRADIUS-CA-Ubuntu-Server | Running | 4 (2s×2c) | 8 GB | 32 GB | vmbr1 tag=20 | FreeRADIUS + CA server. Ubuntu 24.04. VLAN 20 (Classroom). `onboot: 1` |
| 108 | VM 108 | Running | 4 | 2 GB | 24 GB | vmbr1 tag=10 | Ubuntu 24.04. VLAN 10 (Lab). |
| 109 | CDS-n8n | Running | 1 | 16 GB | 40 GB | vmbr1 tag=10 | n8n workflow automation. Ubuntu 24.04. VLAN 10 (Lab). `onboot: 1` |

---

## Bridge → VLAN Mapping

| Bridge | Physical NIC | Mode | Usage |
|--------|-------------|------|-------|
| vmbr0 | enp8s0f0 | DHCP | Untagged lab access; OPNsense WAN-side |
| vmbr1 | enp8s0f1 | Static 172.16.67.3/28, VLAN-aware | Management + tagged VM traffic (VLANs 10/20/30/67) |
| vmbr2 | none | Isolated, VLAN-aware | OPNsense internal testing (no uplink) |
