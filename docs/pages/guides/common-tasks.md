# Common Tasks

## Container Management

### Update Container Configuration

1. Edit template: `templates/config/core/coreams01/{service}/config/{file}.j2`
2. Run: `make apply`
3. If needed: `docker restart {container}`

### Update Container Image

1. Edit `terraform/{hostname}.tf` - change image tag in `docker_image` resource
2. Run: `make apply`

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
