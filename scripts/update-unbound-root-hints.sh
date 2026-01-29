#!/bin/bash
###############################################################################
# update-unbound-root-hints.sh
# 
# Downloads and updates the DNS root hints file for Unbound.
# Validates the download and only updates if content has changed.
# Restarts Unbound if root hints are updated.
#
# Usage: /usr/local/sbin/update-unbound-root-hints.sh
# Typically run via systemd timer (monthly)
###############################################################################

set -euo pipefail

# Configuration
ROOT_HINTS="/var/lib/unbound/root.hints"
ROOT_HINTS_URL="https://www.internic.net/domain/named.root"
TEMP_FILE="/tmp/root.hints.tmp.$$"
BACKUP_FILE="${ROOT_HINTS}.bak"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Cleanup on exit
cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT

echo "==================================="
echo "Unbound Root Hints Update"
echo "==================================="
echo ""
echo "Date: $(date)"
echo "Source: $ROOT_HINTS_URL"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}ERROR: This script must be run as root${NC}" 
   exit 1
fi

# Download fresh root hints
echo -e "${YELLOW}Downloading root hints...${NC}"
if ! curl -fsSL -o "$TEMP_FILE" "$ROOT_HINTS_URL"; then
    echo -e "${RED}✗ ERROR: Failed to download root hints${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Downloaded successfully"

# Verify file is not empty
if [[ ! -s "$TEMP_FILE" ]]; then
    echo -e "${RED}✗ ERROR: Downloaded file is empty${NC}"
    exit 1
fi

# Verify it looks like a valid root hints file
# Should contain lines starting with "." (root zone)
if ! grep -q "^\\." "$TEMP_FILE"; then
    echo -e "${RED}✗ ERROR: File doesn't appear to be a valid root hints file${NC}"
    echo "First few lines of downloaded file:"
    head -n 5 "$TEMP_FILE"
    exit 1
fi
echo -e "${GREEN}✓${NC} File validation passed"

# Check if content has changed
if [[ -f "$ROOT_HINTS" ]]; then
    if cmp -s "$ROOT_HINTS" "$TEMP_FILE"; then
        echo -e "${GREEN}✓${NC} Root hints unchanged, no update needed"
        echo ""
        echo "Current root hints are already up to date."
        echo "Last modified: $(stat -c %y "$ROOT_HINTS")"
        exit 0
    fi
    echo -e "${YELLOW}Content has changed, updating...${NC}"
else
    echo -e "${YELLOW}No existing root hints found, creating...${NC}"
fi

# Backup existing file
if [[ -f "$ROOT_HINTS" ]]; then
    cp "$ROOT_HINTS" "$BACKUP_FILE"
    echo -e "${GREEN}✓${NC} Backup created: $BACKUP_FILE"
fi

# Replace with new file
mv "$TEMP_FILE" "$ROOT_HINTS"
chown unbound:unbound "$ROOT_HINTS" 2>/dev/null || chown root:root "$ROOT_HINTS"
chmod 644 "$ROOT_HINTS"
echo -e "${GREEN}✓${NC} Root hints file updated: $ROOT_HINTS"

# Restart Unbound
echo -e "${YELLOW}Restarting Unbound...${NC}"
if systemctl restart unbound; then
    echo -e "${GREEN}✓${NC} Unbound restarted successfully"
else
    echo -e "${RED}✗ ERROR: Failed to restart Unbound${NC}"
    
    # Try to restore backup
    if [[ -f "$BACKUP_FILE" ]]; then
        echo -e "${YELLOW}Restoring backup...${NC}"
        cp "$BACKUP_FILE" "$ROOT_HINTS"
        systemctl restart unbound
    fi
    
    exit 1
fi

# Verify Unbound is running
sleep 1
if systemctl is-active --quiet unbound; then
    echo -e "${GREEN}✓${NC} Unbound is running"
else
    echo -e "${RED}✗ WARNING: Unbound is not running${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓✓✓ Root hints updated successfully! ✓✓✓${NC}"
echo ""
echo "Summary:"
echo "  - Updated: $ROOT_HINTS"
echo "  - Backup: $BACKUP_FILE"
echo "  - Unbound: Restarted and running"
