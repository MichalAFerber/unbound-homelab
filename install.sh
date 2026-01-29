#!/bin/bash
###############################################################################
# install.sh
# 
# Installation script for Unbound home lab DNS setup
# Copies files to correct locations and sets up systemd services
#
# Usage: sudo ./install.sh
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================="
echo "Unbound Home Lab DNS Setup Installer"
echo "======================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}ERROR: This script must be run as root${NC}" 
   exit 1
fi

# Detect script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Working from: $SCRIPT_DIR"
echo ""

# Confirm installation
read -p "This will install Unbound DNS configuration. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1: Installing Unbound package...${NC}"
if command -v unbound &> /dev/null; then
    echo -e "${GREEN}✓${NC} Unbound already installed"
else
    apt update
    apt install -y unbound curl
    echo -e "${GREEN}✓${NC} Unbound installed"
fi

echo ""
echo -e "${BLUE}Step 2: Creating directory structure...${NC}"
mkdir -p /etc/unbound/unbound.conf.d
mkdir -p /etc/unbound/hosts.d
mkdir -p /etc/unbound/backups
mkdir -p /var/lib/unbound
mkdir -p /usr/local/sbin
echo -e "${GREEN}✓${NC} Directories created"

echo ""
echo -e "${BLUE}Step 3: Downloading root hints...${NC}"
if [[ ! -f /var/lib/unbound/root.hints ]]; then
    curl -fsSL -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.root
    chown unbound:unbound /var/lib/unbound/root.hints 2>/dev/null || chown root:root /var/lib/unbound/root.hints
    chmod 644 /var/lib/unbound/root.hints
    echo -e "${GREEN}✓${NC} Root hints downloaded"
else
    echo -e "${GREEN}✓${NC} Root hints already present"
fi

