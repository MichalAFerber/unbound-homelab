# Unbound DNS Cheatsheet

Quick reference for common tasks and commands.

## Essential Commands

### DNS Operations

```bash
# Regenerate DNS config from TSV
sudo /usr/local/sbin/update_dns.sh

# Sync to secondary server (run from primary)
sudo /usr/local/sbin/sync_dns_to_secondary.sh

# Health check both servers
/usr/local/sbin/dns-check.sh

# Update root hints manually
sudo /usr/local/sbin/update-unbound-root-hints.sh
```

### Service Management

```bash
# Start/Stop/Restart Unbound
sudo systemctl start unbound
sudo systemctl stop unbound
sudo systemctl restart unbound

# Check status
sudo systemctl status unbound

# Enable/disable autostart
sudo systemctl enable unbound
sudo systemctl disable unbound
```

### Systemd Timer

```bash
# Check timer status
systemctl status update-unbound-root-hints.timer

# List all timers
systemctl list-timers

# Enable/disable timer
sudo systemctl enable update-unbound-root-hints.timer
sudo systemctl disable update-unbound-root-hints.timer

# Manually trigger the service
sudo systemctl start update-unbound-root-hints.service
```

## Testing DNS Resolution

### Local Queries

```bash
# Test local DNS server
dig @localhost google.com
dig @localhost example.mykk.foo

# Test specific server
dig @192.168.50.2 google.com
dig @192.168.50.3 plex.mykk.foo

# Quick lookup (no details)
dig +short @localhost google.com

# Test with different record types
dig @localhost example.com MX
dig @localhost example.com AAAA
dig @localhost example.com TXT
```

### Reverse DNS Lookup

```bash
# PTR record lookup
dig -x 192.168.50.2
dig +short -x 192.168.50.205
```

### Performance Testing

```bash
# Time a query
time dig @localhost google.com

# Test cache hit vs miss
dig @localhost example.com          # First query (miss)
dig @localhost example.com          # Second query (hit)

# Benchmark with hyperfine (if installed)
hyperfine 'dig @localhost google.com'
```

### Advanced Testing

```bash
# Trace full resolution path
dig +trace google.com

# Show all details
dig +all @localhost google.com

# Query with TCP instead of UDP
dig +tcp @localhost google.com

# Query with specific timeout
dig +time=1 +tries=1 @localhost google.com
```

## Managing Hosts

### Add a Host

```bash
# Single host
printf "hostname\t192.168.50.100\n" | sudo tee -a /etc/unbound/hosts.d/mykk.foo.tsv
sudo /usr/local/sbin/update_dns.sh

# Host with aliases
printf "hostname\t192.168.50.100\talias1,alias2\n" | sudo tee -a /etc/unbound/hosts.d/mykk.foo.tsv
sudo /usr/local/sbin/update_dns.sh
```

### Edit Hosts

```bash
# Edit the TSV file
sudo nano /etc/unbound/hosts.d/mykk.foo.tsv

# Then regenerate
sudo /usr/local/sbin/update_dns.sh
```

### Remove a Host

```bash
# Edit TSV and remove the line
sudo nano /etc/unbound/hosts.d/mykk.foo.tsv

# Then regenerate
sudo /usr/local/sbin/update_dns.sh
```

## Configuration Files

### Main Config Locations

```bash
# Main Unbound config
sudo nano /etc/unbound/unbound.conf.d/lan53.conf

# Local zone config (auto-generated)
sudo nano /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf

# Hosts database
sudo nano /etc/unbound/hosts.d/mykk.foo.tsv
```

### Validate Configuration

```bash
# Check all configs
sudo unbound-checkconf

# Check specific file
sudo unbound-checkconf /etc/unbound/unbound.conf
```

## Logging and Debugging

### View Logs

```bash
# Real-time logs
sudo journalctl -u unbound -f

# Last 50 entries
sudo journalctl -u unbound -n 50

# Logs since yesterday
sudo journalctl -u unbound --since yesterday

# Logs for specific time range
sudo journalctl -u unbound --since "2024-01-01 00:00:00" --until "2024-01-02 00:00:00"
```

### Enable Debug Logging

```bash
# Edit config to increase verbosity
sudo nano /etc/unbound/unbound.conf.d/lan53.conf
# Change: verbosity: 1  →  verbosity: 2

# Enable query logging temporarily
sudo nano /etc/unbound/unbound.conf.d/lan53.conf
# Change: log-queries: no  →  log-queries: yes

# Restart to apply
sudo systemctl restart unbound
```

### Common Log Patterns

```bash
# Filter for errors
sudo journalctl -u unbound | grep -i error

# Filter for specific domain
sudo journalctl -u unbound | grep example.com

# Count queries
sudo journalctl -u unbound | grep "query:" | wc -l
```

## Backups and Recovery

### Manual Backup

```bash
# Backup all configs
sudo tar -czf ~/unbound-backup-$(date +%Y%m%d).tar.gz \
    /etc/unbound/unbound.conf.d/ \
    /etc/unbound/hosts.d/

# Backup just TSV
sudo cp /etc/unbound/hosts.d/mykk.foo.tsv \
        /etc/unbound/hosts.d/mykk.foo.tsv.backup
```

### Automatic Backups

```bash
# List available backups
ls -lh /etc/unbound/backups/

# View a backup
cat /etc/unbound/backups/local-zone-mykk-foo.conf.20240101-120000.bak
```

### Restore from Backup

