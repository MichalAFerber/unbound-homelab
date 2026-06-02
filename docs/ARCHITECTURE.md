# Architecture

Deeper dive into how the redundant Unbound + Kea DHCP setup is structured and why.

## Overview

Two Ubuntu Server VMs run **Unbound** as recursive caching resolvers. **Kea-DHCP4** runs on **one** of the two VMs (no DHCP redundancy by design — see "Why not redundant DHCP?" below). Both resolvers are handed out to LAN clients via DHCP's `domain-name-servers` option, so client OSes (resolv.conf / NetworkManager / Windows DNS Client) round-robin between them.

## Topology

```
                ┌───────────────────────────────────────┐
                │  Internet                             │
                │  ── 1.1.1.1 / 9.9.9.9 (forwarders) ── │
                │  ── or root servers (recursive)    ── │
                └────────────────────┬──────────────────┘
                                     │
                              ┌──────▼──────┐
                              │   Router    │  Default gateway only.
                              │ 192.168.X.1 │  DHCP **disabled** on the router.
                              └──────┬──────┘
                                     │ LAN (1 GbE)
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
        ┌─────▼─────┐          ┌─────▼─────┐         ┌──────▼──────┐
        │  DNS-1    │          │  DNS-2    │         │ LAN clients │
        │  .10      │          │  .11      │         │  .100-.200  │
        │           │          │           │         │  (DHCP pool)│
        │ Unbound   │          │ Unbound   │         └─────────────┘
        │ Kea-DHCP4 │          │           │
        └───────────┘          └───────────┘
              ▲                      ▲
              └──────────────────────┘
              Both serve queries from clients;
              clients have both in resolv.conf
```

## Software layers

```
┌──────────────────────────────────────────────────┐
│  Ubuntu Server 24.04 LTS (noble)                 │
├──────────────────────────────────────────────────┤
│  systemd-resolved   (disabled — Unbound owns 53) │
│  Unbound 1.19+      (recursive caching resolver) │
│  Kea-DHCP4          (only on DNS-1)              │
│  ufw / iptables     (LAN-only DNS exposure)      │
└──────────────────────────────────────────────────┘
```

`systemd-resolved` is disabled on both VMs so Unbound can bind to `*:53`. The two services don't share port 53.

## Configuration model

The Unbound config has two parts that live in two different files:

| File | Purpose | Sync between hosts? |
|---|---|---|
| `/etc/unbound/unbound.conf` | Distro-default top-level config — just includes `unbound.conf.d/*.conf` | Yes (distro default, identical) |
| `/etc/unbound/unbound.conf.d/local.conf` | All custom config: interface binding, access control, local zone, forwarders | **Mostly yes — diverges only on the `interface:` line** |

The `local.conf` file on DNS-1 differs from DNS-2 in exactly one line:

```diff
-    interface: 192.168.X.10
+    interface: 192.168.X.11
```

Everything else is byte-identical. **Sync is manual** — when you add a host, you edit both files. There is intentionally no rsync/git-sync automation; the surface area is small enough that drift is cheap to detect (any client can `dig @.10 X` vs `dig @.11 X` to spot it).

## Local zone

The `local-zone: "home.lan." static` line tells Unbound:
1. This zone is authoritative locally (don't go ask the internet about `home.lan`)
2. Only data we explicitly define exists (NXDOMAIN for anything else)

The `local-data:` lines define forward records (A). The `local-data-ptr:` lines define reverse records (PTR). A wildcard `*.dev.home.lan.` is used to point an entire subdomain at a reverse-proxy host without listing every subdomain individually.

## Recursive vs forwarders

Both modes are valid; the example config has forwarders enabled.

**Forwarders** (`forward-zone: "."`) — Unbound asks Cloudflare/Quad9 for anything not in the cache or local zone. Pros: faster (CDN-anycast), warmed cache. Cons: those resolvers see your queries.

**Pure recursive** — Unbound walks the DNS hierarchy from the root servers down. Pros: nobody sees your queries except the authoritative servers. Cons: slightly slower first hit; uses root hints.

To switch from forwarders to pure recursive: comment out the entire `forward-zone:` block in `local.conf` and `systemctl reload unbound`. Unbound's compiled-in root hints take over.

## DNSSEC

`module-config: "validator iterator"` enables DNSSEC validation. The trust anchor is `/var/lib/unbound/root.key`, auto-managed by the `unbound-anchor` tool on the distro's monthly schedule. No manual maintenance required.

Verify DNSSEC is working:

```bash
dig @192.168.X.10 dnssec-failed.org +dnssec    # should return SERVFAIL
dig @192.168.X.10 cloudflare.com +dnssec       # should have +ad flag
```

## DHCP (Kea)

Kea is a Linux-native DHCP server from ISC, lighter than ISC dhcpd and trivial to configure as a JSON file. The relevant pieces:

- **`subnet4`** — your LAN subnet + dynamic pool range
- **`option-data`** — pushed to clients on every lease. `domain-name-servers` is the redundancy mechanism (both Unbound IPs).
- **`reservations`** — MAC-to-IP bindings for infrastructure (switches, APs, anything that must have a predictable IP)
- **`lease-database`** — memfile (CSV) is fine for home-scale. Switch to MySQL/Postgres only if you have >1000 leases or want HA.

### Why not redundant DHCP?

Kea supports HA (failover via the HA hook library), but at home scale it's overkill:

- DHCP leases are valid for 24 hours (`valid-lifetime: 86400`)
- A primary failure doesn't drop existing clients off the network
- You have 24 hours to restart the Kea VM before anyone's lease expires
- Restoring from a daily backup of `kea-dhcp4.conf` + `/var/lib/kea/` is a 30-second operation

Cost-benefit: HA Kea = 2× config complexity for a problem that resolves itself in a day. Skip it.

## Hardening

- **`access-control:`** — Unbound only answers queries from the LAN subnet + loopback. Open recursive resolvers are a DDoS amplification vector; do not skip this.
- **`hide-identity:` / `hide-version:`** — don't tell the world what you're running
- **Firewall** — UFW rules should restrict port 53 to the LAN interface only. The VMs shouldn't be reachable on 53/udp or 53/tcp from the WAN.
- **DNSSEC validation** — protects against poisoned responses from upstream forwarders or cache attacks

## Failure modes

| Scenario | Outcome | Recovery |
|---|---|---|
| DNS-2 (secondary) VM down | Clients with .11 first in resolv.conf fall back to .10 after ~2s timeout. Minor latency only. | Boot DNS-2 |
| DNS-1 (primary) VM down | Clients use .11 only. Kea also down → no new DHCP leases. Existing leases continue working. | Boot DNS-1; new clients picked up immediately |
| Both Unbound down | LAN has no DNS. Internet works for IP-addressed traffic only. | Boot at least one VM |
| Kea down, both Unbound up | DNS works. New devices can't get an IP. Existing leases continue for `valid-lifetime`. | Boot the Kea VM |
| Router down | Whole LAN offline. DNS resolution within the LAN still works (resolvers + clients on same subnet). | Recover router |

## Related

- [`CHEATSHEET.md`](CHEATSHEET.md) — daily ops commands
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — diagnosing DNS issues
- [Unbound documentation](https://unbound.docs.nlnetlabs.nl/)
- [Kea documentation](https://kea.readthedocs.io/)
