#!/bin/bash
###############################################################################
# sync_dns_to_secondary.sh
# 
# Syncs DNS configuration from primary to secondary Pi server.
# Copies TSV file and triggers config regeneration on secondary.
#
# Usage: sudo /usr/local/sbin/sync_dns_to_secondary.sh
###############################################################################

set -euo pipefail

# Configuration
SECONDARY_IP="192.168.50.3"
SECONDARY_USER="michal"
TSV_FILE="/etc/unbound/hosts.d/mykk.foo.tsv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "==================================="
echo "DNS Configuration Sync to Secondary"
echo "==================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}ERROR: This script must be run as root${NC}" 
   exit 1
fi

# Check if TSV file exists
if [[ ! -f "$TSV_FILE" ]]; then
    echo -e "${RED}ERROR: TSV file not found: $TSV_FILE${NC}"
    exit 1
fi

# Test SSH connectivity
echo -e "${YELLOW}Testing connectivity to secondary server...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${SECONDARY_USER}@${SECONDARY_IP}" "echo 'Connection OK'" > /dev/null 2>&1; then
    echo -e "${RED}✗ ERROR: Cannot connect to ${SECONDARY_USER}@${SECONDARY_IP}${NC}"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Ensure SSH key authentication is set up"
    echo "  2. Test manually: ssh ${SECONDARY_USER}@${SECONDARY_IP}"
    echo "  3. Check if secondary server is reachable: ping ${SECONDARY_IP}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected to secondary server"

# Sync TSV file
echo -e "${YELLOW}Syncing TSV file to secondary...${NC}"
if rsync -avz "$TSV_FILE" "${SECONDARY_USER}@${SECONDARY_IP}:${TSV_FILE}"; then
    echo -e "${GREEN}✓${NC} TSV file synced"
else
    echo -e "${RED}✗ ERROR: Failed to sync TSV file${NC}"
    exit 1
fi

# Trigger config regeneration on secondary
echo -e "${YELLOW}Regenerating configuration on secondary...${NC}"
if ssh "${SECONDARY_USER}@${SECONDARY_IP}" "sudo /usr/local/sbin/update_dns.sh"; then
    echo -e "${GREEN}✓${NC} Configuration regenerated on secondary"
else
    echo -e "${RED}✗ ERROR: Failed to regenerate configuration on secondary${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓✓✓ Sync completed successfully! ✓✓✓${NC}"
echo ""
echo "Both DNS servers should now have identical configurations."
echo "Run dns-check.sh to verify consistency."
