# Infrastructure Overview

The nxthdr infrastructure is designed to support Internet research and education through a globally distributed network of servers running specialized services.

## Architecture

The infrastructure consists of three main components:

### 1. Core Services (coreams01)

A bare-metal Scaleway Dedibox server in Amsterdam running all essential services:

- **Databases**: ClickHouse, PostgreSQL
- **Messaging**: Redpanda (Kafka-compatible)
- **Observability**: Prometheus, Loki, Grafana
- **Networking**: Headscale (Tailscale coordination server)
- **Proxying**: Caddy (HTTPS reverse proxy)
- **Other services**: Geofeed, CHProxy, Alertmanager

All services run in Docker containers managed by Terraform.

### 2. IXP Servers

Servers connected to Internet Exchange Points (IXPs) for BGP peering:

- Run BIRD routing daemon for BGP
- Connected to core via WireGuard tunnels
- Announce AS215011 routes
- Enable Internet-scale routing experiments

### 3. Probing Servers (VLT)

Vultr instances for active measurements:

- Run Saimiris probing agents
- Distributed globally (Atlanta, Paris)
- Advertise unicast/anycast prefixes
- Send measurement data to core services

## Infrastructure as Code

Everything is managed as code:

```
infrastructure/
├── inventory/          # Server definitions
├── templates/          # Jinja2 templates
│   ├── config/        # Docker container configs
│   └── terraform/     # Terraform templates
├── networks/          # BIRD & WireGuard configs
├── playbooks/         # Ansible automation
├── render/            # Python rendering scripts
├── secrets/           # Encrypted secrets (Ansible Vault)
└── terraform/         # Generated Terraform files
```

## Deployment Workflow

The main deployment workflow follows three steps:

1. **Render** - Generate configs from templates with secrets
2. **Sync** - Copy configs to remote servers via Ansible
3. **Apply** - Deploy containers via Terraform

This is automated through the `make apply` command.

## Network Architecture

### Docker Networks

**Core server** uses two Docker networks:

- **backend** - Internal network for service-to-service communication
- **dmz** - Internet-facing network for public services
- **dmz-ipv4** - IPv4-only network for IPv4 proxy

### BGP Routing

- IXP servers peer with other ASes at exchange points
- Core services reachable via `2a06:de00:50::/44`
- Probing infrastructure uses `2a0e:97c0:8a0::/44`
- IPv6-only with IPv4 proxy for dual-stack access

### VPN Tunnels

WireGuard tunnels connect:

- IXP servers ↔ Core server
- Enables routing of nxthdr traffic through AS215011

## Special Characteristics

### Template Groups

- **core** - Host-specific templates (each host has unique config)
- **ixp** - Shared templates (all IXP servers use same config)
- **vlt** - Shared templates (all VLT servers use same config)

### Secrets Management

- All secrets encrypted with Ansible Vault
- Vault password stored in `.password` file (gitignored)
- Secrets injected during template rendering
- Rendered files never committed to git

### State Management

- Terraform state committed to git (not recommended for production)
- No remote state backend currently configured
- Manual coordination required for concurrent changes

## Next Steps

- [Setup your environment](setup.md) to start working with the infrastructure
- [Quick Start guide](quick-start.md) to make your first deployment
- [Common Tasks](../guides/common-tasks.md) for day-to-day operations
