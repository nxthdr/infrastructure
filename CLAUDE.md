# Infrastructure Repository Guide for Claude

This document provides context for AI assistants working with the nxthdr infrastructure repository.

## Repository Overview

This repository manages infrastructure for [nxthdr](https://nxthdr.dev) using:
- **Ansible** for configuration management and file synchronization
- **Terraform** for Docker container orchestration
- **Jinja2** templates for dynamic configuration rendering
- **Ansible Vault** for secrets management

## Data Pipeline Architecture

The infrastructure supports three main data pipelines:

### 1. BGP Monitoring (BMP)
- **Service**: Risotto (BMP collector)
- **Database**: `bmp` in ClickHouse
- **Data Flow**: BIRD routers → Risotto → Redpanda (Kafka) → ClickHouse
- **Schema**: Cap'n Proto format (`update.capnp:Update`)
- **Purpose**: Collect and store BGP routing updates from peering sessions

### 2. Flow Monitoring (sFlow)
- **Service**: Pesto (sFlow collector)
- **Database**: `flows` in ClickHouse
- **Data Flow**: Network devices → Pesto → Redpanda (Kafka) → ClickHouse
- **Schema**: Cap'n Proto format (`sflow:SFlowFlowRecord`)
- **Purpose**: Collect and analyze network flow data (IPv6 only)
- **Note**: Only flow samples are processed (counter samples filtered out)

### 3. Active Measurements
- **Service**: Saimiris (probing agent)
- **Database**: `saimiris` in ClickHouse
- **Data Flow**: Saimiris agents → Redpanda (Kafka) → ClickHouse
- **Schema**: Cap'n Proto format (`reply.capnp:Reply`)
- **Purpose**: Active network measurements (traceroute, ping, etc.)

## Server Inventory

The infrastructure consists of four server groups defined in `inventory/inventory.yml`:

### Core Servers
- `coreams01` - Main server (Scaleway, Amsterdam)
- Runs all core services: Grafana, Prometheus, ClickHouse, PostgreSQL, Redpanda, Headscale, etc.

### IXP Servers
- `ixpams01` - iFog, Amsterdam (NL-IX)
- `ixpams02` - iFog, Amsterdam
- `ixpfra01` - iFog, Frankfurt (LocIX, FogIXP)
- `ixpcdg01` - FranceIX, Paris
- `ixpcdg02` - FranceIX, Paris

Run monitoring and BGP routing

### VLT (Probing) Servers
- `vltatl01` - Vultr, Atlanta
- `vltcdg01` - Vultr, Paris

Run Saimiris probing infrastructure

### Special Groups
- `ixp` and `vlt` groups use shared templates (same config for all hosts in group)
- `core` group uses host-specific templates

### SSH Access

All servers are accessible via SSH as the `nxthdr` user. The FQDNs follow the pattern `{location}.{group}.infra.nxthdr.dev`.

| Host | SSH Command |
|------|-------------|
| coreams01 | `ssh nxthdr@ams01.core.infra.nxthdr.dev` |
| ixpams01 | `ssh nxthdr@ams01.ixp.infra.nxthdr.dev` |
| ixpams02 | `ssh nxthdr@ams02.ixp.infra.nxthdr.dev` |
| ixpfra01 | `ssh nxthdr@fra01.ixp.infra.nxthdr.dev` |
| ixpcdg01 | `ssh nxthdr@cdg01.ixp.infra.nxthdr.dev` |
| ixpcdg02 | `ssh nxthdr@cdg02.ixp.infra.nxthdr.dev` |
| vltatl01 | `ssh nxthdr@atl01.vlt.infra.nxthdr.dev` |
| vltcdg01 | `ssh nxthdr@cdg01.vlt.infra.nxthdr.dev` |

The exact `ansible_host` values are defined in `inventory/inventory.yml`.

## Main Workflow: `make apply`

The primary deployment command is `make apply`, which executes three sequential steps:

### 1. Render Configuration (`make render`)
Runs two Python scripts using `uv`:
- `render/render_config.py` - Renders Docker container configurations from Jinja2 templates
- `render/render_terraform.py` - Renders Terraform wiring from inventory and secrets

**Process:**
- Reads `inventory/inventory.yml` for server definitions
- Decrypts `secrets/secrets.yml` using vault password from `.password` file
- Renders Jinja2 templates from `templates/config/` → `.rendered/` directory
- Generates Terraform wiring files from inventory:
  - `terraform/docker-providers.tf` (docker provider blocks per host)
  - `terraform/ixp.tf` (IXP module calls)
  - `terraform/vlt.tf` (VLT module calls + vlt_servers locals)
- Renders `templates/terraform/terraform.tfvars.j2` → `terraform/terraform.tfvars`
- `.rendered/` and `terraform/terraform.tfvars` contain plaintext secrets (gitignored)

**Inventory as source of truth:** adding or removing an IXP/VLT server only requires editing `inventory/inventory.yml`. The wiring files are regenerated automatically by `make render-terraform`.

**Template Structure:**
- `templates/config/core/coreams01/` - Host-specific configs for core server
- `templates/config/ixp/` - Shared configs for all IXP servers
- `templates/config/vlt/` - Shared configs for all VLT servers
- `templates/config/shared/` - Common configs across all servers

### 2. Sync Configuration (`make sync-config`)
Runs Ansible playbook: `playbooks/sync-config.yml`
- Uses `ansible.posix.synchronize` (rsync) to copy `.rendered/{hostname}/` → `/home/nxthdr/` on remote servers
- Targets: core, ixp, vlt groups
- No sudo required (runs as `nxthdr` user)

### 3. Apply Terraform (`terraform apply`)
- Executes `terraform -chdir=./terraform apply -auto-approve`
- Creates/updates Docker networks and containers
- Uses Docker provider to connect to remote servers

## Network Configuration Management

### BIRD (BGP Routing)
**Command:** `make sync-bird`

**Process:**
- Runs `playbooks/sync-bird.yml` with sudo (requires BECOME password)
- Copies BIRD configs from `networks/{hostname}/bird/` → `/etc/bird/`
- Reloads BIRD service on: core, ixpfra01, vlt servers
- Configs are NOT templated (static files in `networks/` directory)

**Files:**
- `networks/{hostname}/bird/bird.conf` - Main BIRD configuration
- `networks/{hostname}/bird/peerlab.conf` - Optional peerlab config
- `templates/config/shared/bird/bird.service` - Systemd service file

### WireGuard (VPN)
**Command:** `make sync-wireguard`

**Process:**
- Runs `playbooks/sync-wireguard.yml` with sudo (requires BECOME password)
- Templates configs from `networks/{hostname}/wireguard/` → `/etc/wireguard/`
- Restarts `wg-quick@wg0` and `wg-quick@wg1` services
- Targets: core, ixp groups

## Certificate Management

**Process:**
- `proxy` (IPv6) container generates Let's Encrypt certificates via Caddy
- Certificates are automatically available to both proxy containers

**Workflow for new proxied services:**
1. Update proxy configuration in templates
2. Run `make apply` - deploys config and generates certificates automatically

## Secrets Management

**Vault File:** `secrets/secrets.yml` (encrypted with Ansible Vault)

**Commands:**
- `make edit-secrets` - Edit encrypted secrets file
- Requires `.password` file in repo root (gitignored)

**Setup:**
```bash
echo "<VAULT_PASSWORD>" > .password
```

## Common Tasks

### Update Container Configuration
1. Edit template in `templates/config/{group}/{hostname}/{service}/`
2. Run `make apply`
3. If Terraform didn't change, manually restart: `docker restart <container>`

### Update Container Image Version
1. For core: edit `terraform/coreams01.tf` directly
2. For IXP: edit `terraform/modules/ixp/main.tf` (applies to all IXP servers)
3. For VLT: edit `terraform/modules/vlt-containers/main.tf` (applies to all VLT servers)
4. Run `make apply`

Renovate can update image versions directly in the module files.

### Update BIRD Configuration
1. Edit `networks/{hostname}/bird/bird.conf`
2. Run `make sync-bird` (requires sudo password)

### Update WireGuard Configuration
1. Edit `networks/{hostname}/wireguard/*.conf`
2. Run `make sync-wireguard` (requires sudo password)

### Add New Service to Core Server
1. Create config directory: `templates/config/core/coreams01/{service}/`
2. Add Jinja2 templates (`.j2` extension) or static files
3. Add Terraform resources in `terraform/coreams01.tf`:
   - `docker_image` resource
   - `docker_container` resource
   - Network attachments, volumes, environment variables
4. Run `make apply`

### Add New IXP Server
1. Add host to `inventory/inventory.yml` under the `ixp` group
2. Add network configs in `networks/{hostname}/`
3. Run `terraform -chdir=./terraform init` then `make apply`

The provider block, module call, and config rendering are all generated automatically from inventory.

### Add New VLT Server
1. Add host to `inventory/inventory.yml` under the `vlt` group (include `uniprobe0` and `ansible_host`)
2. Add network configs in `networks/{hostname}/`
3. Run `terraform -chdir=./terraform init` then `make apply`

The provider block, module call, VLT server entry, and config rendering are all generated automatically from inventory.

## ClickHouse Databases

The infrastructure uses ClickHouse for storing time-series data. Database schemas are defined in `clickhouse-tables/`:

### BMP Database (`bmp`)
**Purpose**: Store BGP routing updates from BMP (BGP Monitoring Protocol)

**Tables**:
- `from_kafka` - Kafka engine table consuming from `risotto-updates` topic
- `updates` - MergeTree table storing processed BGP updates
- `from_kafka_mv` - Materialized view transforming Kafka data

**Key Fields**: router address, peer address, prefix, AS path, BGP attributes, timestamps

**TTL**: 7 days

### Flows Database (`flows`)
**Purpose**: Store network flow data from sFlow collectors

**Tables**:
- `from_kafka` - Kafka engine table consuming from `pesto-sflow` topic
- `records` - MergeTree table storing flow records
- `from_kafka_mv` - Materialized view transforming Kafka data

**Key Fields**: source/destination IPs, ports, protocol, packet length, sampling rate

**TTL**: 7 days

**Note**: Only IPv6 flow samples are processed (counter samples filtered at producer)

### Saimiris Database (`saimiris`)
**Purpose**: Store active measurement results from probing agents

**Tables**:
- `from_kafka` - Kafka engine table consuming from `saimiris-replies` topic
- `replies` - MergeTree table storing probe replies
- `from_kafka_mv` - Materialized view transforming Kafka data

**Key Fields**: agent ID, probe/reply addresses, TTL, ICMP type/code, MPLS labels, RTT

**TTL**: 7 days

## Directory Structure

```
infrastructure/
├── .password              # Vault password (gitignored)
├── .rendered/             # Rendered configs with secrets (gitignored)
├── Makefile               # Main automation commands
├── inventory/
│   └── inventory.yml      # Server inventory and variables
├── secrets/
│   └── secrets.yml        # Encrypted secrets (Ansible Vault)
├── render/                # Python rendering scripts
│   ├── render_config.py   # Renders Docker configs
│   └── render_terraform.py # Renders Terraform files
├── clickhouse-tables/     # ClickHouse database schemas
│   ├── bmp/               # BGP monitoring database
│   ├── flows/             # Flow monitoring database
│   └── saimiris/          # Active measurements database
├── templates/
│   ├── config/            # Jinja2 templates for configs
│   │   ├── core/          # Core server configs
│   │   ├── ixp/           # Shared IXP configs
│   │   ├── vlt/           # Shared VLT configs
│   │   └── shared/        # Common configs
│   └── terraform/         # Jinja2 template for tfvars
│       └── terraform.tfvars.j2
├── terraform/             # Terraform configuration
│   ├── coreams01.tf       # Core server resources (static)
│   ├── providers.tf       # Provider requirements and non-docker providers (static)
│   ├── docker-providers.tf # Docker provider blocks (generated from inventory)
│   ├── ixp.tf             # IXP module calls (generated from inventory)
│   ├── vlt.tf             # VLT module calls + locals (generated from inventory)
│   ├── vlt-infrastructure.tf # Vultr servers and DNS for VLT (static)
│   ├── terraform.tfvars   # Rendered from secrets (gitignored)
│   └── modules/
│       ├── ixp/           # Shared IXP container definitions
│       ├── vlt-containers/ # Shared VLT container definitions
│       └── vlt-server/    # Vultr server provisioning
├── networks/              # Network configurations (BIRD, WireGuard)
│   ├── coreams01/
│   │   ├── bird/
│   │   └── wireguard/
│   ├── ixpams01/
│   └── ...
├── playbooks/             # Ansible playbooks
│   ├── sync-config.yml    # Sync Docker configs
│   ├── sync-bird.yml      # Sync BIRD configs
│   ├── sync-wireguard.yml # Sync WireGuard configs
│   └── install-*.yml      # Provisioning playbooks
└── docs/
    └── README.md          # Detailed documentation
```

## Important Notes

### File Rendering Rules
- Files with `.j2` extension are rendered as Jinja2 templates
- Shell scripts (`.sh`) automatically get executable permissions
- Non-template files are copied as-is

### Template Context Variables
Available in Jinja2 templates:
- `inventory_hostname` - Current host name (e.g., `coreams01`)
- Group vars from `inventory.yml`
- Host-specific vars from `inventory.yml`
- All secrets from `secrets/secrets.yml`

### Terraform State

- `terraform.tfstate` is git ignored (not committed)
- State managed locally on deployment machine

### Manual Configuration
Some tasks require manual intervention:
- **Grafana admin password:** `docker exec -ti grafana grafana cli admin reset-admin-password <PASSWORD>`
- **Docker firewall rules:** `ip6tables -I DOCKER-USER -d 2a06:de00:50:cafe:100::/80 -j ACCEPT`

## Troubleshooting

### Configuration not applied
- Check if Terraform detected changes: `terraform -chdir=./terraform plan`
- If no changes, manually restart container: `docker restart <container>`

### Secrets decryption fails
- Verify `.password` file exists and contains correct password
- Test with: `make edit-secrets`

### Ansible connection fails
- Verify SSH access: `ssh nxthdr@{hostname}.infra.nxthdr.dev`
- Check inventory file for correct `ansible_host`

### Rendering fails
- Check for undefined variables in templates
- Verify secrets file contains required keys
- Review error output from `render_config.py` or `render_terraform.py`

## Best Practices

1. **Review changes:** Check what will change before applying
2. **Review Terraform plan:** Use `terraform -chdir=./terraform plan` if needed
3. **Backup before major changes:** Terraform state is in git, but configs are not
4. **Use descriptive commit messages:** Infrastructure changes should be well-documented
5. **Test on single host first:** For multi-host changes, test on one server before rolling out
6. **Keep secrets secure:** Never commit `.password` or `.rendered/` directory
7. **Document manual steps:** Update this file when adding new manual configuration requirements

## Quick Reference

| Task | Command | Requires Sudo |
|------|---------|---------------|
| Full deployment | `make apply` | No |
| Render configs | `make render` | No |
| Sync configs | `make sync-config` | No |
| Update BIRD | `make sync-bird` | Yes |
| Update WireGuard | `make sync-wireguard` | Yes |
| Edit secrets | `make edit-secrets` | No |
| Destroy infrastructure | `make destroy` | No |
| Restart container | `docker restart <name>` | On remote host |
