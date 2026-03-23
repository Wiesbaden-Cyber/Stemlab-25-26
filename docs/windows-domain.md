# Windows Domain & Server Documentation

**Domain:** `stemlab.lan`
**NetBIOS:** `STEMLAB`
**DNS for VLAN 20:** `172.16.20.20`

> **Note:** Earlier documentation incorrectly referenced the domain as `silly.lab.local`. The actual domain name is `stemlab.lan`.

---

## Virtual Machines

### VM105 — WindowsServer1776 (Primary DC)
| Field | Value |
|-------|-------|
| Proxmox VMID | 105 |
| Hostname | WIN-UPU3JKF7N79 |
| Status | Running |
| IP | 172.16.20.20 (static) |
| VLAN | 20 (Classroom) |
| vCPU | 9 (3 sockets × 3 cores) |
| RAM | 8 GB |
| Disk | 70 GB (ZFS) |
| BIOS | UEFI + TPM 2.0 |
| Network | vmbr1 (tag=20) |
| OS | Windows Server 2025 Standard Evaluation (Build 26100) |
| Installed | 2025-11-18 |
| Roles | Active Directory DS, DNS Server, File Server |

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

| Field | Value |
|-------|-------|
| Domain name | `stemlab.lan` |
| NetBIOS name | `STEMLAB` |
| Distinguished Name | `DC=stemlab,DC=lan` |
| Domain Functional Level | Windows 2025 |
| Forest Functional Level | Windows 2025 |
| PDC Emulator | WIN-UPU3JKF7N79.stemlab.lan |
| RID Master | WIN-UPU3JKF7N79.stemlab.lan |
| Infrastructure Master | WIN-UPU3JKF7N79.stemlab.lan |
| Primary DC IP | `172.16.20.20` |
| DNS server (VLAN 20) | `172.16.20.20` |
| SMB signing | Required on DC, not required on other hosts |

All five FSMO roles are held by the single running DC (WIN-UPU3JKF7N79).

---

## OU Structure

The domain uses a flat structure — no custom OUs have been created. All user accounts reside in the default `CN=Users` container.

| OU | Notes |
|----|-------|
| `OU=Domain Controllers,DC=stemlab,DC=lan` | Default DC OU |

---

## User Accounts

~500+ student accounts are provisioned. All student accounts follow the naming pattern `[first initial][3-char surname][4-digit number]` (e.g., `arin3449`, `jdav8803`).

| Account | Type | Status |
|---------|------|--------|
| Administrator | Domain admin | Enabled |
| Guest | Built-in | Disabled |
| krbtgt | Built-in (Kerberos) | Disabled |
| teststudent | Test account | Enabled |
| `a[name][####]` through `z[name][####]` | Student accounts | Enabled |

---

## Groups

Only default built-in AD groups exist — no custom groups have been created.

Notable groups:
- `Domain Admins` — Global Security
- `Domain Users` — Global Security (all user accounts)
- `Domain Computers` — Global Security
- `Remote Desktop Users` — DomainLocal Security
- `Remote Management Users` — DomainLocal Security
- `DnsAdmins` — DomainLocal Security

---

## Group Policy Objects

| GPO | Linked To | Status | Created |
|-----|-----------|--------|---------|
| Default Domain Policy | stemlab.lan | Enabled | 2026-02-12 |
| Default Domain Controllers Policy | OU=Domain Controllers | Enabled | 2026-02-12 |
| Student Home Drive | stemlab.lan | Enabled | 2026-03-12 |
| Network File Sharing | stemlab.lan | Enabled | 2026-03-12 |

**Student Home Drive** — maps a home drive for student accounts (applied to all Authenticated Users domain-wide).

**Network File Sharing** — enables network file sharing firewall rules domain-wide.

---

## DNS Zones

| Zone | Type | AD-Integrated |
|------|------|--------------|
| `stemlab.lan` | Primary | Yes |
| `_msdcs.stemlab.lan` | Primary | Yes |
| `0.in-addr.arpa` | Primary | No |
| `127.in-addr.arpa` | Primary | No |
| `255.in-addr.arpa` | Primary | No |

### Key DNS Records (stemlab.lan)

| Hostname | IP | Notes |
|----------|----|-------|
| win-upu3jkf7n79 | 172.16.20.20 | Primary DC |
| freeradius | 172.16.20.100 | VM107 FreeRADIUS-CA (static) |
| SILLYNAS | 172.16.20.25 | NAS data interface (VLAN 20) |
| SILLYNAS | 172.16.67.4 | NAS management interface (VLAN 67) |
| Z230-422 through Z230-921 | 172.16.20.x | Classroom PCs (DHCP) |
| ROBOTICS-384 through ROBOTICS-627 | 172.16.20.x | Robotics/coding laptops (DHCP) |
| DESKTOP-Z230-463, DESKTOP-Z230-911 | 172.16.10.x | Lab-connected PCs |

---

## Installed Roles & Features

| Role/Feature | Display Name |
|-------------|-------------|
| `AD-Domain-Services` | Active Directory Domain Services |
| `DNS` | DNS Server |
| `FS-FileServer` | File Server |
| `GPMC` | Group Policy Management |
| `RSAT-AD-Tools` | AD DS and AD LDS Tools |
| `RSAT-DNS-Server` | DNS Server Tools |
| `WindowsAdminCenterSetup` | Windows Admin Center Setup |
| `Windows-Defender` | Microsoft Defender Antivirus |
| `NET-Framework-45-Core` | .NET Framework 4.8 |
| `PowerShell` | Windows PowerShell 5.1 |

---

## Joining a Computer to the Domain

> See [`docs/guides/domain-join.md`](guides/domain-join.md) for the full step-by-step guide.

**Quick reference:**
1. Windows 11 Pro required (Home cannot join a domain)
2. Must be on VLAN 20 or have connectivity to `172.16.20.20`
3. Settings → System → About → Domain or workgroup → Change
4. Enter domain: `stemlab.lan`
5. Credentials: `Administrator` / *(domain admin password)*
6. Restart

---

## FreeRADIUS Integration (VM107)

VM107 runs FreeRADIUS and a CA server on VLAN 20. Its IP is `172.16.20.100` (static, DNS hostname: `freeradius.stemlab.lan`). It handles:
- **MAC-based WiFi authentication** for Aruba SSIDs (whitelist via `/etc/freeradius/3.0/users`)
- **Certificate Authority** for issuing certs to network devices

The Aruba Virtual Controller is configured as a RADIUS client pointing to `172.16.20.100`. See [`docs/guides/aruba-radius-whitelist.md`](guides/aruba-radius-whitelist.md) for setup details.
