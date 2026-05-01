# Trust-Relationship Hardening

Recurring `The trust relationship between this workstation and the primary domain failed` errors on classroom and robotics PCs were the symptom — clock drift on the PDC plus aggressive default machine account password rotation were the causes. This page documents the preventive measures applied 2026-05-01 and how to maintain them.

## Root cause summary

The PDC emulator (`WIN-UPU3JKF7N79`) was configured with `Type=NT5DS` and `AnnounceFlags=10` and had no external NTP source. `w32tm /query /source` returned `Free-running System Clock` and the DC was observed running 18.8 seconds ahead of UTC. All domain members sync from this DC, so the entire domain was drifting together until something (Hyper-V time sync on hosts, manual reboot, etc.) forced a single member to true real time — at which point its Kerberos requests were rejected by the DC for clock skew, surfacing as the trust-relationship error.

Machine account passwords also rotate every 30 days by default. A laptop that sits powered off for >30 days returns with a stale password and breaks the secure channel.

## Mitigations applied

### 1. NTP — make the PDC authoritative against external time

Run on the PDC:

```powershell
w32tm /config /manualpeerlist:"de.pool.ntp.org,0x9 ptbtime1.ptb.de,0x9 ptbtime2.ptb.de,0x9 time.cloudflare.com,0x9" /syncfromflags:manual /reliable:yes /update
Stop-Service w32time
Start-Service w32time
w32tm /resync /rediscover
```

Verify:

```powershell
w32tm /query /source       # expect one of the configured peers, NOT "Free-running System Clock"
w32tm /query /status       # Source: ptbtime2.ptb.de,0x9  (or similar); Stratum: 2
```

Domain members are unchanged (`Type=NT5DS`); they continue to pull from the PDC, which is now itself accurate.

### 2. GPO: Stemlab - Machine Account Hardening

Linked at `DC=stemlab,DC=lan`. Applies one registry setting:

| Hive | Key | Value | Type | Default → New |
|------|-----|-------|------|---------------|
| HKLM | `SYSTEM\CurrentControlSet\Services\Netlogon\Parameters` | `MaximumPasswordAge` | DWORD (days) | 30 → **120** |

Backed via:

```powershell
Set-GPRegistryValue -Name "Stemlab - Machine Account Hardening" `
    -Key "HKLM\System\CurrentControlSet\Services\Netlogon\Parameters" `
    -ValueName "MaximumPasswordAge" -Type DWord -Value 120
```

### 3. GPO: Stemlab - Local Admin Enforcement

Linked at `DC=stemlab,DC=lan`. Computer Configuration → Policies → Windows Settings → Scripts → Startup, pointing at `\\stemlab.lan\NETLOGON\enforce-local-admin.ps1`.

The script is idempotent and:

- Detects domain controllers via `Win32_ComputerSystem.DomainRole` (4 = BDC, 5 = PDC) and exits early — **critical**, because on a DC `Get-LocalUser` / `New-LocalUser` write to AD instead of the SAM and would silently create a domain user account.
- Creates the local `admin` user with `-PasswordNeverExpires -AccountNeverExpires` if missing.
- If present, calls `Set-LocalUser -PasswordNeverExpires $true` and resets the password (so drift is corrected on every reboot).
- Ensures membership in the local Administrators group (resolved via SID `S-1-5-32-544` to be locale-independent).
- Logs to `C:\Windows\Temp\stemlab-local-admin.log`.

The shared password is stored in the script itself in `C:\Windows\SYSVOL\sysvol\stemlab.lan\scripts\` on the PDC. SYSVOL is readable by Authenticated Users — so any domain user could read it. This is an explicitly accepted lab-environment trade-off; treat the password as a break-glass credential, not a secret.

## Rollout & verification

1. Machines pick up the new GPOs on next `gpupdate` cycle (~90 minutes) or `gpupdate /force`.
2. The startup script only runs **at boot**, so unless rebooted, machines won't apply the local-admin change. Schedule a reboot or trigger:

   ```powershell
   gpupdate /force
   # then either:
   shutdown /r /t 0
   # or run the script directly:
   powershell -ExecutionPolicy Bypass -File \\stemlab.lan\NETLOGON\enforce-local-admin.ps1
   ```

3. Per-host verification:

   ```powershell
   Get-LocalUser admin | Format-List Name,Enabled,PasswordExpires,PasswordLastSet
   Get-LocalGroupMember -SID S-1-5-32-544 | Where-Object Name -like '*\admin'
   Get-Content C:\Windows\Temp\stemlab-local-admin.log -Tail 5
   ```

4. NTP propagation check on a member:

   ```powershell
   w32tm /query /source     # expect WIN-UPU3JKF7N79.stemlab.lan
   w32tm /stripchart /computer:WIN-UPU3JKF7N79 /samples:1 /dataonly
   ```

## Recovering a host where trust is already broken

When a workstation already shows the trust-relationship error, the GPO doesn't help (it can't apply because the secure channel is broken). Two options:

**Option A — Reset the secure channel (fastest, no domain rejoin):**

Log in as the local `admin` (the GPO-managed account, once present), open elevated PowerShell:

```powershell
$cred = Get-Credential STEMLAB\Administrator
Reset-ComputerMachinePassword -Server WIN-UPU3JKF7N79.stemlab.lan -Credential $cred
# reboot
```

**Option B — Leave/rejoin domain:**

```powershell
Remove-Computer -UnjoinDomainCredential STEMLAB\Administrator -PassThru -Restart -Force
# after reboot, rejoin via Settings → System → About
```

## Maintenance

| Task | Cadence |
|------|---------|
| Rotate the local `admin` password | When operator changes or on-demand. Edit `enforce-local-admin.ps1` in SYSVOL, reboot members. |
| Audit machines that haven't applied the GPO | Quarterly. `Get-ADComputer -Filter * -Properties LastLogonDate, PasswordLastSet` — anything older than 90 days is a candidate for cleanup. |
| Review `MaximumPasswordAge` setting | Annually. 120 days balances rotation hygiene against lab usage patterns. |
| Verify NTP source on PDC | Anytime trust errors recur. `w32tm /query /source` should never return `Free-running System Clock` again. |

## Implementation history

| Date | Change |
|------|--------|
| 2026-05-01 | NTP authoritative source set; both GPOs created and linked at domain root; startup script deployed to NETLOGON. Live-push of the script via WMI/schtasks blocked by Windows 11 UAC remote token filtering and most lab machines being powered off — relying on next-boot GPO application instead. |
