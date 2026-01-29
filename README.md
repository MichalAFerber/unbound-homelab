# 🛡️ Unbound Home Lab DNS

A production-ready, redundant DNS infrastructure for home labs using Unbound on Raspberry Pi 4 servers.

## Features

- ✅ **Redundant DNS** across two Pi servers (primary/secondary)
- ✅ **Recursive resolution** direct to root servers (no ISP forwarding)
- ✅ **Local zone management** with easy TSV-based editing
- ✅ **Automatic config sync** between servers
- ✅ **Monthly root hints updates** via systemd timers
- ✅ **Health monitoring** with consistency checks
- ✅ **Security hardening** (access controls, DNSSEC, privacy)
- ✅ **Automated backups** and rollback capability

## Quick Start

### Prerequisites

- Two Raspberry Pi 4 (or similar Linux servers)
- Ubuntu/Debian-based OS
- Static IP addresses configured
- SSH access between servers (for sync)

### Installation

1. Clone this repository:
```bash
git clone https://github.com/yourusername/unbound-homelab.git
cd unbound-homelab
```

2. Run the installer:
```bash
sudo ./install.sh
```

3. Edit your hosts file:
```bash
sudo nano /etc/unbound/hosts.d/mykk.foo.tsv
```

4. Generate configuration:
```bash
sudo /usr/local/sbin/update_dns.sh
```

5. Test resolution:
```bash
dig @localhost google.com
dig @localhost yourhost.mykk.foo
```

## Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  pi4server      │         │  pi4server02    │
│  192.168.50.2   │◄───────►│  192.168.50.3   │
│  (Primary DNS)  │  Sync   │  (Secondary DNS)│
└────────┬────────┘         └────────┬────────┘
         │                           │
         └─────────┬─────────────────┘
                   │
         ┌─────────▼────────┐
         │   Asus Router    │
         │   DHCP Server    │
         └─────────┬────────┘
                   │
         ┌─────────▼────────┐
         │   LAN Clients    │
         │  Auto-configure  │
         └──────────────────┘
```

## Configuration Files

### Primary Configuration
- `/etc/unbound/unbound.conf.d/lan53.conf` - Main Unbound config
- `/etc/unbound/hosts.d/mykk.foo.tsv` - Hosts database (TSV format)
- `/etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf` - Generated zone file

### Scripts
- `/usr/local/sbin/update_dns.sh` - Regenerate config from TSV
- `/usr/local/sbin/sync_dns_to_secondary.sh` - Sync to secondary server
- `/usr/local/sbin/update-unbound-root-hints.sh` - Update root hints
- `/usr/local/sbin/dns-check.sh` - Health monitoring

### Systemd Units
- `update-unbound-root-hints.service` - Root hints update service
- `update-unbound-root-hints.timer` - Monthly timer for updates

## Usage

### Adding a New Host

```bash
# Edit TSV file
printf "newhost\t192.168.50.100\talias1,alias2\n" | sudo tee -a /etc/unbound/hosts.d/mykk.foo.tsv

# Regenerate config
sudo /usr/local/sbin/update_dns.sh

# Sync to secondary (from primary)
sudo /usr/local/sbin/sync_dns_to_secondary.sh
```

### Health Check

```bash
/usr/local/sbin/dns-check.sh
```

### Manual Root Hints Update

```bash
sudo /usr/local/sbin/update-unbound-root-hints.sh
```

### View Logs

```bash
# Real-time logs
journalctl -u unbound -f

# Last 50 entries
journalctl -u unbound -n 50
```

## TSV File Format

```tsv
# hostname	ip_address	aliases (comma-separated, optional)
pi4server	192.168.50.2	dns1
plex	192.168.50.205	media,streaming
truenas	192.168.50.202	nas,storage
```

## Security Features

- **Access Control**: Only LAN subnet can query
- **DNSSEC**: Validation enabled
- **Privacy**: QNAME minimization, minimal responses
- **Rate Limiting**: Optional protection against amplification attacks
- **Identity Hiding**: No server version/identity disclosure

## Router Configuration

Configure your DHCP server to use both DNS servers:

- **DNS Server 1**: 192.168.50.2
- **DNS Server 2**: 192.168.50.3
- **Search Domain**: mykk.foo (or your domain)

## Troubleshooting

### DNS not resolving

```bash
# Check if Unbound is running
systemctl status unbound

# Check logs
journalctl -u unbound -n 50

# Test manually
dig @192.168.50.2 google.com
dig @localhost google.com
```

### Config not syncing between servers

```bash
# Verify SSH connectivity
ssh user@192.168.50.3

# Check sync script
sudo /usr/local/sbin/sync_dns_to_secondary.sh

# Compare TSV files
diff /etc/unbound/hosts.d/mykk.foo.tsv \
     user@192.168.50.3:/etc/unbound/hosts.d/mykk.foo.tsv
```

### Root hints not updating

```bash
# Check timer status
systemctl status update-unbound-root-hints.timer

# Check last run
systemctl list-timers

# Manually trigger update
sudo /usr/local/sbin/update-unbound-root-hints.sh
```

## Performance

Typical query response times:
- **Local zone**: <1ms
- **Cached external**: ~2ms
- **Uncached external**: ~180ms (recursive lookup)

## Maintenance

### Backup Configuration

```bash
# Manual backup
sudo tar -czf unbound-backup-$(date +%Y%m%d).tar.gz \
    /etc/unbound/unbound.conf.d/ \
    /etc/unbound/hosts.d/
```

### Restore from Backup

```bash
# Restore from automatic backup
sudo cp /etc/unbound/backups/local-zone-mykk-foo.conf.TIMESTAMP.bak \
        /etc/unbound/unbound.conf.d/local-zone-mykk-foo.conf
sudo systemctl restart unbound
```

## Project Structure

```
unbound-homelab/
├── install.sh                          # Main installation script
├── README.md                           # This file
├── scripts/
│   ├── update_dns.sh                   # Regenerate config from TSV
│   ├── sync_dns_to_secondary.sh        # Sync to secondary server
│   ├── update-unbound-root-hints.sh    # Update root hints
│   └── dns-check.sh                    # Health monitoring
├── systemd/
│   ├── update-unbound-root-hints.service
│   └── update-unbound-root-hints.timer
├── etc/
│   ├── unbound.conf.d/
│   │   ├── lan53.conf                  # Main config
│   │   └── local-zone-mykk-foo.conf.example
│   └── hosts.d/
│       └── mykk.foo.tsv.example        # Example hosts file
└── docs/
    ├── ARCHITECTURE.md                 # Architecture details
    ├── CHEATSHEET.md                   # Command reference
    └── TROUBLESHOOTING.md              # Detailed troubleshooting
```

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Unbound DNS resolver by NLnet Labs
- Root hints from IANA
- Inspired by the home lab community

## Related Projects

- [Pi-hole](https://pi-hole.net/) - Network-wide ad blocking
- [Unbound](https://nlnetlabs.nl/projects/unbound/) - Validating recursive DNS
- [dnscrypt-proxy](https://github.com/DNSCrypt/dnscrypt-proxy) - DNS encryption

## Support

- **Issues**: [GitHub Issues](https://github.com/MichalAFerber/unbound-homelab/issues)
- **Blog Post**: [Full writeup on michalferber.me](https://michalferber.me/2025-09-22-building-a-redundant-unbound-dns-setup-in-my-home-lab)

---

**Created with ❤️ by Michal Ferber, aka TechGuyWithABeard**
