# VLT Server Terraform Module

This module provisions a Vultr server and associated Porkbun DNS records for NXTHDR VLT infrastructure.

## Features

- Creates a Vultr compute instance with IPv4 and IPv6
- Automatically creates Porkbun A and AAAA DNS records
- Configures SSH keys for access
- Outputs all necessary information for configuration management

## Usage

This module is called automatically by the `vlt-infrastructure.tf` file, which reads from `inventory.yml`.

### Manual Usage (if needed)

```hcl
module "vlt_server" {
  source = "./modules/vlt-server"

  hostname     = "vltatl01"
  region       = "atl"
  ssh_key_ids  = ["abc123"]

  # Optional overrides
  plan         = "vc2-1c-1gb"
  os_id        = 1743  # Ubuntu 22.04 LTS
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| hostname | Short hostname (e.g., vltatl01) | string | - | yes |
| region | Vultr region code (e.g., atl, cdg, fra) | string | - | yes |
| ssh_key_ids | List of SSH key IDs to add to the server | list(string) | - | yes |
| plan | Vultr plan ID | string | "vc2-1c-1gb" | no |
| os_id | Vultr OS ID | number | 2625 (Debian 13 trixie) | no |
| enable_ipv6 | Enable IPv6 on the server | bool | true | no |
| porkbun_domain | Base domain for DNS records | string | "nxthdr.dev" | no |
| dns_subdomain | DNS subdomain pattern | string | "vlt.infra" | no |

## Outputs

| Name | Description |
|------|-------------|
| id | Vultr instance ID |
| hostname | Server hostname |
| fqdn | Fully qualified domain name |
| main_ip | Primary IPv4 address |
| v6_main_ip | Primary IPv6 address |
| v6_network | IPv6 network |
| v6_network_size | IPv6 network size |
| region | Vultr region |
| status | Server status |

## DNS Records

The module automatically creates:
- **A record**: `{location}.vlt.infra.nxthdr.dev` → IPv4
- **AAAA record**: `{location}.vlt.infra.nxthdr.dev` → IPv6

Example: `atl01.vlt.infra.nxthdr.dev`

## Notes

- The module extracts the location code from the hostname (e.g., `vltatl01` → `atl`)
- SSH keys are not updated after initial creation to prevent server recreation
- The server is created with Debian 13 x64 by default
- Automatic backups are disabled (`backups = "disabled"`)
