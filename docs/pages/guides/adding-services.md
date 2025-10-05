# Adding New Services

## Add to Core Server

1. **Create config directory**:
   ```bash
   mkdir -p templates/config/core/coreams01/{service}/config
   ```

2. **Add config files** (use `.j2` for templates):
   ```bash
   vim templates/config/core/coreams01/{service}/config/config.yml.j2
   ```

3. **Add Terraform resources** in `terraform/coreams01.tf`:
   ```hcl
   resource "docker_image" "service_name" {
     name = "image:tag"
     provider = docker.coreams01
   }

   resource "docker_container" "service_name" {
     image = docker_image.service_name.image_id
     name  = "service-name"
     provider = docker.coreams01
     restart = "unless-stopped"

     log_driver = "json-file"
     log_opts = { tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}" }
     dns = ["2a00:1098:2c::1", "2a00:1098:2b::1"]

     network_mode = "bridge"
     networks_advanced {
       name = docker_network.backend.name
       ipv6_address = "2a06:de00:50:cafe:10::XX"  # Choose unused IP
     }

     volumes {
       container_path = "/etc/service/config"
       host_path = "/home/nxthdr/service/config"
     }
   }
   ```

4. **Deploy**: `make apply`

## Add to IXP/VLT Servers

1. **Create shared config**:
   ```bash
   mkdir -p templates/config/ixp/{service}/config
   vim templates/config/ixp/{service}/config/config.yml.j2
   ```

2. **Update Terraform template** in `templates/terraform/ixp.tf.j2`:
   ```hcl
   resource "docker_image" "service_name" {
     name = "image:tag"
     provider = docker.{{ inventory_hostname }}
   }

   resource "docker_container" "service_name" {
     image = docker_image.service_name.image_id
     name  = "service-name"
     provider = docker.{{ inventory_hostname }}
     restart = "unless-stopped"
     # ... rest of config
   }
   ```

3. **Deploy**: `make apply` (deploys to all IXP servers)

## Expose via HTTPS

1. Add DMZ network in Terraform:
   ```hcl
   networks_advanced {
     name = docker_network.dmz.name
     ipv6_address = "2a06:de00:50:cafe:100::XX"
   }
   ```

2. Update `templates/config/core/coreams01/proxy/config/Caddyfile.j2`:
   ```
   service.nxthdr.dev {
       reverse_proxy [2a06:de00:50:cafe:100::XX]:port
       tls { dns cloudflare {env.CLOUDFLARE_API_TOKEN} }
   }
   ```

3. Deploy: `make apply`

## Add Secrets

1. Run: `make edit-secrets`
2. Add secrets:
   ```yaml
   service:
     api_key: "key"
   ```
3. Use in templates: `{{ secrets.service.api_key }}`

## Service Dependencies

Services on same network communicate by container name:
```yaml
host: clickhouse  # Container name
```

Optional Terraform dependency:
```hcl
depends_on = [docker_container.clickhouse]
```

## Persistent Data

Mount volume in Terraform:
```hcl
volumes {
  container_path = "/var/lib/service"
  host_path = "/home/nxthdr/service/data"
}
```

## Health Checks

```hcl
healthcheck {
  test = ["CMD", "curl", "-f", "http://localhost:port/health"]
  interval = "30s"
  timeout = "3s"
  retries = 3
}
```
## Resource Limits

```hcl
memory = 512  # MB
cpu_shares = 1024
```

## Add to Prometheus

Edit `templates/config/core/coreams01/prometheus/config/prometheus.yml.j2`:
```yaml
scrape_configs:
  - job_name: 'service'
    static_configs:
      - targets: ['service:port']
```

## Next Steps

- [Common Tasks](common-tasks.md) - Day-to-day operations
- [Network Configuration](network-configuration.md) - BIRD and WireGuard
- [Architecture](../reference/architecture.md) - Technical details
