# Architecture Documentation

Detailed technical architecture of the redundant Unbound DNS setup.

## Overview

This system provides redundant recursive DNS resolution for a home lab environment using two Raspberry Pi 4 servers running Unbound. The architecture emphasizes reliability, security, and ease of maintenance.

## System Components

### Hardware Layer

```
┌─────────────────────────────┐       ┌─────────────────────────────┐
│     Raspberry Pi 4 (4GB)    │       │     Raspberry Pi 4 (4GB)    │
│    pi4server (Primary)      │       │  pi4server02 (Secondary)    │
│    192.168.50.2             │       │    192.168.50.3             │
│                             │       │                             │
│  - Ubuntu Server 24.04      │       │  - Ubuntu Server 24.04      │
│  - 4GB RAM                  │       │  - 4GB RAM                  │
│  - Ethernet (1Gbps)         │       │  - Ethernet (1Gbps)         │
└─────────────────────────────┘       └─────────────────────────────┘
             │                                     │
             └─────────────┬───────────────────────┘
                           │
                    ┌──────▼───────┐
                    │ Asus Router  │
                    │ DHCP Server  │
                    │   Gateway    │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ LAN Clients  │
                    │  (DHCP)      │
                    └──────────────┘
```

### Software Stack

```
┌─────────────────────────────────────────────────┐
│                 Application Layer                │
│  - dig, nslookup, host (DNS query tools)        │
└─────────────────────────────────────────────────┘
                       ↕
┌─────────────────────────────────────────────────┐
│              DNS Resolution Layer                │
│  - Unbound 1.19+ (Recursive resolver)           │
│  - Local zone: mykk.foo                         │
│  - DNSSEC validation                            │
└─────────────────────────────────────────────────┘
                       ↕
┌─────────────────────────────────────────────────┐
│             Configuration Layer                  │
│  - TSV source files                             │
│  - Generated Unbound configs                    │
│  - Systemd services/timers                      │
└─────────────────────────────────────────────────┘
                       ↕
┌─────────────────────────────────────────────────┐
│                Operating System                  │
│  - Ubuntu Server 24.04 LTS                      │
│  - systemd init system                          │
│  - rsync for file sync                          │
└─────────────────────────────────────────────────┘
```

## DNS Query Flow

### External Domain Resolution

```
Client                Primary DNS              Root Servers            Authoritative
Device               (192.168.50.2)           (a-m.root-servers.net)     Servers
  │                        │                          │                     │
  │  Query: google.com     │                          │                     │
  ├───────────────────────►│                          │                     │
  │                        │  Query: . NS?            │                     │
  │                        ├─────────────────────────►│                     │
  │                        │◄─────────────────────────┤                     │
  │                        │  Referral: com. NS       │                     │
  │                        │                          │                     │
  │                        │  Query: google.com NS?   │                     │
  │                        ├─────────────────────────────────────────────────►
  │                        │◄─────────────────────────────────────────────────
  │                        │  Response: 142.250.x.x   │                     │
  │◄───────────────────────┤                          │                     │
  │  Response: 142.250.x.x │                          │                     │
  │                        │                          │                     │
  │                   [Cached for TTL]                │                     │
```

### Local Zone Resolution

```
Client                Primary DNS              Local Zone Config
Device               (192.168.50.2)           (static data)
  │                        │                          │
  │  Query: plex.mykk.foo  │                          │
  ├───────────────────────►│                          │
  │                        │  Lookup: local-zone      │
  │                        ├─────────────────────────►│
  │                        │◄─────────────────────────┤
  │                        │  Return: 192.168.50.205  │
  │◄───────────────────────┤                          │
  │  Response: 192.168.50.205                         │
  │                        │                          │
  │                   [No caching needed]             │
```

### Failover Scenario

```
Client                Primary DNS              Secondary DNS
Device               (192.168.50.2)           (192.168.50.3)
  │                        │                          │
  │  Query: google.com     │                          │
  ├───────────────────────►│                          │
  │                        X (Server Down)            │
  │                        │                          │
  │  [Timeout after 2s]    │                          │
  │                        │                          │
  │  Query: google.com     │                          │
  ├──────────────────────────────────────────────────►│
  │                        │                          │
  │◄──────────────────────────────────────────────────┤
  │  Response: 142.250.x.x │                          │
  │                        │                          │
```

## Configuration Management

### Data Flow: From TSV to Active Config

