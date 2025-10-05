# Quick Start Guide

This guide walks you through making your first infrastructure change.

## Understanding the Workflow

The main deployment command is:

```bash
make apply
```

This executes three steps:

1. **Render** - Generate configs from Jinja2 templates
2. **Sync** - Copy configs to servers via Ansible
3. **Apply** - Deploy containers via Terraform

## Example: Update a Container Configuration

Let's update the Grafana configuration as an example.

### Step 1: Locate the Template

Configuration templates are in `templates/config/{group}/{hostname}/{service}/`:

```bash
# For Grafana on coreams01
ls templates/config/core/coreams01/grafana/
```

### Step 2: Edit the Template

Edit a configuration file:

```bash
# Example: Edit Grafana config
vim templates/config/core/coreams01/grafana/config/grafana.ini.j2
```

Make your changes. Jinja2 variables are available:

- `{{ inventory_hostname }}` - Current host (e.g., `coreams01`)
- `{{ secrets.grafana_admin_password }}` - From secrets.yml
- Any variables from `inventory/inventory.yml`

### Step 3: Render and Preview

Render the templates to see the output:

```bash
make render
```

Check the rendered file:

```bash
cat .rendered/coreams01/grafana/config/grafana.ini
```

!!! tip "Rendered Directory"
    The `.rendered/` directory contains plaintext secrets and is gitignored. Never commit it!

### Step 4: Deploy

Deploy the changes:

```bash
make apply
```

This will:

1. ✅ Render templates
2. ✅ Sync to remote server
3. ✅ Apply Terraform changes

### Step 5: Verify

If Terraform didn't detect changes (config-only update), restart the container:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
docker restart grafana
```

## Example: Update a Container Image

Let's update a Docker image version.

### Step 1: Edit Terraform File

```bash
vim terraform/coreams01.tf
```

Find the image resource and update the version:

```hcl
resource "docker_image" "grafana" {
  name = "grafana/grafana:10.2.0"  # Update this version
  provider = docker.coreams01
}
```

### Step 2: Apply Changes

```bash
make apply
```

Terraform will detect the image change and recreate the container.

### Step 3: Verify

Check the container is running:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
docker ps | grep grafana
```

## Example: Update BIRD Configuration

Network configurations are in `networks/{hostname}/`.

### Step 1: Edit BIRD Config

```bash
vim networks/coreams01/bird/bird.conf
```

### Step 2: Sync Configuration

```bash
make sync-bird
```

You'll be prompted for the BECOME password (sudo password).

### Step 3: Verify

BIRD will automatically reload. Check status:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
sudo birdc show status
```

## Common Commands Reference

| Task | Command | Requires Sudo |
|------|---------|---------------|
| Full deployment | `make apply` | No |
| Render only | `make render` | No |
| Sync configs | `make sync-config` | No |
| Update BIRD | `make sync-bird` | Yes |
| Update WireGuard | `make sync-wireguard` | Yes |
| Edit secrets | `make edit-secrets` | No |

## Best Practices

- **Test on one host first** for multi-host changes
- **Review Terraform plan** if needed: `terraform -chdir=./terraform plan`
- **Never commit**: `.password`, `.rendered/`, `terraform/terraform.tfvars`

## Troubleshooting

### Rendering Fails

```
Error rendering template: Undefined variable
```

**Solution**: Check that all variables used in templates exist in:
- `inventory/inventory.yml`
- `secrets/secrets.yml`

### Ansible Sync Fails

```
UNREACHABLE! => {"changed": false, "msg": "Failed to connect"}
```

**Solution**: Verify SSH access to the server.

### Container Not Updated

After `make apply`, container still uses old config.

**Solution**: Manually restart the container:

```bash
ssh nxthdr@ams01.core.infra.nxthdr.dev
docker restart <container_name>
```

## Next Steps

- [Common Tasks](../guides/common-tasks.md) - Day-to-day operations
- [Network Configuration](../guides/network-configuration.md) - BIRD and WireGuard
- [Adding Services](../guides/adding-services.md) - Add new services
- [Architecture](../reference/architecture.md) - Technical details
