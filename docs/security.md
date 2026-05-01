# Security Hardening Log

Tracks security changes made to the StemLab environment.

---

## Applied — 2026-05-01

Preventive maintenance against recurring "trust relationship between this workstation and the primary domain failed" errors on classroom and robotics PCs.

### Windows Server (172.16.20.20) — NTP authoritative time

| Change | Detail |
|--------|--------|
| PDC emulator now external NTP-sourced | Was `Type=NT5DS` with `Source: Free-running System Clock` (DC clock was drifting; observed 18.8 s offset from real time). Reconfigured: `Type=NTP`, `AnnounceFlags=5` (reliable), `manualpeerlist=de.pool.ntp.org,0x9 ptbtime1.ptb.de,0x9 ptbtime2.ptb.de,0x9 time.cloudflare.com,0x9`. Verify with `w32tm /query /source` — should return one of the configured peers, not `Free-running System Clock`. |
| Domain members unchanged | Members stay on `Type=NT5DS` and pull from the now-correct PDC. No member-side change required. Kerberos clock-skew failures should no longer slowly accumulate. |

### Active Directory — Group Policy

| Change | Detail |
|--------|--------|
| GPO **Stemlab - Machine Account Hardening** | New GPO linked at domain root. Sets `HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters\MaximumPasswordAge = 120` (default 30). Increases the window before a machine account password rotation can desync and cause trust failures. |
| GPO **Stemlab - Local Admin Enforcement** | New GPO linked at domain root. Computer Configuration → Startup script: `\\stemlab.lan\NETLOGON\enforce-local-admin.ps1`. Idempotently ensures a local `admin` user exists with a known password, `PasswordNeverExpires=true`, member of the local Administrators group. **Skips Domain Controllers** (`Win32_ComputerSystem.DomainRole` 4/5) — on a DC `Get-LocalUser`/`New-LocalUser` would fall through to AD and create domain objects. |

The `admin` account is intended as a break-glass local administrator on each domain-joined workstation, used only when domain trust is broken. **The shared password is stored in `\\stemlab.lan\NETLOGON\enforce-local-admin.ps1` (readable by Authenticated Users via SYSVOL replication) and in the operator password manager — not in this repository.** Lab/educational environment; risk explicitly accepted. To rotate, edit the script in `C:\Windows\SYSVOL\sysvol\stemlab.lan\scripts\` on the PDC and reboot members (or trigger gpupdate + run the script manually).

See [`docs/guides/trust-relationship-hardening.md`](guides/trust-relationship-hardening.md) for the full procedure, verification steps, and post-rollout checklist.

---

## Applied — 2026-03-23

### dolus (172.16.10.58) — stemlab-drinks server

| Change | Detail |
|--------|--------|
| Port 3000 bound to localhost only | `compose.yml`: `127.0.0.1:3000:3000` — direct LAN access blocked, traffic must go through Cloudflare Tunnel |
| Backend container runs as non-root | `Dockerfile`: files owned by UID 1000, `user: "1000:1000"` in compose.yml |
| `.env` permissions hardened | `chmod 600` — was world-readable, contained ADMIN_PIN |
| Cloudflare cert/config permissions hardened | `chmod 600 ~/.cloudflared/cert.pem` and `config.yml` |
| Project source files locked down | `chmod o-rwx` on backend/, db/, compose.yml |
| SSH X11 Forwarding disabled | Added `X11Forwarding no` to `/etc/ssh/sshd_config` |
| `ferry` removed from `lxd` group | LXD group membership is a trivial local root escalation path |
| CSP `script-src-attr` fixed | Helmet v8 default `'none'` was blocking all `onclick` handlers — set to `'unsafe-inline'` |
| Express `trust proxy` set to 1 | Cloudflare Tunnel injects `X-Forwarded-For`; without `app.set('trust proxy', 1)` express-rate-limit throws `ERR_ERL_UNEXPECTED_X_FORWARDED_FOR` and rejects every auth request — PIN appeared broken for all users |

### Windows Server (172.16.20.20)

| Change | Detail |
|--------|--------|
| WinRM firewall rule scoped | Replaced broad `allow any` rule with `RemoteIP: 172.16.20.0/24, 172.16.67.0/28` only |

### SillyRouter

| Change | Detail |
|--------|--------|
| ACL DOLUS-RESTRICT applied to Vlan10 inbound | Blocks dolus (172.16.10.58) from reaching Proxmox (172.16.67.3) port 8006 only — all other VLAN 10 clients unaffected |

### SillyNAS (172.16.67.4)

| Change | Detail |
|--------|--------|
| SMB Transport Encryption Required | TrueNAS UI → Shares → SMB → Transport Encryption Behavior set to "Required" — enforces SMB3 signing and encryption on all connections |

---

## Pending

| # | Item | Severity | Action Required |
|---|------|----------|-----------------|
| 1 | Change ADMIN_PIN from default | High | Edit `.env` on dolus, restart backend |

### Router ACL for #1 (run on SillyRouter)

```
conf t
ip access-list extended DOLUS-RESTRICT
 deny tcp host 172.16.10.58 host 172.16.67.3 eq 8006
 permit ip any any
!
interface Vlan10
 ip access-group DOLUS-RESTRICT in
end
write memory
```

This blocks only dolus (172.16.10.58) from reaching Proxmox port 8006. All other VLAN 10 clients are unaffected.

---

## Notes

- Admin PIN for drinks.velocit.ee: rate-limited to 5 attempts/IP/15 min (per real client IP via `X-Forwarded-For`). Direct LAN access to port 3000 is now blocked.
- `ferry` is still in the `docker` group (required to manage containers). Docker group = effective root — keep SSH key secured and passphrase-protected.
- PostgreSQL is not exposed on the host — only accessible inside the Docker bridge network.