```bash
# Restore specific backup
sudo cp /etc/unbound/backups/local-zone-mykk-foo.conf.TIMESTAMP.bak \
        /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf

# Restart Unbound
sudo systemctl restart unbound
```

## Performance Monitoring

### Query Statistics

```bash
# If remote-control is enabled
sudo unbound-control stats

# Check cache size
sudo unbound-control dump_cache | wc -l
```

### Cache Management

```bash
# Flush entire cache
sudo unbound-control flush_zone .

# Flush specific zone
sudo unbound-control flush_zone mykk.foo

# Flush specific name
sudo unbound-control flush example.com
```

### Resource Usage

```bash
# Memory usage
ps aux | grep unbound

# Detailed process info
sudo systemctl status unbound

# System resource limits
sudo cat /proc/$(pidof unbound)/limits
```

## Network Troubleshooting

### Check Listening Ports

```bash
# Show Unbound listening
sudo netstat -tulpn | grep unbound

# Alternative with ss
sudo ss -tulpn | grep unbound

# Verify port 53 is open
sudo lsof -i :53
```

### Test from Remote Client

```bash
# From another machine on the network
dig @192.168.50.2 google.com
nslookup google.com 192.168.50.2

# Test DNSSEC
dig @192.168.50.2 dnssec-failed.org
```

### Firewall Rules

```bash
# Check if firewall is blocking
sudo ufw status
sudo iptables -L -n -v | grep 53

# Allow DNS through firewall (if needed)
sudo ufw allow 53/udp
sudo ufw allow 53/tcp
```

## Sync Between Servers

### Setup SSH Keys

```bash
# Generate key on primary
ssh-keygen -t ed25519 -C "dns-sync"

# Copy to secondary
ssh-copy-id user@192.168.50.3

# Test connection
ssh user@192.168.50.3 "echo 'SSH works'"
```

### Manual Sync

```bash
# From primary to secondary
rsync -avz /etc/unbound/hosts.d/mykk.foo.tsv \
    user@192.168.50.3:/etc/unbound/hosts.d/

# SSH and regenerate on secondary
ssh user@192.168.50.3 "sudo /usr/local/sbin/update_dns.sh"
```

### Verify Sync

```bash
# Compare TSV files
diff /etc/unbound/hosts.d/mykk.foo.tsv \
     <(ssh user@192.168.50.3 "cat /etc/unbound/hosts.d/mykk.foo.tsv")

# Compare generated configs
diff /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf \
     <(ssh user@192.168.50.3 "cat /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf")
```

## Security Checks

### Verify Access Control

```bash
# Test from LAN (should work)
dig @192.168.50.2 google.com

# Test from outside network (should refuse)
# (Run this from external IP or use online DNS tools)
```

### Check DNSSEC

```bash
# Test DNSSEC validation
dig @localhost dnssec-failed.org

# Should return SERVFAIL if DNSSEC is working
```

### Audit Configuration

```bash
# Check for common misconfigurations
sudo unbound-checkconf

# Review security settings
grep -E "access-control|hide-identity|hide-version" \
    /etc/unbound/unbound.conf.d/lan53.conf
```

## Common Issues and Fixes

### Issue: DNS Not Resolving

```bash
# Check if Unbound is running
sudo systemctl status unbound

# Check logs for errors
sudo journalctl -u unbound -n 50

# Test basic connectivity
ping 192.168.50.2

# Restart Unbound
sudo systemctl restart unbound
```

### Issue: Config Validation Failed

```bash
# Check what's wrong
sudo unbound-checkconf

# Review recent changes
ls -lht /etc/unbound/backups/

# Restore last working config
sudo cp /etc/unbound/backups/local-zone-mykk-foo.conf.*.bak \
        /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf
sudo systemctl restart unbound
```

### Issue: Slow Resolution

```bash
# Check if root hints are current
ls -lh /var/lib/unbound/root.hints

# Update root hints
sudo /usr/local/sbin/update-unbound-root-hints.sh

# Clear cache and restart
sudo unbound-control flush_zone .
sudo systemctl restart unbound
```

## Quick Reference Commands

```bash
# ✅ Add host and sync
printf "newhost\t192.168.50.100\n" | sudo tee -a /etc/unbound/hosts.d/mykk.foo.tsv && \
sudo /usr/local/sbin/update_dns.sh && \
sudo /usr/local/sbin/sync_dns_to_secondary.sh

# ✅ Full health check
/usr/local/sbin/dns-check.sh && echo "DNS is healthy" || echo "DNS has issues"

# ✅ View live queries (if logging enabled)
sudo journalctl -u unbound -f | grep "query:"

# ✅ One-liner restart
sudo systemctl restart unbound && systemctl status unbound

# ✅ Quick test both servers
for s in 192.168.50.2 192.168.50.3; do echo "Testing $s:"; dig +short @$s google.com; done
```

## Environment Variables

```bash
# Customize script behavior (if supported)
export DNS_DOMAIN="mykk.foo"
export PRIMARY_IP="192.168.50.2"
export SECONDARY_IP="192.168.50.3"
```

## Useful Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias dns-update='sudo /usr/local/sbin/update_dns.sh'
alias dns-sync='sudo /usr/local/sbin/sync_dns_to_secondary.sh'
alias dns-check='/usr/local/sbin/dns-check.sh'
alias dns-logs='sudo journalctl -u unbound -f'
alias dns-status='sudo systemctl status unbound'
alias dns-restart='sudo systemctl restart unbound'
```

---

**Pro Tip**: Bookmark this cheatsheet for quick reference!
