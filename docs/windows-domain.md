# Windows Domain & Server Documentation

**Domain:** `silly.lab.local`
**DNS for VLAN 20:** `172.16.20.20`

---

## Virtual Machines

### VM105 — WindowsServer1776 (Primary DC)
| Field | Value |
|-------|-------|
| Proxmox VMID | 105 |
| Status | Running |
| IP | 172.16.20.20 (static) |
| VLAN | 20 (Classroom) |
| vCPU | 9 (3 sockets × 3 cores) |
| RAM | 8 GB |
| Disk | 70 GB (ZFS) |
| BIOS | UEFI + TPM 2.0 |
| Network | vmbr1 (tag=20) |
| Roles | Active Directory DS, DNS Server |
| Notes | Primary DC. DNS server for VLAN 20 (`172.16.20.20`). SMB signing required. |

### VM106 — ADDC (Secondary DC)
| Field | Value |
|-------|-------|
| Proxmox VMID | 106 |
| Status | Stopped |
| VLAN | 20 (Classroom) |
| vCPU | 4 (2 sockets × 2 cores) |
| RAM | 4 GB |
| Disk | 32 GB (ZFS) |
| BIOS | UEFI + TPM 2.0 |
| OS | Windows Server 2025 |
| Notes | Secondary / standby DC. Currently not running. |

---

## Domain Details

> ⚠️ **This section needs to be completed** once RDP/WinRM access is available.
> Known so far from network enumeration (port 88/Kerberos, 389/LDAP, 636/LDAPs, 445/SMB):

| Field | Value |
|-------|-------|
| Domain name | `silly.lab.local` |
| Primary DC IP | `172.16.20.20` |
| DNS server (VLAN 20) | `172.16.20.20` |
| SMB signing | Required on DC, not required on other hosts |

**To complete:**
- Forest / domain functional level
- OU structure
- User accounts and groups
- Group Policy Objects (GPOs)
- DNS zones and records
- Any additional installed roles/features

---

## Joining a Computer to the Domain

> See [`docs/guides/domain-join.md`](guides/domain-join.md) for the full step-by-step guide.

**Quick reference:**
1. Windows 11 Pro required (Home cannot join a domain)
2. Must be on VLAN 20 or have connectivity to `172.16.20.20`
3. Settings → System → About → Domain or workgroup → Change
4. Enter domain: `silly.lab.local`
5. Credentials: `Administrator` / *(domain admin password)*
6. Restart

---

## FreeRADIUS Integration (VM107)

VM107 runs FreeRADIUS and a CA server on VLAN 20 alongside the domain. It handles:
- **MAC-based WiFi authentication** for Aruba SSIDs (whitelist via `/etc/freeradius/3.0/users`)
- **Certificate Authority** for issuing certs to network devices

The Aruba Virtual Controller is configured as a RADIUS client pointing to VM107's IP. See [`docs/guides/aruba-radius-whitelist.md`](guides/aruba-radius-whitelist.md) for setup details.

---

## 172.16.20.100 — Unknown Windows Host

A Windows machine with SMB open was found at `172.16.20.100` (static, excluded from DHCP). SMB signing is not required (not a DC). Identity TBD.
