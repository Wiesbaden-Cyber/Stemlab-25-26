# SillyNAS — TrueNAS Configuration
**Version:** TrueNAS 25.04.2.6
**Retrieved:** 2026-03-23

---

## Network Interfaces

| Interface | IP Address | Subnet | Status | Notes |
|-----------|-----------|--------|--------|-------|
| enp14s0 | 172.16.67.4 | /28 | UP | Management VLAN 67 — primary management NIC |
| enp15s0 | 172.16.20.25 | /24 | UP | Classroom VLAN 20 — data/share access NIC |
| enp16s0 | — | — | DOWN | Unused |
| enp17s0 | — | — | DOWN | Unused |

---

## Storage Pools

| Pool | Status | Type | Mount Point |
|------|--------|------|-------------|
| STUDENT_STORAGE | ONLINE | RAIDZ1 (4 disks: sda, sdb, sdc, sdd) | /mnt/STUDENT_STORAGE |
| CYBER_LAB | ONLINE | Single disk | /mnt/CYBER_LAB |

---

## Shares

### SMB
| Share Name | Path |
|------------|------|
| student_homes | /mnt/STUDENT_STORAGE/homes |
| shared | /mnt/STUDENT_STORAGE/shared |

### NFS
| Path | Notes |
|------|-------|
| /mnt/CYBER_LAB/APT_CACHE | APT package cache — used by lab provisioning/PXE |