```
┌──────────────────────────────────────────────────────────┐
│  1. Source of Truth                                      │
│  /etc/unbound/hosts.d/mykk.foo.tsv                      │
│                                                          │
│  hostname<TAB>ip<TAB>aliases                            │
│  plex<TAB>192.168.50.205<TAB>media,streaming           │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│  2. Generation Script                                    │
│  /usr/local/sbin/update_dns.sh                          │
│                                                          │
│  - Parse TSV file                                       │
│  - Generate A records                                   │
│  - Generate PTR records                                 │
│  - Generate CNAME aliases                               │
│  - Create timestamped backup                            │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│  3. Generated Configuration                              │
│  /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf   │
│                                                          │
│  server:                                                │
│    local-zone: "mykk.foo." static                       │
│    local-data: "plex.mykk.foo. IN A 192.168.50.205"    │
│    local-data: "media.mykk.foo. IN CNAME plex.mykk.foo"│
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│  4. Validation                                           │
│  unbound-checkconf                                      │
│                                                          │
│  - Syntax validation                                    │
│  - Semantic checks                                      │
│  - If fails: restore backup                             │
└──────────────────────┬───────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────┐
│  5. Activation                                           │
│  systemctl restart unbound                              │
│                                                          │
│  - Reload configuration                                 │
│  - Clear caches                                         │
│  - Start answering queries                              │
└──────────────────────────────────────────────────────────┘
```

### Synchronization Flow (Primary → Secondary)

```
┌────────────────────────────────────────────────────────────┐
│  Primary Server (192.168.50.2)                             │
│                                                            │
│  1. TSV file updated                                       │
│  2. update_dns.sh regenerates config                       │
│  3. Unbound restarted                                      │
└────────────────────┬───────────────────────────────────────┘
                     │
                     │ sync_dns_to_secondary.sh
                     │
                     ▼
┌────────────────────────────────────────────────────────────┐
│  SSH + rsync                                               │
│                                                            │
│  rsync -avz TSV → secondary                               │
│  ssh secondary "sudo update_dns.sh"                       │
└────────────────────┬───────────────────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────────────────┐
│  Secondary Server (192.168.50.3)                           │
│                                                            │
│  1. Receives updated TSV                                   │
│  2. update_dns.sh regenerates config                       │
│  3. Unbound restarted                                      │
│  4. Now serving identical zone data                        │
└────────────────────────────────────────────────────────────┘
```

## File System Layout

```
/etc/unbound/
├── unbound.conf                    # Main Unbound config (usually includes .d/)
├── unbound.conf.d/
│   ├── lan53.conf                  # Server-specific config (interface, ACLs, etc.)
│   └── local-zone-mykk-foo.conf    # Generated local zone (auto-created)
├── hosts.d/
│   └── mykk.foo.tsv                # Source of truth for DNS records
└── backups/
    └── local-zone-mykk-foo.conf.YYYYMMDD-HHMMSS.bak  # Timestamped backups

/var/lib/unbound/
├── root.hints                      # DNS root servers list (updated monthly)
└── root.key                        # DNSSEC trust anchor (auto-managed)

/usr/local/sbin/
├── update_dns.sh                   # Regenerate config from TSV
├── sync_dns_to_secondary.sh        # Sync to secondary server
├── update-unbound-root-hints.sh    # Update root hints
└── dns-check.sh                    # Health monitoring

/etc/systemd/system/
├── update-unbound-root-hints.service  # Root hints update service
└── update-unbound-root-hints.timer    # Monthly trigger
```

## Network Architecture

### Port Usage

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| DNS | 53 | UDP | Primary DNS queries |
| DNS | 53 | TCP | Large responses, zone transfers |
| SSH | 22 | TCP | Configuration sync between servers |

### IP Addressing Scheme

```
Network: 192.168.50.0/24
Gateway: 192.168.50.1 (Router)

┌─────────────────────────────────────────┐
│  Static Assignments (DHCP Reserved)     │
├─────────────────────────────────────────┤
│  192.168.50.2   - pi4server (DNS1)      │
│  192.168.50.3   - pi4server02 (DNS2)    │
│  192.168.50.200-220 - Lab servers       │
├─────────────────────────────────────────┤
│  DHCP Pool: 192.168.50.50-199          │
└─────────────────────────────────────────┘
```

### DNS Query Path

```
[Client]
   │
   │ DNS Query (UDP/53)
   ▼
[Router DHCP]
   │
   │ Returns: DNS1=192.168.50.2, DNS2=192.168.50.3
   ▼
[Client OS]
   │
   │ Try DNS1 first
   ▼
[Unbound Primary - 192.168.50.2]
   │
   ├──► Local zone? → Return static data
   │
   └──► External? → Recursive lookup
          │
          ├──► Check cache
          │     └──► Hit? Return cached
          │
          └──► Miss? Query root servers
                └──► Follow referrals
                     └──► Cache & return
```

## Security Architecture

### Access Control Layers

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Network Firewall (Optional)                   │
│  - Block external access to port 53                     │
│  - Allow only LAN subnet                                │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 2: Unbound Access Control Lists                  │
│  - access-control: 192.168.50.0/24 allow               │
│  - access-control: 0.0.0.0/0 refuse                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Query Privacy                                 │
│  - QNAME minimization (RFC 7816)                       │
│  - Minimal responses                                    │
│  - Hide server identity/version                         │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 4: DNSSEC Validation                             │
│  - Validate cryptographic signatures                    │
│  - Prevent cache poisoning                              │
│  - Detect tampering                                     │
└─────────────────────────────────────────────────────────┘
```

### Trust Model

```
┌──────────────────┐
│   Root Zone      │  ← IANA managed
│   (trust anchor) │     - root.key
└────────┬─────────┘     - Auto-updated via RFC 5011
         │
         ▼
