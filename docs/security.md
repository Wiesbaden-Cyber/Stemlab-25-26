# Security Hardening Log

Tracks security changes made to the StemLab environment.

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

- Admin PIN for drinks.velocit.ee: rate-limited to 5 attempts/IP/15 min via Cloudflare. Direct LAN access to port 3000 is now blocked.
- `ferry` is still in the `docker` group (required to manage containers). Docker group = effective root — keep SSH key secured and passphrase-protected.
- PostgreSQL is not exposed on the host — only accessible inside the Docker bridge network.
