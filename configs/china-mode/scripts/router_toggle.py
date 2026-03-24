#!/usr/bin/env python3
"""
router_toggle.py — Automate SillyRouter config for China Mode
Runs on SillyProxmox (172.16.67.3) which is in the MGMT VLAN and
is allowed to SSH to the router per the MGMT-ONLY ACL.

Credentials are never stored. Read from environment variables:
  ROUTER_HOST    - router IP (default: 172.16.67.1)
  ROUTER_USER    - SSH username
  ROUTER_PASS    - SSH password
  ROUTER_ENABLE  - enable secret

Usage:
  python3 router_toggle.py on
  python3 router_toggle.py off
"""

import sys
import os
import getpass

try:
    from netmiko import ConnectHandler
    from netmiko.exceptions import NetmikoTimeoutException, NetmikoAuthenticationException
except ImportError:
    print("ERROR: netmiko not installed. Run: pip3 install netmiko --break-system-packages")
    sys.exit(1)

ROUTER_HOST   = os.environ.get("ROUTER_HOST", "172.16.67.1")
PIHOLE_IP     = "172.16.20.21"
ORIGINAL_DNS  = "172.16.20.20 8.8.8.8 1.1.1.1"

COMMANDS_ON = [
    "ip dhcp pool CLASSROOM",
    " no dns-server",
    f" dns-server {PIHOLE_IP}",
    "exit",
    "ip access-list extended CHINA-MODE-DNS-LOCK",
    f" 10 permit udp any host {PIHOLE_IP} eq 53",
    f" 20 permit tcp any host {PIHOLE_IP} eq 53",
    " 30 deny   udp any any eq 53 log",
    " 40 deny   tcp any any eq 53 log",
    " 50 permit ip any any",
    "exit",
    "interface Vlan20",
    " ip access-group CHINA-MODE-DNS-LOCK in",
    "exit",
]

COMMANDS_OFF = [
    "ip dhcp pool CLASSROOM",
    " no dns-server",
    f" dns-server {ORIGINAL_DNS}",
    "exit",
    "interface Vlan20",
    " no ip access-group CHINA-MODE-DNS-LOCK in",
    "exit",
]


def prompt_cred(env_var: str, prompt_text: str, secret: bool = False) -> str:
    val = os.environ.get(env_var)
    if val:
        return val
    if secret:
        return getpass.getpass(f"  {prompt_text}: ")
    return input(f"  {prompt_text}: ")


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("on", "off"):
        print(f"Usage: {sys.argv[0]} on|off")
        sys.exit(1)

    mode = sys.argv[1]

    print(f"\n[router_toggle] Connecting to SillyRouter at {ROUTER_HOST}...")
    print("  Credentials (set ROUTER_USER/ROUTER_PASS/ROUTER_ENABLE env vars to skip prompts)")

    username = prompt_cred("ROUTER_USER", "Router SSH username")
    password = prompt_cred("ROUTER_PASS", "Router SSH password", secret=True)
    enable   = prompt_cred("ROUTER_ENABLE", "Router enable secret", secret=True)

    device = {
        "device_type": "cisco_ios",
        "host": ROUTER_HOST,
        "username": username,
        "password": password,
        "secret": enable,
        "timeout": 15,
        "session_log": None,
    }

    commands = COMMANDS_ON if mode == "on" else COMMANDS_OFF

    try:
        with ConnectHandler(**device) as conn:
            conn.enable()
            print(f"  Connected. Applying China Mode {mode.upper()} config...")
            output = conn.send_config_set(commands)

            # Clear DHCP bindings to force client renewal
            print("  Clearing DHCP bindings...")
            conn.send_command("clear ip dhcp binding *", expect_string=r"#")

            # Save config
            print("  Saving config (wr mem)...")
            conn.save_config()

            print(f"\n[router_toggle] Done. China Mode is {mode.upper()} on VLAN 20.")

            if mode == "on":
                print(f"  DHCP DNS for VLAN 20: {PIHOLE_IP} (Pi-hole)")
                print("  ACL CHINA-MODE-DNS-LOCK applied to Vlan20 inbound")
            else:
                print(f"  DHCP DNS for VLAN 20 restored: {ORIGINAL_DNS}")
                print("  ACL CHINA-MODE-DNS-LOCK removed from Vlan20")

    except NetmikoAuthenticationException:
        print("\nERROR: Authentication failed. Check ROUTER_USER/ROUTER_PASS/ROUTER_ENABLE.")
        sys.exit(1)
    except NetmikoTimeoutException:
        print(f"\nERROR: Connection timed out. Is {ROUTER_HOST} reachable from this host?")
        sys.exit(1)
    except Exception as e:
        print(f"\nERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
