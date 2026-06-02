# 🛡️ Unbound Home Lab DNS

Redundant recursive DNS for a home lab — two **Unbound** resolvers on Ubuntu VMs, fed by a single **Kea** DHCPv4 server. All hosts on the LAN get DHCP from one place; DNS queries land on whichever resolver answers first.

🔗 Live README: <https://michalaferber.github.io/unbound-homelab/>

> **Note** — this repo was originally built around two Raspberry Pi 4 servers running a TSV-driven Unbound config with custom sync scripts. It has since been simplified: stock Unbound on Ubuntu VMs, no custom scripts, no automation. The current docs reflect the simplified setup.

## What this gives you

- **Redundant DNS** — two Unbound resolvers; clients get both as `domain-name-servers` via DHCP
- **Authoritative local zone** — your LAN's hosts resolve by name (e.g. `nas.home.lan` → `192.168.X.30`)
- **Reverse DNS** — `dig -x 192.168.X.30` returns the hostname
- **DHCP reservations** — pin specific MACs to specific IPs (network gear, servers)
- **DNSSEC validation** at the resolver
- **Cache + prefetch** — repeat queries answered locally in microseconds

What this **doesn't** give you — and intentionally:
- No ad-blocking. Add Pi-hole or AdGuard Home upstream if you want that.
- No automatic config sync between the two resolvers. The two `local.conf` files are kept in sync manually. They diverge in exactly one line (the `interface:` binding).
- No installer script. Two `apt install`s + drop-in config files is all there is.

## Stack

| Role | Component | Where it runs |
|---|---|---|
| Recursive resolver (primary) | Unbound 1.19+ | Ubuntu 24.04 LTS VM |
| Recursive resolver (secondary) | Unbound 1.19+ | Ubuntu 24.04 LTS VM |
| DHCPv4 | Kea-DHCP4 | One of the resolver VMs (no DHCP redundancy in this design) |

Both VMs run on a Proxmox host as Ubuntu Server VMs (1-2 vCPU, 1-2 GB RAM is plenty).

## Quick start

### 1. Install on each resolver

```bash
sudo apt update
sudo apt install -y unbound
```

### 2. Drop in your `local.conf`

Copy [`etc/unbound/unbound.conf.d/local.conf.example`](etc/unbound/unbound.conf.d/local.conf.example) to `/etc/unbound/unbound.conf.d/local.conf` on **each** resolver. Edit:

- The `interface:` line → bind to that host's LAN IP (primary uses `.10`, secondary `.11`, or whatever your scheme is)
- `access-control:` → your LAN subnet
- `local-zone:` and `local-data:` lines → your LAN domain + host map

### 3. Test, reload, verify

```bash
sudo unbound-checkconf
sudo systemctl restart unbound
sudo systemctl status unbound --no-pager

# From a LAN client:
dig @192.168.X.10 router.home.lan      # should return the local A
dig @192.168.X.10 google.com           # should return a real A
dig @192.168.X.10 google.com +dnssec   # ad flag = DNSSEC validated
```

### 4. Install Kea on one of the VMs

```bash
sudo apt install -y kea-dhcp4-server
```

Copy [`etc/kea/kea-dhcp4.conf.example`](etc/kea/kea-dhcp4.conf.example) to `/etc/kea/kea-dhcp4.conf`. Edit:

- `interfaces` → the actual NIC name (often `enp6s18` on Proxmox VMs, `eth0` on bare metal)
- `subnet4` block → your LAN subnet + pool range
- `domain-name-servers` → IPs of your two Unbound resolvers
- `reservations` → MAC-to-IP for your network gear

```bash
sudo systemctl enable --now kea-dhcp4-server
sudo systemctl status kea-dhcp4-server --no-pager
```

### 5. Disable the router's built-in DHCP

Your existing router/firewall (pfSense, OPNsense, Netgate, etc.) should stop handing out DHCP leases — otherwise clients race between the two. The router stays as the default gateway; Kea hands out the gateway IP as the `routers` option.

## Architecture

```
                  ┌─────────────────────┐
                  │  Router / Firewall  │
                  │  192.168.X.1        │
                  │  (gateway only —    │
                  │   DHCP disabled)    │
                  └──────────┬──────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼────────┐  ┌────────▼────────┐  ┌────────▼────────┐
│ DNS Primary    │  │ DNS Secondary   │  │  LAN Clients    │
│ 192.168.X.10   │  │ 192.168.X.11    │  │  192.168.X.100+ │
│                │  │                 │  │  (DHCP pool)    │
│ Unbound 1.19+  │  │ Unbound 1.19+   │  │                 │
│ Kea-DHCP4 ─────┼──┼─────────────────┼─►│ resolv.conf:    │
│                │  │                 │  │   .10           │
│                │  │                 │  │   .11           │
└───────┬────────┘  └────────┬────────┘  └─────────────────┘
        │                    │
        └──────────┬─────────┘
                   │
        Recursive → root, or forward → 1.1.1.1 / 9.9.9.9
```

DHCP runs on **one** host only (typically the primary). DNS runs on **both**. If the primary VM goes down, DNS still works from the secondary. DHCP renewals will fail until the primary is back — but existing leases are valid for `valid-lifetime` (24 hours by default), so the LAN keeps working.

## Repo layout

```
unbound-homelab/
├── etc/
│   ├── unbound/unbound.conf.d/local.conf.example
│   └── kea/kea-dhcp4.conf.example
├── docs/
│   ├── ARCHITECTURE.md         deeper architectural detail + rationale
│   ├── CHEATSHEET.md           one-screen ops reference
│   └── TROUBLESHOOTING.md      when DNS is broken, look here
├── _config.yml                 Jekyll/cayman theme for GitHub Pages
├── LICENSE                     MIT
└── README.md                   you are here
```

## License

MIT — see [LICENSE](LICENSE).
