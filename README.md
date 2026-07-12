# 👁️ Eye of Zeus

A menu-driven network auditing and penetration-testing framework for Linux
(built and tested on Kali). It wraps common offensive-security tooling —
discovery, MITM, exploitation, and post-exploitation — behind a single themed
terminal interface with an animated UI.

> **Author:** arch_nexus707 · **Theme:** Debian / Hyprland

---

## ⚠️ Legal & Ethical Use — Read First

**This software is for authorized security testing and education only.**

You may use it **only** against systems that you own or for which you have
**explicit, written permission** to test. Unauthorized scanning, interception,
access, or attack of networks and devices is **illegal** in most jurisdictions
(e.g. the U.S. Computer Fraud and Abuse Act, the UK Computer Misuse Act, and
equivalents worldwide) and can carry serious criminal and civil penalties.

The author and contributors accept **no liability** for misuse or damage. By
using this tool you accept full responsibility for your actions. If you do not
have permission to test a target, **do not use this tool against it.**

---

## Features

| Module | Capabilities |
| --- | --- |
| **Network Discovery** | Ping sweep, deep OS/service scan, ARP scan, WiFi AP discovery |
| **MITM** | ARP/DNS spoofing, SSL strip, session hijack, captive portal, evil twin |
| **Exploitation** | SMB/RDP/Web exploits, WiFi (handshake, PMKID, WPS, deauth), exploit search |
| **Post-Exploitation** | Persistence, data exfiltration, privilege escalation, lateral movement |

- `Eye_Of_Zeus_2.sh` — the full framework (recommended).
- `Eye_Of_Zeus.sh` — a lightweight standalone ARP-MITM + traffic-sniff workflow.

## Requirements

- Linux (Kali recommended), run as **root**.
- The scripts check for their dependencies on launch and offer to install the
  missing ones via `apt`. Core tools include: `nmap`, `bettercap`, `ettercap`,
  `hydra`, `aircrack-ng`, `metasploit-framework`, `hcxtools`, `dsniff`,
  `dnsmasq`, `hostapd`, `sslstrip`, and the Python packages `scapy`,
  `requests`, `beautifulsoup4`.
- A running X display is required for `Eye_Of_Zeus.sh` (it opens `xterm`
  windows); it will not work over a plain SSH session.

## Usage

```bash
git clone https://github.com/archnexus707/Eye_Of_Zeus.git
cd Eye_Of_Zeus
chmod +x Eye_Of_Zeus_2.sh
sudo ./Eye_Of_Zeus_2.sh
```

Navigate the numbered menus. Long-running attacks (ARP spoof, SSL strip,
captive portal, evil twin, deauth) run until you press **Ctrl+C**, which cleans
up (restores IP forwarding, removes iptables rules, stops monitor mode) and
returns you to the menu.

## Notes & Caveats

- Several modules depend on tool versions and file paths that vary between Kali
  releases (e.g. `hcxdumptool` flags, exploit-DB script paths, wordlist
  locations under `/usr/share/wordlists`). Verify these on your system.
- `sslstrip` is Python 2 and has been dropped from recent Kali; prefer
  `bettercap`'s SSL-strip caplet if it is unavailable.

## License

Released under the [MIT License](LICENSE).
