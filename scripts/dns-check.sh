#!/bin/bash
###############################################################################
# dns-check.sh
# 
# Health check script for redundant DNS servers.
# Tests resolution of both local and external domains across all servers.
# Verifies consistency and detects configuration drift.
#
# Usage: /usr/local/sbin/dns-check.sh
###############################################################################

set -euo pipefail

# Configuration
SERVERS=(192.168.50.2 192.168.50.3)
LOCAL_HOSTS=("pi4server.mykk.foo" "plex.mykk.foo" "truenas.mykk.foo")
EXTERNAL_HOSTS=("google.com" "cloudflare.com")
TIMEOUT=2

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================="
echo "DNS Health Check"
echo "======================================="
echo "Date: $(date)"
echo ""

ERRORS=0
WARNINGS=0

# Function to query DNS
query_dns() {
    local server=$1
    local hostname=$2
    dig +short +time="$TIMEOUT" +tries=1 @"$server" "$hostname" 2>/dev/null | head -n1
}

# Function to check server reachability
check_server_reachable() {
    local server=$1
    if ! ping -c 1 -W 1 "$server" > /dev/null 2>&1; then
        echo -e "${RED}✗ Server $server is not reachable${NC}"
        return 1
    fi
    return 0
}

# Check server reachability first
echo -e "${BLUE}Checking server connectivity...${NC}"
for s in "${SERVERS[@]}"; do
    if check_server_reachable "$s"; then
        echo -e "  ${GREEN}✓${NC} $s - reachable"
    else
        echo -e "  ${RED}✗${NC} $s - UNREACHABLE"
        ((ERRORS++))
    fi
done
echo ""

# Check local hosts
echo -e "${BLUE}Checking local zone resolution (mykk.foo)...${NC}"
for h in "${LOCAL_HOSTS[@]}"; do
    echo -e "\nHost: ${YELLOW}$h${NC}"
    
    RESULTS=()
    for s in "${SERVERS[@]}"; do
        RESULT=$(query_dns "$s" "$h")
        RESULTS+=("$RESULT")
        
        if [[ -z "$RESULT" ]]; then
            echo -e "  ${RED}✗${NC} $s - NO RESPONSE"
            ((ERRORS++))
        else
            echo -e "  ${GREEN}✓${NC} $s - $RESULT"
        fi
    done
    
    # Check if all results match
    if [[ ${#RESULTS[@]} -gt 1 ]]; then
        FIRST="${RESULTS[0]}"
        MISMATCH=0
        for r in "${RESULTS[@]:1}"; do
            if [[ "$r" != "$FIRST" ]]; then
                MISMATCH=1
                break
            fi
        done
        
        if [[ $MISMATCH -eq 1 ]]; then
            echo -e "  ${RED}⚠ MISMATCH DETECTED - Servers returning different results${NC}"
            ((ERRORS++))
        fi
    fi
done

echo ""

# Check external hosts
echo -e "${BLUE}Checking external domain resolution...${NC}"
for h in "${EXTERNAL_HOSTS[@]}"; do
    echo -e "\nHost: ${YELLOW}$h${NC}"
    
    RESULTS=()
    for s in "${SERVERS[@]}"; do
        RESULT=$(query_dns "$s" "$h")
        RESULTS+=("$RESULT")
        
        if [[ -z "$RESULT" ]]; then
            echo -e "  ${RED}✗${NC} $s - NO RESPONSE"
            ((ERRORS++))
        else
            echo -e "  ${GREEN}✓${NC} $s - $RESULT"
        fi
    done
done

echo ""

# Check Unbound service status
echo -e "${BLUE}Checking Unbound service status...${NC}"
for s in "${SERVERS[@]}"; do
    # Determine which server this is
    if [[ "$s" == "192.168.50.2" ]]; then
        SERVER_NAME="pi4server (primary)"
        # Check local service if we're on pi4server
        if [[ "$(hostname -I | grep -o '192.168.50.2')" ]]; then
            if systemctl is-active --quiet unbound; then
                echo -e "  ${GREEN}✓${NC} $SERVER_NAME - service running"
            else
                echo -e "  ${RED}✗${NC} $SERVER_NAME - service NOT running"
                ((ERRORS++))
            fi
        else
            echo -e "  ${YELLOW}ℹ${NC} $SERVER_NAME - status check skipped (remote)"
        fi
    elif [[ "$s" == "192.168.50.3" ]]; then
        SERVER_NAME="pi4server02 (secondary)"
        # Check local service if we're on pi4server02
        if [[ "$(hostname -I | grep -o '192.168.50.3')" ]]; then
            if systemctl is-active --quiet unbound; then
                echo -e "  ${GREEN}✓${NC} $SERVER_NAME - service running"
            else
                echo -e "  ${RED}✗${NC} $SERVER_NAME - service NOT running"
                ((ERRORS++))
            fi
        else
            echo -e "  ${YELLOW}ℹ${NC} $SERVER_NAME - status check skipped (remote)"
        fi
    fi
done

echo ""
echo "======================================="

# Summary
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓✓✓ All checks passed! ✓✓✓${NC}"
    echo ""
    echo "DNS infrastructure is healthy:"
    echo "  - All servers responding"
    echo "  - Local zones resolving correctly"
    echo "  - External queries working"
    echo "  - No configuration drift detected"
    exit 0
else
    echo -e "${RED}✗✗✗ $ERRORS error(s) detected ✗✗✗${NC}"
    echo ""
    echo "Recommended actions:"
    if [[ $ERRORS -gt 0 ]]; then
        echo "  1. Check Unbound logs: journalctl -u unbound -n 50"
        echo "  2. Verify configurations are in sync"
        echo "  3. Test manually: dig @192.168.50.2 google.com"
        echo "  4. Review /etc/unbound/unbound.conf.d/*.conf"
    fi
    exit 1
fi