echo ""
echo -e "${BLUE}Step 4: Installing scripts...${NC}"
for script in scripts/*.sh; do
    if [[ -f "$script" ]]; then
        SCRIPT_NAME=$(basename "$script")
        cp "$script" /usr/local/sbin/
        chmod +x /usr/local/sbin/"$SCRIPT_NAME"
        echo -e "${GREEN}✓${NC} Installed $SCRIPT_NAME"
    fi
done

echo ""
echo -e "${BLUE}Step 5: Installing systemd units...${NC}"
for unit in systemd/*; do
    if [[ -f "$unit" ]]; then
        UNIT_NAME=$(basename "$unit")
        cp "$unit" /etc/systemd/system/
        echo -e "${GREEN}✓${NC} Installed $UNIT_NAME"
    fi
done

echo ""
echo -e "${BLUE}Step 6: Installing configuration files...${NC}"

# Check if lan53.conf already exists
if [[ -f /etc/unbound/unbound.conf.d/lan53.conf ]]; then
    echo -e "${YELLOW}⚠${NC} lan53.conf already exists, creating backup..."
    cp /etc/unbound/unbound.conf.d/lan53.conf /etc/unbound/unbound.conf.d/lan53.conf.bak
fi

# Copy configuration
cp etc/unbound.conf.d/lan53.conf /etc/unbound/unbound.conf.d/
echo -e "${GREEN}✓${NC} Installed lan53.conf"

# Copy example TSV if it doesn't exist
if [[ ! -f /etc/unbound/hosts.d/mykk.foo.tsv ]]; then
    cp etc/hosts.d/mykk.foo.tsv.example /etc/unbound/hosts.d/mykk.foo.tsv
    echo -e "${GREEN}✓${NC} Installed mykk.foo.tsv (example)"
else
    echo -e "${YELLOW}⚠${NC} mykk.foo.tsv already exists, keeping current version"
fi

# Copy example zone config
cp etc/unbound.conf.d/local-zone-mykk-foo.conf.example /etc/unbound/unbound.conf.d/
echo -e "${GREEN}✓${NC} Installed local-zone example"

echo ""
echo -e "${BLUE}Step 7: Configuring systemd...${NC}"
systemctl daemon-reload
systemctl enable update-unbound-root-hints.timer
systemctl start update-unbound-root-hints.timer
echo -e "${GREEN}✓${NC} Systemd timer enabled and started"

echo ""
echo -e "${BLUE}Step 8: Configuring Unbound...${NC}"

# Prompt for server IP
echo ""
echo "This server's IP address should be configured in lan53.conf"
echo "Current IP addresses on this system:"
ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print "  - " $2}'
echo ""
read -p "Enter this server's LAN IP (e.g., 192.168.50.2 or 192.168.50.3): " SERVER_IP

# Update interface in config
sed -i "s/interface: 192.168.50.2/interface: ${SERVER_IP}/" /etc/unbound/unbound.conf.d/lan53.conf
echo -e "${GREEN}✓${NC} Set interface to $SERVER_IP"

# Prompt for domain
echo ""
read -p "Enter your local domain name (default: mykk.foo): " LOCAL_DOMAIN
LOCAL_DOMAIN=${LOCAL_DOMAIN:-mykk.foo}
echo -e "${GREEN}✓${NC} Using domain: $LOCAL_DOMAIN"

# Update domain in scripts if not mykk.foo
if [[ "$LOCAL_DOMAIN" != "mykk.foo" ]]; then
    sed -i "s/mykk\\.foo/$LOCAL_DOMAIN/g" /usr/local/sbin/update_dns.sh
    echo -e "${GREEN}✓${NC} Updated domain in scripts"
fi

echo ""
echo -e "${BLUE}Step 9: Generating initial DNS configuration...${NC}"
/usr/local/sbin/update_dns.sh

echo ""
echo -e "${BLUE}Step 10: Setting up SSH key for sync (optional)...${NC}"
if [[ "$SERVER_IP" == "192.168.50.2" ]]; then
    echo "This appears to be the primary server."
    read -p "Do you want to configure SSH key for secondary sync? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter username for SSH to secondary server: " SSH_USER
        read -p "Enter secondary server IP (default: 192.168.50.3): " SECONDARY_IP
        SECONDARY_IP=${SECONDARY_IP:-192.168.50.3}
        
        echo ""
        echo "Run these commands to set up passwordless SSH:"
        echo "  1. ssh-keygen -t ed25519 -C 'dns-sync'"
        echo "  2. ssh-copy-id ${SSH_USER}@${SECONDARY_IP}"
        echo "  3. Update /usr/local/sbin/sync_dns_to_secondary.sh with correct IP and user"
    fi
fi

echo ""
echo "======================================="
echo -e "${GREEN}✓✓✓ Installation Complete! ✓✓✓${NC}"
echo "======================================="
echo ""
echo "Next steps:"
echo "  1. Edit /etc/unbound/hosts.d/mykk.foo.tsv with your hosts"
echo "  2. Run: sudo /usr/local/sbin/update_dns.sh"
echo "  3. Test: dig @${SERVER_IP} google.com"
echo "  4. Health check: /usr/local/sbin/dns-check.sh"
echo ""
echo "If this is the secondary server:"
echo "  - Make sure SSH key from primary is authorized"
echo "  - Primary can sync with: sudo /usr/local/sbin/sync_dns_to_secondary.sh"
echo ""
echo "Configuration files:"
echo "  - Main config: /etc/unbound/unbound.conf.d/lan53.conf"
echo "  - Hosts TSV: /etc/unbound/hosts.d/mykk.foo.tsv"
echo "  - Generated zone: /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf"
echo ""
echo "Useful commands:"
echo "  - Update DNS: sudo /usr/local/sbin/update_dns.sh"
echo "  - Sync to secondary: sudo /usr/local/sbin/sync_dns_to_secondary.sh"
echo "  - Health check: /usr/local/sbin/dns-check.sh"
echo "  - Check timer: systemctl status update-unbound-root-hints.timer"
echo "  - View logs: journalctl -u unbound -f"
echo ""
