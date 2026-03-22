# Common Tasks

## Container Management

### Update Container Configuration

1. Edit template: `templates/config/core/coreams01/{service}/config/{file}.j2`
2. Run: `make apply`
3. If needed: `docker restart {container}`

### Update Container Image

1. For core: edit `terraform/coreams01.tf`
2. For IXP: edit `terraform/modules/ixp/main.tf` (applies to all IXP servers)
3. For VLT: edit `terraform/modules/vlt-containers/main.tf` (applies to all VLT servers)
4. Run: `make apply`

## Network Configuration

### Update BIRD

1. Edit: `networks/{hostname}/bird/bird.conf`
2. Run: `make sync-bird` (requires sudo password)
3. Verify: `sudo birdc show status`

### Update WireGuard

1. Edit: `networks/{hostname}/wireguard/{interface}.conf`
2. Run: `make sync-wireguard` (requires sudo password)
3. Verify: `sudo wg show`

## Secrets Management

### Edit Secrets

```bash
make edit-secrets
```

Add secrets in YAML format, use in templates as `{{ secrets.key_name }}`.

### Rotate a Secret

1. Run: `make edit-secrets`
2. Change the value
3. Run: `make apply`
4. Restart affected containers

## Template Management

### Add Configuration File

1. Create: `templates/config/{group}/{hostname}/{service}/config/file.j2`
2. Run: `make apply`

### Test Rendering

```bash
make render
cat .rendered/{hostname}/{service}/config/{file}
```

### Available Variables

- `{{ inventory_hostname }}` - Host name
- `{{ ansible_host }}` - Server FQDN
- `{{ secrets.key }}` - From secrets.yml
- Group/host vars from inventory.yml

## VLT Server Management

### Add a VLT Server

1. Add host to `inventory/inventory.yml` under the `vlt` group:
   ```yaml
   vltsgp01:
     ansible_host: sgp01.vlt.infra.nxthdr.dev
     uniprobe0: 2a0e:97c0:8a5::/48
   ```
   - Hostname: `vlt{region}{index}` (3-char Vultr region code)
   - `uniprobe0`: next available `/48` from `2a0e:97c0:8a0::/44`
2. Run:
   ```bash
   make render-terraform && terraform -chdir=./terraform init && make vlt
   ```

### Remove VLT Server(s)

1. Remove the host entry (or entries) from `inventory/inventory.yml`
2. Run:
   ```bash
   make vlt-prune
   ```

This compares inventory with Terraform state, shows which servers will be destroyed, and asks for confirmation before proceeding. It handles Docker state cleanup, Terraform re-rendering, and Vultr VM destruction automatically.

## Deployment

### Full Deployment

```bash
make apply
```

### Config Only

```bash
make sync-config
# Then restart containers manually
```

### Preview Changes

```bash
terraform -chdir=./terraform plan
```

## Next Steps

- [Network Configuration](network-configuration.md) - BIRD and WireGuard setup
- [Adding Services](adding-services.md) - Add new services
- [Architecture](../reference/architecture.md) - Technical details
