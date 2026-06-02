# Cheatsheet

Daily ops reference for the Unbound + Kea setup. Replace `dns-primary` / `dns-secondary` / `192.168.X.10` / `192.168.X.11` with your actual hostnames and IPs.

## Service control

```bash
# Unbound (run on each resolver)
sudo systemctl status unbound --no-pager
sudo systemctl reload unbound          # config change, no cache flush
sudo systemctl restart unbound         # config change + cache flush
sudo systemctl stop unbound
sudo systemctl start unbound

# Kea (on the host running DHCP)
sudo systemctl status kea-dhcp4-server --no-pager
sudo systemctl restart kea-dhcp4-server
```

## Validate config before applying

```bash
# Unbound — fails loudly if the conf is broken; safer than reload-and-see
sudo unbound-checkconf

# Kea — JSON syntax + semantic check
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
```

## DNS query testing

```bash
# From a LAN client — test each resolver explicitly
dig @192.168.X.10 router.home.lan      # local zone, primary
dig @192.168.X.11 router.home.lan      # local zone, secondary
dig @192.168.X.10 google.com           # recursion / forwarding works
dig @192.168.X.10 google.com +dnssec   # +ad flag = DNSSEC validated
dig @192.168.X.10 -x 192.168.X.30      # reverse lookup

# Use the system resolver (whatever resolv.conf points at)
dig router.home.lan
nslookup router.home.lan
```

## Cache inspection

```bash
# How many entries are in the cache right now
sudo unbound-control stats_noreset | grep total.num.cachehits

# Dump the entire cache
sudo unbound-control dump_cache | less

# Flush a specific entry (useful when a record changed and TTL is long)
sudo unbound-control flush example.com

# Flush an entire zone (recursive — includes subdomains)
sudo unbound-control flush_zone home.lan

# Nuclear option: clear everything
sudo unbound-control reload
```

## Stats / monitoring

```bash
# Quick stats snapshot
sudo unbound-control stats_noreset | head -25

# Most useful counters:
#   total.num.queries           total queries served
#   total.num.cachehits         queries answered from cache
#   total.num.cachemiss         queries that hit upstream
#   total.requestlist.avg       avg pending queries (should be near 0)
#   unwanted.queries            queries from clients we shouldn't be serving
```

## Adding a host to the local zone

1. SSH into the **primary** resolver
2. Edit `/etc/unbound/unbound.conf.d/local.conf`, add:
   ```
   local-data: "newhost.home.lan. IN A 192.168.X.42"
   local-data-ptr: "192.168.X.42 newhost.home.lan"
   ```
3. `sudo unbound-checkconf && sudo systemctl reload unbound`
4. Repeat steps 2–3 on the **secondary** resolver (or `scp` the file over and reload)
5. Test: `dig @192.168.X.10 newhost.home.lan` and `dig @192.168.X.11 newhost.home.lan` — both should answer

## Sync the two resolvers (one-liner)

```bash
# Copy the canonical local.conf from primary -> secondary,
# then patch the interface line and reload
ssh dns-primary 'cat /etc/unbound/unbound.conf.d/local.conf' \
  | sed 's/192.168.X.10/192.168.X.11/' \
  | ssh dns-secondary 'sudo tee /etc/unbound/unbound.conf.d/local.conf > /dev/null \
       && sudo unbound-checkconf \
       && sudo systemctl reload unbound'
```

## DHCP — Kea operations

```bash
# Current leases (CSV format)
sudo cat /var/lib/kea/kea-leases4.csv

# Just the active leases, formatted
sudo awk -F, '$8==0 {print $1, $3, $9}' /var/lib/kea/kea-leases4.csv | column -t

# Watch new leases come in
sudo tail -f /var/log/kea-dhcp4.log
# (or journalctl if Kea logs to systemd)
sudo journalctl -u kea-dhcp4-server -f

# Add a reservation: edit /etc/kea/kea-dhcp4.conf, then:
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf      # validate
sudo systemctl restart kea-dhcp4-server         # apply
```

## Backups

```bash
# Backup both resolver configs + Kea state
ts=$(date +%F)
ssh dns-primary "sudo tar czf - /etc/unbound /etc/kea /var/lib/kea" \
  > ~/backups/dns-primary-$ts.tar.gz
ssh dns-secondary "sudo tar czf - /etc/unbound" \
  > ~/backups/dns-secondary-$ts.tar.gz
```

## Useful one-liners

```bash
# Which clients have queried me in the last hour?  (requires query log enabled)
sudo journalctl -u unbound --since "1 hour ago" | awk '{print $5}' | sort -u

# Cache hit ratio (rough — over lifetime of the daemon)
sudo unbound-control stats_noreset \
  | awk -F= '/total.num.queries/{q=$2} /total.num.cachehits/{h=$2} END {printf "%.1f%%\n", 100*h/q}'

# Test that the forwarders (1.1.1.1 / 9.9.9.9) are reachable
dig @1.1.1.1 google.com +short
dig @9.9.9.9 google.com +short
```
