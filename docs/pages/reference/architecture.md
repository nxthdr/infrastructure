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
- **Data Collection**: Risotto (BMP collector), Pesto (sFlow collector), Saimiris Gateway
- **Application Services**: Geofeed, CHProxy, and other nxthdr services

### IXP Servers

**Purpose**: BGP peering at Internet Exchange Points

**Locations**: Amsterdam (2 servers), Frankfurt (1 server)
**Provider**: iFog
**IXPs**: FogIXP, FranceIX, NL-IX

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

### BGP Monitoring Pipeline

```
┌─────────────┐
│ BIRD Routers│
│ (BMP)       │
└──────┬──────┘
       │ BMP messages
       ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Risotto    │─────►│  Redpanda   │─────►│ ClickHouse  │
│ (Collector) │      │  (Kafka)    │      │ (bmp db)    │
└─────────────┘      └─────────────┘      └──────┬──────┘
                                                  │
                                                  │ Query
                                                  ▼
                                           ┌─────────────┐
                                           │   Grafana   │
                                           └─────────────┘
```

### Flow Monitoring Pipeline

```
┌─────────────┐
│  Network    │
│  Devices    │
│  (sFlow)    │
└──────┬──────┘
       │ sFlow datagrams
       ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Pesto     │─────►│  Redpanda   │─────►│ ClickHouse  │
│ (Collector) │      │  (Kafka)    │      │ (flows db)  │
└─────────────┘      └─────────────┘      └──────┬──────┘
                                                  │
                                                  │ Query
                                                  ▼
                                           ┌─────────────┐
                                           │   Grafana   │
                                           └─────────────┘
```

**Note**: Only IPv6 flow samples are processed. Counter samples are filtered at the producer level.

### Active Measurement Pipeline

!!! note "Active measurements are bursty, not continuous"
    The `saimiris.replies` pipeline only flows when `saimprowler` dispatches a probe batch — a systemd timer on `coreams01` fires every **30 minutes** (`OnUnitActiveSec=30min`). Between bursts the table receives no inserts; this is expected. Freshness/health checks must use a **≥1-hour** window to detect real outages, not 5 minutes.

```
┌─────────────┐
│ VLT Servers │
│ (Saimiris)  │
└──────┬──────┘
       │ Probe replies
       ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  Saimiris   │─────►│  Redpanda   │─────►│ ClickHouse  │
│  Gateway    │      │  (Kafka)    │      │(saimiris db)│
└─────────────┘      └─────────────┘      └──────┬──────┘
                                                  │
                                                  │ Query
                                                  ▼
                                           ┌─────────────┐
                                           │   Grafana   │
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

## ClickHouse Database Architecture

### Database Overview

ClickHouse stores all time-series data in three separate databases:

**BMP Database** (`bmp`):
- Stores BGP routing updates from BMP protocol
- Kafka topic: `risotto-updates`
- Schema: Cap'n Proto (`update.capnp:Update`)
- TTL: 7 days
- Key tables: `from_kafka`, `updates`, `from_kafka_mv`

**Flows Database** (`flows`):
- Stores network flow data from sFlow collectors
- Kafka topic: `pesto-sflow`
- Schema: Cap'n Proto (`sflow:SFlowFlowRecord`)
- TTL: 7 days
- Key tables: `from_kafka`, `records`, `from_kafka_mv`
- Note: IPv6 only, flow samples only (no counter samples)

**Saimiris Database** (`saimiris`):
- Stores active measurement probe replies
- Kafka topic: `saimiris-replies`
- Schema: Cap'n Proto (`reply.capnp:Reply`)
- TTL: 7 days
- Key tables: `from_kafka`, `replies`, `from_kafka_mv`

### Table Architecture Pattern

All databases follow the same pattern:

1. **Kafka Engine Table** (`from_kafka`):
   - Consumes messages from Redpanda/Kafka
   - Uses Cap'n Proto format for efficient serialization
   - No data persistence (streaming only)

2. **MergeTree Table** (`updates`/`records`/`replies`):
   - Persistent storage with optimized ordering
   - Partitioned by date for efficient queries
   - Automatic TTL-based deletion

3. **Materialized View** (`from_kafka_mv`):
   - Transforms and loads data from Kafka to MergeTree
   - Handles field name conversion (camelCase → snake_case)
   - Adds timestamps and metadata

### Schema Definitions

Database schemas are maintained in `clickhouse-tables/` directory:
- `clickhouse-tables/bmp/bmp.sql`
- `clickhouse-tables/flows/flows.sql`
- `clickhouse-tables/saimiris/saimiris.sql`

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
2. Generates Terraform wiring files from inventory:
   - `terraform/docker-providers.tf` (docker provider blocks per host)
   - `terraform/ixp.tf` (IXP module calls)
   - `terraform/vlt.tf` (VLT module calls + vlt_servers locals)
3. Renders `templates/terraform/terraform.tfvars.j2` → `terraform/terraform.tfvars`

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

### Authentication (MAS)

User authentication for the Matrix homeserver (Synapse) is delegated to the **Matrix Authentication Service (MAS)** at `auth.nxthdr.dev`, which federates to Auth0 for credentials (MSC3861 native OIDC):

```
Client ──OIDC──► MAS (auth.nxthdr.dev) ──OIDC upstream──► Auth0
                   └──MSC3861──► Synapse (matrix.nxthdr.dev)
```

MAS owns all user auth, access-token issuance/introspection, and registration. Room state, messages, and federation remain in Synapse; appservices (Hookshot) use appservice tokens and bypass MAS. See the [MAS Migration](mas-migration.md) runbook for migration details and admin operations.

## Deployment Architecture

### Terraform State

**Current Setup**:
- State (`terraform.tfstate`) is gitignored — stored locally on the deployment machine
- No remote backend
- Manual coordination required for concurrent changes

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
2. **Local Terraform state**: No remote backend — not ideal for team collaboration
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
- All services expose a `/metrics` endpoint
- Default scrape interval: 30s (some jobs scrape at 60s)
- Retention: 30 days (`--storage.tsdb.retention.time=30d`)

**Exporters**:
- cAdvisor: Container metrics
- Node Exporter: System metrics
- bird_exporter: BGP / BIRD metrics (IXP and VLT)

### Log Aggregation

**Loki Pipeline**:
- Docker logs forwarded to Loki
- Structured logging with labels
- Retention: 7 days

### Alerting

Alerts flow through **Prometheus → Alertmanager → Hookshot webhook → Matrix room**:

- **Prometheus** evaluates alert rules and fires to Alertmanager
- **Alertmanager** deduplicates/groups and forwards to a Hookshot generic webhook
- **Hookshot** bridges the payload into the Matrix alert room

Alertmanager exposes a UI (HTTP basic auth) at `https://alertmanager.nxthdr.dev` for creating and expiring silences. See the [Alert Silences](alert-silences.md) runbook for the full procedure, and [Hookshot Transformation](hookshot-transformation.md) for how alert formatting is configured.

## Next Steps

- [Common Tasks](../guides/common-tasks.md) - Day-to-day operations
- [Network Configuration](../guides/network-configuration.md) - BIRD and WireGuard
- [Alert Silences](alert-silences.md) - Silencing alerts
- [MAS Migration](mas-migration.md) - Matrix authentication migration runbook
