# Network Configuration

This guide covers BIRD (BGP routing) and WireGuard (VPN) configuration management.

## BIRD Configuration

BIRD is used for BGP routing on core, IXP, and VLT servers to announce AS215011 routes.

### Configuration Files

BIRD configurations are located in `networks/{hostname}/bird/`:

```
networks/
├── coreams01/
│   └── bird/
│       └── bird.conf
├── ixpams01/
│   └── bird/
│       ├── bird.conf
│       └── peerlab.conf  # Optional
└── ...
```

!!! note "Not Templated"
    BIRD configs are **not** Jinja2 templates. They are static files copied as-is to servers.

### Update BIRD Configuration

1. **Edit the configuration**:
   ```bash
   vim networks/coreams01/bird/bird.conf
   ```

2. **Sync to server**:
   ```bash
   make sync-bird
   ```

   This will prompt for your BECOME password (sudo password).

3. **Verify the change**:
   ```bash
   ssh nxthdr@ams01.core.infra.nxthdr.dev
   sudo birdc show status
   sudo birdc show protocols all
   ```

### BIRD Playbook Details

The `sync-bird` playbook (`playbooks/sync-bird.yml`):

1. Creates `/etc/bird` directory
2. Copies `bird.conf` from `networks/{hostname}/bird/`
3. Copies optional `peerlab.conf` if it exists
4. Copies systemd service file
5. Reloads systemd daemon
6. Reloads BIRD service

**Target hosts**: `core`, `ixp`, `vlt`

### Common BIRD Operations

**Check BIRD status**:
```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
sudo birdc show status
```

**View BGP sessions**:
```bash
sudo birdc show protocols
```

**View routing table**:
```bash
sudo birdc show route
```

**Reload BIRD configuration**:
```bash
sudo birdc configure
```

**Restart BIRD service**:
```bash
sudo systemctl restart bird
```

## WireGuard Configuration

WireGuard VPN tunnels connect IXP servers to the core server.

### Configuration Files

WireGuard configurations are in `networks/{hostname}/wireguard/`:

```
networks/
├── coreams01/
│   └── wireguard/
│       ├── wg0.conf
│       └── wg1.conf
├── ixpams01/
│   └── wireguard/
│       ├── wg0.conf
│       └── wg1.conf
└── ...
```

!!! note "Templated"
    WireGuard configs **are** Jinja2 templates and can use variables from inventory and secrets.

### Update WireGuard Configuration

1. **Edit the configuration**:
   ```bash
   vim networks/coreams01/wireguard/wg0.conf
   ```

2. **Sync to server**:
   ```bash
   make sync-wireguard
   ```

   This will prompt for your BECOME password.

3. **Verify the tunnel**:
   ```bash
   ssh nxthdr@ams01.core.infra.nxthdr.dev
   sudo wg show
   ```

### WireGuard Playbook Details

The `sync-wireguard` playbook (`playbooks/sync-wireguard.yml`):

1. Templates all files from `networks/{hostname}/wireguard/`
2. Copies to `/etc/wireguard/` on remote server
3. Restarts `wg-quick@wg0.service`
4. Restarts `wg-quick@wg1.service`

**Target hosts**: `core`, `ixp`

### Common WireGuard Operations

**Check tunnel status**:
```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
sudo wg show
```

**Restart WireGuard interface**:
```bash
sudo systemctl restart wg-quick@wg0
```

**View WireGuard logs**:
```bash
sudo journalctl -u wg-quick@wg0 -f
```

**Test connectivity through tunnel**:
```bash
ping6 <remote_tunnel_ip>
```

### Generate WireGuard Keys

To create new WireGuard keys:

```bash
# Generate private key
wg genkey

# Generate public key from private key
echo "<private_key>" | wg pubkey
```

Store the private key in `secrets/secrets.yml`:

```bash
make edit-secrets
```

Add:
```yaml
wireguard_private_key_wg0: "<private_key>"
```

Use in config:
```ini
PrivateKey = {{ secrets.wireguard_private_key_wg0 }}
```

## Network Topology

### Core to IXP Tunnels

```
┌─────────────┐                    ┌─────────────┐
│  coreams01  │◄──── WireGuard ────►│  ixpams01   │
│  (Core)     │      Tunnel         │  (IXP)      │
└─────────────┘                    └─────────────┘
      │                                    │
      │ Announces                          │ Peers with
      │ 2a06:de00:50::/44                 │ other ASes
      │                                    │
      └────────────────────────────────────┘
           Traffic flows through AS215011
```

### Prefix Announcements

- **Core services**: `2a06:de00:50::/44`
  - Announced by core to IXP servers
  - IXP servers propagate to Internet via BGP

- **Probing infrastructure**: `2a0e:97c0:8a0::/44`
  - Announced by VLT servers
  - Enables unicast/anycast measurements

## Firewall Configuration

### Docker Firewall Rules

By default, Docker networks are isolated. To allow external access:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
sudo ip6tables -I DOCKER-USER -d 2a06:de00:50:cafe:100::/80 -j ACCEPT
```

This allows traffic to the DMZ network.

!!! warning "Manual Configuration"
    This firewall rule is not managed by the infrastructure code and must be applied manually.

### View Current Rules

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
sudo ip6tables -L DOCKER-USER -n -v
```

## Troubleshooting

### BIRD Not Starting

**Check logs**:
```bash
sudo journalctl -u bird -n 50
```

**Common issues**:
- Syntax error in config: `sudo bird -p -c /etc/bird/bird.conf`
- Port already in use: `sudo netstat -tulpn | grep 179`
- Missing dependencies: `sudo apt install bird2`

### WireGuard Tunnel Down

**Check interface status**:
```bash
sudo wg show
sudo ip link show wg0
```

**Common issues**:
- Firewall blocking UDP port: `sudo ufw allow 51820/udp`
- Incorrect endpoint: Check `Endpoint` in config
- Key mismatch: Verify public/private key pairs

**Restart tunnel**:
```bash
sudo systemctl restart wg-quick@wg0
```

### BGP Session Not Establishing

**Check BIRD logs**:
```bash
sudo birdc show protocols all peer_name
```

**Common issues**:
- Incorrect neighbor IP
- AS number mismatch
- Firewall blocking TCP port 179
- Peer not configured on remote side

**Test connectivity**:
```bash
ping6 <peer_ipv6>
telnet <peer_ipv6> 179
```

### Routes Not Propagating

**Check export filters**:
```bash
sudo birdc show route export peer_name
```

**Verify static routes**:
```bash
sudo birdc show route protocol static_routes
```

**Check kernel routing table**:
```bash
ip -6 route show
```

## Best Practices

1. **Test BIRD config syntax** before deploying:
   ```bash
   sudo bird -p -c /etc/bird/bird.conf
   ```

2. **Monitor BGP sessions** after changes:
   ```bash
   sudo birdc show protocols
   ```

3. **Keep WireGuard keys secure** in Ansible Vault

4. **Document peering arrangements** in comments

5. **Use BGP communities** for route tagging and filtering

6. **Set up monitoring** for tunnel and BGP session status

## Next Steps

- [Adding Services](adding-services.md) - Add new services
- [Common Tasks](common-tasks.md) - Day-to-day operations
- [Architecture](../reference/architecture.md) - Technical details