┌──────────────────┐
│   TLD Zones      │  ← e.g., .com, .org, .net
│   (DNSSEC chain) │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Domain Zones    │  ← e.g., google.com
│  (signed)        │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Validated       │  ← Unbound verifies entire chain
│  Response        │
└──────────────────┘

Local Zones (mykk.foo):
  - Not DNSSEC signed (internal only)
  - Trusted implicitly (static configuration)
  - Not validated against external authority
```

## Scalability Considerations

### Current Capacity

- **Queries per second**: ~1000 (per server)
- **Cache entries**: ~50,000 (16MB rrset cache)
- **Concurrent clients**: Unlimited (LAN subnet)
- **Memory usage**: ~100MB per server at peak

### Scaling Options

#### Vertical Scaling (Single Server)
- Increase cache sizes (more RAM)
- Add more threads (more CPU cores)
- Enable prefetching for popular domains

#### Horizontal Scaling (Add Servers)
```
Primary + Secondary + Tertiary
    ↓         ↓         ↓
  DNS1      DNS2      DNS3
192.168.50.2 → .3 → .4

Client receives all three
Tries in order: DNS1 → DNS2 → DNS3
```

#### Load Balancing (Advanced)
```
         ┌──────────────┐
         │ HAProxy/VIP  │
         │ 192.168.50.5 │
         └───────┬──────┘
                 │
     ┌───────────┼───────────┐
     ▼           ▼           ▼
  DNS1        DNS2        DNS3
   .2          .3          .4
```

## Monitoring and Health

### Health Check Flow

```
┌─────────────────────────────────────────┐
│  dns-check.sh                           │
│                                         │
│  For each server (DNS1, DNS2):          │
│    For each test host:                  │
│      1. Query local domain              │
│      2. Query external domain           │
│      3. Compare responses               │
│      4. Check service status            │
└─────────────────────┬───────────────────┘
                      │
                      ▼
        ┌─────────────────────────┐
        │  All tests pass?        │
        └─────────┬───────────────┘
         YES │   │ NO
             │   ▼
             │   Report errors:
             │   - Server unreachable
             │   - Query timeout
             │   - Mismatched responses
             │   - Service not running
             │
             ▼
         Success!
         Exit 0
```

### Metrics to Monitor

1. **Availability**
   - Service uptime (systemd status)
   - Query success rate
   - Network reachability

2. **Performance**
   - Query response time
   - Cache hit rate
   - Memory usage

3. **Configuration**
   - Sync status between servers
   - Backup age
   - Root hints freshness

## Disaster Recovery

### Failure Scenarios

#### Primary Server Failure
```
Normal Operation:          Primary Failed:
    DNS1 → Success             DNS1 → Timeout
    DNS2 → Standby             DNS2 → Success
    
Action: None required      Action: Fix DNS1, verify sync
Impact: None visible       Impact: ~2s delay per query
```

#### Both Servers Failure
```
DNS1 → Timeout
DNS2 → Timeout

Action: Manual intervention required
Impact: No DNS resolution (clients use ISP DNS if configured)

Recovery:
1. Fix hardware/network issues
2. Restore from backups if needed
3. Run dns-check.sh to verify
```

#### Configuration Corruption
```
Bad Config Deployed:
   update_dns.sh detects → Validation fails
   Restores backup → Restart with old config
   
Manual Override:
   Restore from /etc/unbound/backups/
   systemctl restart unbound
```

### Backup Strategy

```
┌─────────────────────────────────────────┐
│  Automatic Backups                      │
│  - Every config generation              │
│  - Timestamped files                    │
│  - Kept in /etc/unbound/backups/        │
│  - Retention: Last 30 days              │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│  Manual Backups (Recommended)           │
│  - Weekly tar.gz of /etc/unbound/       │
│  - Store off-system (NAS, cloud)        │
│  - Test restore procedure quarterly     │
└─────────────────────────────────────────┘
```

## Future Enhancements

### Planned Improvements

1. **Pi-hole Integration**
   - Ad-blocking upstream from Unbound
   - DNS-level tracking protection

2. **Prometheus Monitoring**
   - Expose metrics endpoint
   - Grafana dashboards
   - Alerting on anomalies

3. **Conditional Forwarding**
   - Forward corporate domains to office DNS
   - Forward IoT domain to isolated resolver

4. **DNSSEC Signing**
   - Sign local zones
   - Full chain of trust

5. **IPv6 Support**
   - AAAA records for local hosts
   - IPv6 recursive queries

---

**Architecture designed for reliability, security, and maintainability in home lab environments.**
