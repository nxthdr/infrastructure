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
  name = "grafana/grafana:13.0.2"  # bump this tag to update
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

BIRD configs are Jinja2 templates under `templates/config/{group}/.../bird/`.

### Step 1: Edit the BIRD Template

```bash
# IXP host (per-host); or templates/config/vlt/bird/bird.conf.j2 for all VLT hosts
vim templates/config/ixp/ixpams01/bird/bird.conf.j2
```

### Step 2: Render and Sync

```bash
make sync-bird
```

This renders the templates and deploys the rendered config to the `ixp` and `vlt` groups. You'll be prompted for the BECOME password (sudo). `sync-bird` does **not** target the core server — core BIRD is applied manually.

### Step 3: Verify

BIRD reloads automatically. Check status:

```bash
ssh nxthdr@ams01.ixp.infra.nxthdr.dev
sudo birdc show status
```

## Common Commands Reference

See [Common Tasks](../guides/common-tasks.md) for the full command reference and day-to-day operations.

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
