# Infrastructure Documentation

Welcome to the **nxthdr infrastructure** documentation. This repository manages the infrastructure for [nxthdr](https://nxthdr.dev) using Infrastructure as Code principles.

## What is this?

This repository contains all the configuration, automation, and documentation needed to deploy and manage the nxthdr platform infrastructure, including:

- **Core services** - Grafana, Prometheus, ClickHouse, PostgreSQL, Redpanda, and more
- **IXP servers** - BGP routing and peering infrastructure
- **Probing servers** - Active measurement infrastructure
- **Network configuration** - BIRD (BGP) and WireGuard (VPN) configurations

## Technology Stack

- **[Ansible](https://www.ansible.com/)** - Configuration management and file synchronization
- **[Terraform](https://www.terraform.io/)** - Docker container orchestration
- **[Jinja2](https://jinja.palletsprojects.com/)** - Template rendering
- **[Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/)** - Secrets management
- **[Docker](https://www.docker.com/)** - Container runtime
- **[BIRD](https://bird.network.cz/)** - BGP routing daemon
- **[WireGuard](https://www.wireguard.com/)** - VPN tunneling

## Quick Links

- [Getting Started](getting-started/overview.md) - Learn about the infrastructure architecture
- [Setup](getting-started/setup.md) - Set up your local environment
- [Quick Start](getting-started/quick-start.md) - Deploy your first change
- [Common Tasks](guides/common-tasks.md) - Frequently performed operations
- [Troubleshooting](reference/troubleshooting.md) - Common issues and solutions

## Server Inventory

### Core Servers
- **coreams01** - Scaleway Dedibox, Amsterdam
  - All core services (databases, observability, messaging)

### IXP Servers
- **ixpams01** - iFog, Amsterdam (NL-IX)
- **ixpams02** - iFog, Amsterdam
- **ixpfra01** - iFog, Frankfurt (LocIX, FogIXP)
- **ixpcdg01** - FranceIX
- **ixpcdg02** - FranceIX

### Probing Servers
- **vltatl01** - Vultr, Atlanta
- **vltcdg01** - Vultr, Paris

## Contributing

This infrastructure is managed as code and is open source. If you find issues or have suggestions:

1. Open an issue on [GitHub](https://github.com/nxthdr/infrastructure/issues)
2. Submit a pull request with improvements
3. Contact us at [admin@nxthdr.dev](mailto:admin@nxthdr.dev)

## Security

If you discover a security vulnerability:

- For security issues, prefer email: [admin@nxthdr.dev](mailto:admin@nxthdr.dev)
- Or open an issue on [GitHub](https://github.com/nxthdr/infrastructure/issues)
