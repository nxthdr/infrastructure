# nxthdr Infrastructure

Infrastructure as Code for the [nxthdr](https://nxthdr.dev) platform.

## Documentation

📚 **[Read the full documentation](https://nxthdr.github.io/infrastructure/)**

Quick links:
- [Getting Started](docs/pages/getting-started/overview.md)
- [Quick Start Guide](docs/pages/getting-started/quick-start.md)
- [Common Tasks](docs/pages/guides/common-tasks.md)
- [For AI Assistants](CLAUDE.md)

## Quick Start

```bash
# 1. Set up vault password
echo "YOUR_VAULT_PASSWORD" > .password

# 2. Deploy everything
make apply
```

## Main Commands

| Command | Description |
|---------|-------------|
| `make apply` | Full deployment (render + sync + terraform) |
| `make render` | Render templates only |
| `make sync-config` | Sync configs to servers |
| `make sync-bird` | Sync BIRD (BGP) configs |
| `make sync-wireguard` | Sync WireGuard (VPN) configs |
| `make edit-secrets` | Edit encrypted secrets |

## Technology Stack

- **Ansible** - Configuration management
- **Terraform** - Docker container orchestration
- **Jinja2** - Template rendering
- **Ansible Vault** - Secrets management
- **Docker** - Container runtime
- **BIRD** - BGP routing
- **WireGuard** - VPN tunneling

## Repository Structure

```
infrastructure/
├── inventory/          # Server definitions
├── templates/          # Jinja2 templates
│   ├── config/        # Docker container configs
│   └── terraform/     # Terraform templates
├── playbooks/         # Ansible automation
├── render/            # Python rendering scripts
├── secrets/           # Encrypted secrets
├── terraform/         # Terraform files
└── docs/              # Documentation (MkDocs)
```

## Server Provisioning

### VLT (Vultr) Servers - Fully Automated

For new probing servers on Vultr:

1. Add server to `inventory/inventory.yml`
2. Run `make vlt`

This automates everything: server creation, DNS, software installation, and configuration deployment.

### IXP Servers - Semi-Automated

For new IXP servers (manual provisioning):

1. Manually provision server at hosting provider
2. Manually create DNS records
3. Add server to `inventory/inventory.yml`
4. Run `make ixp`

This automates: software installation, BIRD/WireGuard config generation and deployment, Docker containers.

### Core Servers - Semi-Automated

For new core servers (manual provisioning):

1. Manually provision server
2. Manually create DNS records
3. Add server to `inventory/inventory.yml`
4. Run `make core`

This automates: software installation, BIRD/WireGuard config generation and deployment, Docker containers.

## Security

If you discover a security vulnerability, prefer email: [admin@nxthdr.dev](mailto:admin@nxthdr.dev)

## Contributing

Contributions are welcome! Please:

1. Read the [documentation](https://nxthdr.github.io/infrastructure/)
2. Open an issue to discuss your changes
3. Submit a pull request

## License

See [LICENSE](LICENSE) file for details.
