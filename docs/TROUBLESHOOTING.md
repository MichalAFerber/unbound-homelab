# Troubleshooting Guide

Comprehensive troubleshooting guide for common issues with Unbound DNS setup.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [DNS Resolution Issues](#dns-resolution-issues)
- [Service Issues](#service-issues)
- [Configuration Issues](#configuration-issues)
- [Network Issues](#network-issues)
- [Synchronization Issues](#synchronization-issues)
- [Performance Issues](#performance-issues)
- [Security Issues](#security-issues)

---

## Quick Diagnostics

Run these commands first to get a quick overview:

```bash
# Check service status
sudo systemctl status unbound

# Test local resolution
dig @localhost google.com

# Run health check
/usr/local/sbin/dns-check.sh

# Check logs for errors
sudo journalctl -u unbound -n 50 | grep -i error
```

---

## DNS Resolution Issues

### Issue: Cannot Resolve Any Domains

**Symptoms:**
- `dig @localhost google.com` returns SERVFAIL or times out
- All DNS queries fail

**Diagnostic Steps:**

```bash
# 1. Check if Unbound is running
sudo systemctl status unbound

# 2. Check if Unbound is listening on port 53
sudo netstat -tulpn | grep :53

# 3. Check logs for errors
sudo journalctl -u unbound -n 100

# 4. Verify configuration
sudo unbound-checkconf
```

**Common Causes & Solutions:**

1. **Unbound not running**
   ```bash
   sudo systemctl start unbound
   sudo systemctl enable unbound
   ```

2. **Port 53 already in use**
   ```bash
   # Find what's using port 53
   sudo lsof -i :53
   
   # Common culprits: systemd-resolved, dnsmasq
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   ```

3. **Firewall blocking**
   ```bash
   sudo ufw allow 53/udp
   sudo ufw allow 53/tcp
   ```

4. **Invalid configuration**
   ```bash
   # Restore from backup
   sudo cp /etc/unbound/backups/local-zone-mykk-foo.conf.*.bak \
           /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf
   sudo systemctl restart unbound
   ```

---

### Issue: External Domains Don't Resolve

**Symptoms:**
- Local domains (e.g., `plex.mykk.foo`) work fine
- External domains (e.g., `google.com`) fail

**Diagnostic Steps:**

```bash
# 1. Test external resolution
dig @localhost google.com

# 2. Check root hints
ls -lh /var/lib/unbound/root.hints
cat /var/lib/unbound/root.hints | head -20

# 3. Test direct root query
dig @198.41.0.4 google.com

# 4. Check for upstream network issues
ping 8.8.8.8
```

**Common Causes & Solutions:**

1. **Missing or corrupt root hints**
   ```bash
   sudo /usr/local/sbin/update-unbound-root-hints.sh
   ```

2. **Network connectivity issues**
   ```bash
   # Test outbound connectivity
   ping 1.1.1.1
   curl -I https://www.google.com
   
   # Check default route
   ip route show
   ```

3. **DNS port blocked by ISP/firewall**
   ```bash
   # Test if UDP/53 is blocked
   dig @8.8.8.8 +tcp google.com  # Try TCP
   ```

4. **DNSSEC validation failing**
   ```bash
   # Temporarily disable DNSSEC to test
   sudo nano /etc/unbound/unbound.conf.d/lan53.conf
   # Add: module-config: "iterator"
   # Remove DNSSEC hardening options
   sudo systemctl restart unbound
   ```

---

### Issue: Local Domains Don't Resolve

**Symptoms:**
- External domains work fine
- Local domains (e.g., `plex.mykk.foo`) fail

**Diagnostic Steps:**

```bash
# 1. Check if local zone is loaded
dig @localhost plex.mykk.foo

# 2. Verify zone file exists
cat /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf

# 3. Check TSV source
cat /etc/unbound/hosts.d/mykk.foo.tsv

# 4. Validate config
sudo unbound-checkconf
```

**Common Causes & Solutions:**

1. **Zone file not generated**
   ```bash
   sudo /usr/local/sbin/update_dns.sh
   ```

2. **Typo in hostname or domain**
   ```bash
   # Check TSV for errors
   cat /etc/unbound/hosts.d/mykk.foo.tsv
   
   # Regenerate
   sudo /usr/local/sbin/update_dns.sh
   ```

3. **Zone file not included**
   ```bash
   # Ensure this line exists in main config
   grep -r "include.*local-zone-mykk-foo" /etc/unbound/
   
   # If missing, Unbound might not be loading .conf.d/
   cat /etc/unbound/unbound.conf | grep "include:"
   ```

---

## Service Issues

### Issue: Unbound Won't Start

**Symptoms:**
- `systemctl start unbound` fails
- Service shows "failed" status

**Diagnostic Steps:**

```bash
# 1. Check detailed status
sudo systemctl status unbound -l

# 2. Check logs
sudo journalctl -u unbound -n 100 --no-pager

# 3. Try starting manually
sudo unbound -d -v
```

**Common Causes & Solutions:**

1. **Configuration syntax error**
   ```bash
   sudo unbound-checkconf
   # Fix errors shown
   ```

2. **Permission issues**
   ```bash
   # Check ownership
   ls -la /etc/unbound/
   ls -la /var/lib/unbound/
   
   # Fix if needed
   sudo chown -R unbound:unbound /var/lib/unbound/
   ```

3. **Port already in use**
   ```bash
   sudo lsof -i :53
   # Stop conflicting service
   ```

4. **SELinux/AppArmor blocking**
   ```bash
   # Check AppArmor (Ubuntu)
   sudo aa-status | grep unbound
   
   # Temporarily disable to test
   sudo aa-complain /usr/sbin/unbound
   ```

---

### Issue: Unbound Crashes or Restarts Frequently

**Symptoms:**
- Service keeps restarting
- Logs show segfaults or crashes

**Diagnostic Steps:**

```bash
# 1. Check system resources
free -h
df -h

# 2. Check for OOM killer
sudo journalctl -k | grep -i "out of memory"
sudo journalctl -k | grep -i "killed process"

# 3. Check Unbound logs
sudo journalctl -u unbound -n 500 | grep -i "fatal\|crash\|segfault"

# 4. Run memory test
sudo unbound -d -v  # Watch memory usage
```

**Common Causes & Solutions:**

1. **Out of memory**
   ```bash
   # Check current memory usage
   ps aux | grep unbound
   
   # Reduce cache sizes in config
   sudo nano /etc/unbound/unbound.conf.d/lan53.conf
   # Change:
   # msg-cache-size: 8m  → 4m
   # rrset-cache-size: 16m → 8m
   
   sudo systemctl restart unbound
   ```

2. **Too many threads for Pi**
   ```bash
   # Reduce threads
   sudo nano /etc/unbound/unbound.conf.d/lan53.conf
   # Change: num-threads: 2 → 1
   ```

3. **Corrupted cache**
   ```bash
   # Clear cache and restart
   sudo rm -rf /var/lib/unbound/*.cache
   sudo systemctl restart unbound
   ```

---

## Configuration Issues

### Issue: Config Validation Fails

**Symptoms:**
- `unbound-checkconf` reports errors
- `update_dns.sh` fails validation step

**Diagnostic Steps:**

```bash
# 1. Run validation
sudo unbound-checkconf

# 2. Check specific file
sudo unbound-checkconf /etc/unbound/unbound.conf

# 3. View recent changes
ls -lt /etc/unbound/backups/
```

**Common Causes & Solutions:**

1. **Syntax errors in generated config**
   ```bash
   # View the generated file
   cat /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf
   
   # Check for:
   # - Missing quotes
   # - Incorrect indentation
   # - Invalid IP addresses
   # - Missing trailing dots on FQDNs
   ```

2. **TSV format errors**
   ```bash
   # Check for tabs vs spaces
   cat -A /etc/unbound/hosts.d/mykk.foo.tsv
   # Should show ^I for tabs, not spaces
   
   # Fix spaces to tabs
   sudo sed -i 's/  \+/\t/g' /etc/unbound/hosts.d/mykk.foo.tsv
   ```

3. **Restore from backup**
   ```bash
   LATEST_BACKUP=$(ls -t /etc/unbound/backups/*.bak | head -1)
   sudo cp "$LATEST_BACKUP" \
           /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf
   sudo systemctl restart unbound
   ```

---

### Issue: Changes Not Taking Effect

**Symptoms:**
- Updated TSV file
- Ran `update_dns.sh`
- But queries still return old data

**Diagnostic Steps:**

```bash
# 1. Check if config was actually updated
ls -lt /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf
cat /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf | grep "hostname"

# 2. Check if Unbound restarted
sudo systemctl status unbound

# 3. Check if cache is returning stale data
dig @localhost hostname.mykk.foo
```

**Solutions:**

```bash
# 1. Manually regenerate
sudo /usr/local/sbin/update_dns.sh

# 2. Force restart
sudo systemctl restart unbound

# 3. Clear cache (if using unbound-control)
sudo unbound-control flush_zone mykk.foo

# 4. Verify changes
dig @localhost hostname.mykk.foo
cat /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf | grep hostname
```

---

## Network Issues

### Issue: Clients Can't Reach DNS Server

**Symptoms:**
- `dig @192.168.50.2 google.com` times out from client
- Works from server itself (`dig @localhost`)

**Diagnostic Steps:**

```bash
# On DNS server:
# 1. Check if listening on correct interface
sudo netstat -tulpn | grep :53

# 2. Check firewall
sudo ufw status
sudo iptables -L -n -v | grep 53

# 3. Test from server
dig @192.168.50.2 google.com

# From client:
# 4. Test connectivity
ping 192.168.50.2

# 5. Test DNS
dig @192.168.50.2 google.com
```

**Common Causes & Solutions:**

1. **Firewall blocking port 53**
   ```bash
   sudo ufw allow from 192.168.50.0/24 to any port 53
   sudo ufw reload
   ```

2. **Listening on wrong interface**
   ```bash
   # Check current setting
   grep "interface:" /etc/unbound/unbound.conf.d/lan53.conf
   
   # Should be: interface: 192.168.50.2 (or .3 for secondary)
   # Not: interface: 127.0.0.1
   
   # Fix and restart
   sudo nano /etc/unbound/unbound.conf.d/lan53.conf
   sudo systemctl restart unbound
   ```

3. **Access control blocking clients**
   ```bash
   # Check ACLs
   grep "access-control:" /etc/unbound/unbound.conf.d/lan53.conf
   
   # Should have:
   # access-control: 192.168.50.0/24 allow
   ```

---

### Issue: Slow DNS Resolution

**Symptoms:**
- Queries take 5-10 seconds
- Intermittent timeouts

**Diagnostic Steps:**

```bash
# 1. Measure query time
time dig @localhost google.com

# 2. Check cache hit rate
sudo unbound-control stats | grep "num.cache"

# 3. Check network latency
ping 8.8.8.8
traceroute 8.8.8.8

# 4. Check root hints freshness
ls -lh /var/lib/unbound/root.hints
```

**Common Causes & Solutions:**

1. **Root hints outdated**
   ```bash
   sudo /usr/local/sbin/update-unbound-root-hints.sh
   ```

2. **Network congestion**
   ```bash
   # Test alternative DNS temporarily
   dig @8.8.8.8 google.com
   
   # If faster, issue is with root lookups
   # Consider forwarding mode temporarily
   ```

3. **Cache too small**
   ```bash
   # Increase cache size
   sudo nano /etc/unbound/unbound.conf.d/lan53.conf
   # msg-cache-size: 8m → 16m
   # rrset-cache-size: 16m → 32m
   sudo systemctl restart unbound
   ```

4. **DNSSEC validation overhead**
   ```bash
   # Check if DNSSEC is causing delays
   dig @localhost +dnssec google.com
   
   # Time with and without DNSSEC
   time dig @localhost +dnssec google.com
   time dig @localhost +cd google.com  # +cd disables checking
   ```

---

## Synchronization Issues

### Issue: Secondary Server Out of Sync

**Symptoms:**
- `dns-check.sh` reports mismatches
- Queries to .2 and .3 return different results

**Diagnostic Steps:**

```bash
# On primary (192.168.50.2):
# 1. Check TSV file
cat /etc/unbound/hosts.d/mykk.foo.tsv

# 2. Check generated config
cat /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf

# 3. Compare with secondary
diff /etc/unbound/hosts.d/mykk.foo.tsv \
     <(ssh user@192.168.50.3 "cat /etc/unbound/hosts.d/mykk.foo.tsv")
```

**Solutions:**

```bash
# 1. Manually sync
sudo /usr/local/sbin/sync_dns_to_secondary.sh

# 2. If that fails, manual rsync
rsync -avz /etc/unbound/hosts.d/mykk.foo.tsv \
      user@192.168.50.3:/etc/unbound/hosts.d/

ssh user@192.168.50.3 "sudo /usr/local/sbin/update_dns.sh"

# 3. Verify sync
/usr/local/sbin/dns-check.sh
```

---

### Issue: SSH Sync Fails

**Symptoms:**
- `sync_dns_to_secondary.sh` reports connection errors
- "Permission denied" errors

**Diagnostic Steps:**

```bash
# 1. Test SSH connectivity
ssh user@192.168.50.3 "echo 'test'"

# 2. Check SSH key
ls -la ~/.ssh/id_*

# 3. Check authorized_keys on secondary
ssh user@192.168.50.3 "cat ~/.ssh/authorized_keys"
```

**Solutions:**

```bash
# 1. Set up SSH key if missing
ssh-keygen -t ed25519 -C "dns-sync"
ssh-copy-id user@192.168.50.3

# 2. Fix permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# On secondary:
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# 3. Test passwordless login
ssh user@192.168.50.3 "hostname"
```

---

## Performance Issues

### Issue: High CPU Usage

**Symptoms:**
- Unbound using >50% CPU constantly
- System feels sluggish

**Diagnostic Steps:**

```bash
# 1. Check CPU usage
top -p $(pidof unbound)

# 2. Check query rate
sudo unbound-control stats | grep "num.query"

# 3. Check thread usage
ps -T -p $(pidof unbound)
```

**Solutions:**

```bash
# 1. Reduce threads if over-allocated
sudo nano /etc/unbound/unbound.conf.d/lan53.conf
# num-threads: 2 → 1

# 2. Enable prefetching to reduce query bursts
# prefetch: no → prefetch: yes

# 3. Increase cache TTLs
# cache-min-ttl: 300 → 600

sudo systemctl restart unbound
```

---

### Issue: High Memory Usage

**Symptoms:**
- Unbound using >500MB RAM
- System running out of memory

**Diagnostic Steps:**

```bash
# 1. Check memory usage
ps aux | grep unbound
free -h

# 2. Check cache stats
sudo unbound-control stats | grep "cache"
```

**Solutions:**

```bash
# Reduce cache sizes
sudo nano /etc/unbound/unbound.conf.d/lan53.conf

# Change:
# msg-cache-size: 8m → 4m
# rrset-cache-size: 16m → 8m
# key-cache-size: 4m → 2m

sudo systemctl restart unbound
```

---

## Security Issues

### Issue: Open Resolver (Responding to External Queries)

**Symptoms:**
- Queries from internet IPs are being answered
- Potential abuse for DNS amplification attacks

**Diagnostic Steps:**

```bash
# 1. Check access controls
grep "access-control:" /etc/unbound/unbound.conf.d/lan53.conf

# 2. Test from external IP (use online tool)
# dig @your-public-ip google.com

# 3. Check firewall
sudo ufw status
```

**Solutions:**

```bash
# 1. Ensure proper ACLs
sudo nano /etc/unbound/unbound.conf.d/lan53.conf

# Should have:
# access-control: 127.0.0.0/8 allow
# access-control: 192.168.50.0/24 allow
# access-control: 0.0.0.0/0 refuse

# 2. Add firewall rules
sudo ufw default deny incoming
sudo ufw allow from 192.168.50.0/24 to any port 53
sudo ufw enable

# 3. Restart and verify
sudo systemctl restart unbound
```

---

### Issue: DNSSEC Validation Failures

**Symptoms:**
- Some domains return SERVFAIL
- Logs show "validation failure"

**Diagnostic Steps:**

```bash
# 1. Test specific domain
dig @localhost dnssec-failed.org

# 2. Check DNSSEC trust anchor
ls -lh /var/lib/unbound/root.key

# 3. Check logs
sudo journalctl -u unbound | grep -i dnssec
```

**Solutions:**

```bash
# 1. Update trust anchor
sudo unbound-anchor -a /var/lib/unbound/root.key

# 2. Update root hints
sudo /usr/local/sbin/update-unbound-root-hints.sh

# 3. If persistent, temporarily disable for testing
sudo nano /etc/unbound/unbound.conf.d/lan53.conf
# Comment out: harden-dnssec-stripped: yes

sudo systemctl restart unbound
```

---

## Emergency Recovery

### Complete System Failure

If nothing works:

```bash
# 1. Stop Unbound
sudo systemctl stop unbound

# 2. Backup current config
sudo cp -r /etc/unbound /tmp/unbound-backup

# 3. Restore from repo
cd ~/unbound-homelab
sudo ./install.sh

# 4. Or restore from tar backup
sudo tar -xzf unbound-backup-DATE.tar.gz -C /

# 5. Restart
sudo systemctl restart unbound
```

### Getting Help

If you're still stuck:

1. **Gather diagnostics:**
   ```bash
   # Create diagnostic bundle
   mkdir ~/dns-diagnostics
   sudo journalctl -u unbound -n 500 > ~/dns-diagnostics/unbound.log
   sudo unbound-checkconf > ~/dns-diagnostics/checkconf.txt 2>&1
   cp /etc/unbound/unbound.conf.d/*.conf ~/dns-diagnostics/
   /usr/local/sbin/dns-check.sh > ~/dns-diagnostics/health-check.txt 2>&1
   
   tar -czf dns-diagnostics.tar.gz ~/dns-diagnostics/
   ```

2. **Check GitHub issues:** [Project Issues](https://github.com/yourusername/unbound-homelab/issues)

3. **Community forums:**
   - r/homelab
   - Unbound mailing list
   - Server Fault

---

**Remember**: Most issues can be solved by checking logs, validating configs, and restarting the service. When in doubt, restore from backup!
