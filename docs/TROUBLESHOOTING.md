# Troubleshooting

When DNS is broken, work top-to-bottom. Each section assumes the ones above passed.

## Step 0: Is the daemon even running?

```bash
sudo systemctl status unbound --no-pager
```

If it's not running, start with that. `journalctl -u unbound -n 50` to see why it died. Common causes:
- `systemd-resolved` also bound to port 53 (`sudo systemctl disable --now systemd-resolved`)
- Config syntax error from the last edit (`sudo unbound-checkconf` to confirm)
- Permissions on `/var/lib/unbound/root.key` (should be owned by `unbound:unbound`)

## Step 1: Is the resolver answering at all?

From the resolver host itself:

```bash
dig @127.0.0.1 google.com +short
```

- Returns IPs → DNS works locally. Skip to Step 3.
- Times out / SERVFAIL → continue with Step 2.

## Step 2: Is Unbound listening on the right interface?

```bash
sudo ss -lnup | grep ':53'
sudo ss -lntp | grep ':53'
```

Expect two lines per protocol — one binding to `127.0.0.1:53` and one to `192.168.X.10:53` (the LAN IP). If only loopback is listed, the `interface:` line in `local.conf` is wrong or missing the LAN IP.

## Step 3: Is the resolver reachable from a LAN client?

From a client machine:

```bash
dig @192.168.X.10 google.com +short
```

- Returns IPs → Unbound is fine. Issue is on the client side (skip to Step 6).
- Times out → continue with Step 4.

## Step 4: Network path / firewall

```bash
# From the client
ping 192.168.X.10
nc -zv 192.168.X.10 53           # TCP — verifies LAN routing + port open
nc -zvu 192.168.X.10 53          # UDP

# On the resolver — is UFW or iptables blocking?
sudo ufw status verbose
sudo iptables -L -n | grep ':53'
```

If `ping` works but `nc -zvu` fails, port 53 is blocked. On UFW:

```bash
sudo ufw allow from 192.168.X.0/24 to any port 53
```

## Step 5: `access-control:` rejecting the client

If queries reach Unbound but get refused, Unbound's `access-control:` is too narrow.

```bash
# On the resolver — watch live for refusals
sudo journalctl -u unbound -f | grep -iE "refused|denied"
```

In `local.conf`, the `access-control: 192.168.X.0/24 allow` line must cover the client's IP. Don't forget secondary subnets if you have VLANs.

## Step 6: Client uses the wrong resolver

```bash
# Linux/macOS
cat /etc/resolv.conf                    # what the resolver lib thinks
scutil --dns 2>/dev/null | head -20    # macOS — what the system actually uses

# Windows
ipconfig /all | findstr "DNS Servers"
```

On managed-by-NetworkManager systems, `/etc/resolv.conf` may be auto-overwritten. To verify, check what NetworkManager has set:

```bash
nmcli dev show | grep DNS
```

If DHCP isn't pushing your two Unbound IPs, the issue is in Kea, not Unbound. See Step 9.

## Step 7: DNSSEC validation failure (SERVFAIL on real domains)

If `dig` works for some domains but returns SERVFAIL on others, with the `+dnssec` flag showing no `ad` flag:

```bash
# Check the trust anchor file exists + is recent
sudo ls -la /var/lib/unbound/root.key

# Force an update
sudo unbound-anchor -a /var/lib/unbound/root.key

# Then restart
sudo systemctl restart unbound
```

If a specific domain consistently SERVFAILs and `dig +cd` (checking-disabled) makes it work, that domain has broken DNSSEC. That's their problem, not yours — but you can whitelist it:

```
# In local.conf
server:
    domain-insecure: "broken-zone.example."
```

## Step 8: Stale cache (record changed but you're still getting the old one)

```bash
sudo unbound-control flush <hostname>            # one record
sudo unbound-control flush_zone <zone>           # whole zone, recursive
sudo unbound-control reload                      # nuclear: clear everything + reload config
```

## Step 9: Kea DHCP not handing out the right DNS servers

```bash
# On the DHCP host
sudo systemctl status kea-dhcp4-server --no-pager
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf       # validate config

# Watch leases as clients renew
sudo journalctl -u kea-dhcp4-server -f
```

Then from a client, force a renewal:

```bash
# Linux (dhclient-based)
sudo dhclient -r && sudo dhclient

# macOS
sudo ipconfig set en0 BOOTP && sudo ipconfig set en0 DHCP

# Windows
ipconfig /release && ipconfig /renew
```

And re-check the client's resolver list. If Kea is fine but the client still has old servers, the client cached the lease somewhere — reboot it.

## Step 10: One resolver works, the other doesn't

This is by far the most common operational issue after adding a new host: you edited `local.conf` on one resolver but forgot the other.

```bash
# Diff the two files
ssh dns-primary 'cat /etc/unbound/unbound.conf.d/local.conf' > /tmp/dns1.conf
ssh dns-secondary 'cat /etc/unbound/unbound.conf.d/local.conf' > /tmp/dns2.conf
diff /tmp/dns1.conf /tmp/dns2.conf
```

The only line that should differ is the `interface:` line. Anything else is drift; sync from primary using the one-liner in [CHEATSHEET.md](CHEATSHEET.md#sync-the-two-resolvers-one-liner).

## Step 11: Both resolvers down — emergency

If both Unbound VMs are unreachable and you need internet *right now*:

1. On any LAN client, manually set DNS to `1.1.1.1` and `9.9.9.9`
2. Internet browsing works; LAN-internal hostnames stop resolving until DNS is back

Then troubleshoot the VMs at your leisure. Check the Proxmox host first — if the host is down, both VMs are gone. If the host is up, individually console into each VM and run Step 0.

## Useful log locations

| Log | Where |
|---|---|
| Unbound systemd journal | `journalctl -u unbound` |
| Kea systemd journal | `journalctl -u kea-dhcp4-server` |
| Kea leases | `/var/lib/kea/kea-leases4.csv` |
| Root trust anchor | `/var/lib/unbound/root.key` |

## When in doubt: nuke and reload

For Unbound, the "is it the config or is it the cache?" question is settled by:

```bash
sudo unbound-checkconf && sudo systemctl restart unbound
```

A full restart clears the entire cache and re-reads the config. If problems persist after this, the issue is structural (config error, network, firewall) — not stale cache.
