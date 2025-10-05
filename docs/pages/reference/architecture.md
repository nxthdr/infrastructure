# Architecture Reference

This page provides detailed technical information about the infrastructure architecture.

## System Components

### Core Server (coreams01)

**Provider**: Scaleway Dedibox  
**Location**: Amsterdam, Netherlands  
**Role**: Central hub for all nxthdr services

**Service Categories**:
- **Databases**: ClickHouse (time-series), PostgreSQL (relational)
- **Messaging**: Redpanda (Kafka-compatible streaming)
- **Observability**: Prometheus (metrics), Loki (logs), Grafana (dashboards), Alertmanager
- **Networking**: Headscale (Tailscale), Caddy (HTTPS proxy)
- **Application Services**: Various nxthdr-specific services

### IXP Servers

**Purpose**: BGP peering at Internet Exchange Points

**Locations**: Amsterdam (2 servers), Frankfurt (1 server)  
**Provider**: iFog  
**IXPs**: NL-IX, LocIX, FogIXP

**Service Categories**:
- **Routing**: BIRD (BGP daemon)
- **Connectivity**: WireGuard (VPN to core)
- **Monitoring**: Metrics and flow collection

### Probing Servers (VLT)

**Purpose**: Active measurement infrastructure

**Locations**: Multiple global locations  
**Provider**: Vultr  
**Prefix**: `2a0e:97c0:8a0::/44` (sub-prefixes per location)

**Service Categories**:
- **Probing**: Saimiris (active measurement agent)
- **Monitoring**: Metrics and flow collection

## Network Architecture

### IP Addressing

**Core Server Networks**:

```
DMZ Network (IPv6):     2a06:de00:50:cafe:100::/80
DMZ Network (IPv4):     172.18.0.0/16
Backend Network (IPv6): 2a06:de00:50:cafe:10::/80
Backend Network (IPv4): 172.19.0.0/16
```

**Public Prefixes**:

```
Core Services:   2a06:de00:50::/44 (announced via AS215011)
Probing:         2a0e:97c0:8a0::/44 (announced via AS215011)
```

### Docker Networks

#### Backend Network

Internal network for service-to-service communication.

**Characteristics**:
- Not accessible from Internet
- IPv4 and IPv6 enabled
- Services communicate by container name (Docker DNS)

**IP Range**: `2a06:de00:50:cafe:10::/80`

#### DMZ Network

Internet-facing network for public services.

**Characteristics**:
- Accessible from Internet via proxy
- IPv6 only
- Requires firewall rule: `ip6tables -I DOCKER-USER -d 2a06:de00:50:cafe:100::/80 -j ACCEPT`

**IP Range**: `2a06:de00:50:cafe:100::/80`

#### DMZ-IPv4 Network

IPv4-only network for IPv4 proxy.

**Purpose**: Provide IPv4 access to IPv6-only services

### BGP Routing

```
┌─────────────┐
│   IXP       │
│   Peers     │
└──────┬──────┘
       │ BGP
       │
┌──────▼──────┐      WireGuard      ┌─────────────┐
│  IXP Server │◄────────────────────►│ Core Server │
│  (BIRD)     │      Tunnel          │  (BIRD)     │
└─────────────┘                      └─────────────┘
       │                                    │
       │ Announces                          │ Announces
       │ 2a06:de00:50::/44                 │ to IXP servers
       │                                    │
       ▼                                    ▼
   Internet                            Services
```

**Routing Flow**:
1. Core server announces `2a06:de00:50::/44` to IXP servers via WireGuard
2. IXP servers announce to Internet via BGP at IXPs
3. Traffic destined for nxthdr services routes through IXP servers
4. IXP servers forward to core via WireGuard tunnel

## Data Flow

### Measurement Data Pipeline

```
┌─────────────┐
│ VLT Servers │
│ (Saimiris)  │
└──────┬──────┘
       │ Sends probes
       │ via Redpanda
       ▼
┌─────────────┐      ┌─────────────┐
│  Redpanda   │─────►│ ClickHouse  │
│  (Kafka)    │      │ (Storage)   │
└─────────────┘      └──────┬──────┘
                            │
                            │ Query
                            ▼
                     ┌─────────────┐
                     │   Grafana   │
                     │ (Visualize) │
                     └─────────────┘
```

### Observability Pipeline

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Services   │─────►│ Prometheus  │─────►│   Grafana   │
│  (Metrics)  │      │ (Scrape)    │      │  (Display)  │
└─────────────┘      └─────────────┘      └─────────────┘

┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Services   │─────►│    Loki     │─────►│   Grafana   │
│  (Logs)     │      │ (Aggregate) │      │  (Display)  │
└─────────────┘      └─────────────┘      └─────────────┘
```

## Infrastructure as Code Architecture

### Template Rendering Pipeline

```
┌─────────────────┐
│ inventory.yml   │
│ secrets.yml     │
│ templates/      │
└────────┬────────┘
         │
         │ render_config.py
         │ render_terraform.py
         ▼
┌─────────────────┐
│  .rendered/     │  (gitignored)
│  terraform/     │
└────────┬────────┘
         │
         │ Ansible sync
         ▼
┌─────────────────┐
│ Remote Servers  │
│ /home/nxthdr/   │
└────────┬────────┘
         │
         │ Terraform apply
         ▼
┌─────────────────┐
│ Docker          │
│ Containers      │
└─────────────────┘
```

### Rendering Process

**render_config.py**:
1. Loads `inventory/inventory.yml`
2. Decrypts `secrets/secrets.yml` with vault password
3. For each host:
   - Loads group vars
   - Loads host vars
   - Merges with secrets
   - Renders templates from `templates/config/{group}/{hostname}/`
   - Outputs to `.rendered/{hostname}/`

**render_terraform.py**:
1. Loads inventory and secrets
2. Renders `templates/terraform/providers.tf.j2` → `terraform/providers.tf`
3. Renders `templates/terraform/terraform.tfvars.j2` → `terraform/terraform.tfvars`
4. For IXP/VLT hosts:
   - Renders `templates/terraform/{group}.tf.j2` → `terraform/{hostname}.tf`

## Security Architecture

### Secrets Management

**Ansible Vault**:
- All secrets encrypted in `secrets/secrets.yml`
- AES256 encryption
- Password stored in `.password` (gitignored)
- Decrypted during rendering, never committed in plaintext

**Secret Types**:
- Database passwords
- API tokens (Cloudflare, etc.)
- WireGuard private keys
- Service credentials

### Network Security

**Firewall**:
- Docker networks isolated by default
- Manual firewall rules for DMZ access
- WireGuard tunnels for IXP ↔ Core communication

**Access Control**:
- SSH key-based authentication
- No password authentication
- Sudo required for system-level changes

### SSL/TLS

**Certificate Management**:
- Automatic via Let's Encrypt
- DNS-01 challenge with Cloudflare
- Caddy handles renewal automatically
- Certificates synced to IPv4 proxy manually

## Deployment Architecture

### Terraform State

**Current Setup**:
- State stored in git repository
- No remote backend
- Manual coordination required

**Providers**:
- Docker provider for container management
- Connects to Docker daemon via SSH

### Ansible Inventory

**Structure**:
```yaml
{group}:
  hosts:
    {hostname}:
      ansible_host: {fqdn}
      {host_vars}
  vars:
    ansible_user: nxthdr
    {group_vars}
```

**Groups**:
- `core`: Core servers
- `ixp`: IXP servers
- `vlt`: Probing servers

## Scalability Considerations

### Current Limitations

1. **Single core server**: No redundancy
2. **Terraform state in git**: Not suitable for team collaboration
3. **Manual certificate sync**: Requires manual intervention
4. **IPv6-only core**: Requires IPv4 proxy for dual-stack

### Future Improvements

1. **Core redundancy**: Multiple core servers with load balancing
2. **Remote Terraform state**: Use S3/GCS backend
3. **Automated certificate sync**: Sync via Ansible playbook
4. **Dual-stack core**: Native IPv4 support

## Monitoring Architecture

### Metrics Collection

**Prometheus Scraping**:
- All services expose `/metrics` endpoint
- Prometheus scrapes every 15s
- Retention: 15 days

**Exporters**:
- cAdvisor: Container metrics
- Node Exporter: System metrics (if installed)
- Custom exporters: Service-specific metrics

### Log Aggregation

**Loki Pipeline**:
- Docker logs forwarded to Loki
- Structured logging with labels
- Retention: 30 days

### Alerting

**Alertmanager**:
- Receives alerts from Prometheus
- Routes to appropriate channels
- Deduplication and grouping

## Next Steps

- [Directory Structure](directory-structure.md) - Detailed file organization
- [Makefile Commands](makefile.md) - Command reference
- [Secrets Management](secrets.md) - Working with secrets
- [Troubleshooting](troubleshooting.md) - Common issues
