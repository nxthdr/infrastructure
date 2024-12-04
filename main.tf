locals {
  network_dmz_ipv4_prefix = "172.18.0.0/16"
  network_dmz_ipv6_prefix = "2a06:de00:50:cafe:100::/80"

  network_backend_ipv4_prefix = "172.19.0.0/16"
  network_backend_ipv6_prefix = "2a06:de00:50:cafe:10::/80"
}

resource "docker_network" "dmz" {
  name = "dmz"
  driver = "bridge"
  ipv6 = true
  ipam_config {
    subnet = local.network_dmz_ipv4_prefix
    gateway = cidrhost(local.network_dmz_ipv4_prefix, 1)
  }
  ipam_config {
    subnet = local.network_dmz_ipv6_prefix
  }
}

resource "docker_network" "backend" {
  name = "backend"
  driver = "bridge"
  ipv6 = true
  ipam_config {
    subnet = local.network_backend_ipv4_prefix
    gateway = cidrhost(local.network_backend_ipv4_prefix, 1)
  }
  ipam_config {
    subnet = local.network_backend_ipv6_prefix
  }
}

# DMZ services
## Reverse Proxy
resource "docker_image" "caddy" {
  name = "caddy:2.9"
}

resource "docker_container" "proxy" {
  image = docker_image.caddy.image_id
  name  = "proxy"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  env = ["CADDY_ADMIN=[::]:2019"]
  user = "1000:1000"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.dmz.name
    ipv6_address = "2a06:de00:50:cafe:100::a"
  }
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::a"
  }
  volumes {
    container_path = "/etc/caddy/Caddyfile"
    host_path = "/home/matthieugouel/nxthdr/proxy/config/Caddyfile"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/matthieugouel/nxthdr/proxy/data"
  }
}

# `as215011.net` backend services
## as215011 Website
data "docker_registry_image" "website_nxthdr" {
  name = "ghcr.io/nxthdr/nxthdr.dev:main"
}

resource "docker_image" "website_nxthdr" {
  name          = data.docker_registry_image.website_nxthdr.name
  pull_triggers = [data.docker_registry_image.website_nxthdr.sha256_digest]
}

resource "docker_container" "website_as215011" {
  image = docker_image.website_nxthdr.image_id
  name  = "website_as215011"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  env = ["CADDY_ADMIN=[::]:2019"]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::10"
  }
}

## Geofeed
resource "docker_container" "geofeed" {
  image = docker_image.caddy.image_id
  name  = "geofeed"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  env = ["CADDY_ADMIN=[::]:2019"]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::11"
  }
  volumes {
    container_path = "/etc/caddy/Caddyfile"
    host_path = "/home/matthieugouel/nxthdr/geofeed/config/Caddyfile"
  }
  volumes {
    container_path = "/www/html"
    host_path = "/home/matthieugouel/nxthdr/geofeed/data/html"
  }
}

## Peers
data "docker_registry_image" "peers" {
  name = "ghcr.io/nxthdr/peers:main"
}

resource "docker_image" "peers" {
  name          = data.docker_registry_image.peers.name
  pull_triggers = [data.docker_registry_image.peers.sha256_digest]
}

resource "docker_container" "peers" {
  image = docker_image.peers.image_id
  name  = "peers"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::12"
  }
}

# `nxthdr.dev` backend services
## nxthdr Website
resource "docker_container" "website_nxthdr" {
  image = docker_image.website_nxthdr.image_id
  name  = "website_nxthdr"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  env = ["CADDY_ADMIN=[::]:2019"]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::100"
  }
}

## ClickHouse
resource "docker_image" "clickhouse" {
  name = "docker.io/clickhouse/clickhouse-server:24.11.1"
}

resource "docker_container" "clickhouse" {
  image = docker_image.clickhouse.image_id
  name  = "clickhouse"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1000:1000"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::101"
  }
  volumes {
    container_path = "/etc/clickhouse-server/config.d"
    host_path = "/home/matthieugouel/nxthdr/clickhouse/config/config.d"
  }
  volumes {
    container_path = "/etc/clickhouse-server/users.d"
    host_path = "/home/matthieugouel/nxthdr/clickhouse/config/users.d"
  }
  volumes {
    container_path = "/var/lib/clickhouse"
    host_path = "/home/matthieugouel/nxthdr/clickhouse/data"
  }
  capabilities {
    add = [ "SYS_NICE", "NET_ADMIN", "IPC_LOCK" ]
  }
  ulimit {
    name = "nofile"
    soft = 262144
    hard = 262144
  }
}

## Chproxy
resource "docker_image" "chproxy" {
  name = "ttl.sh/chproxy:1h"
}

resource "docker_container" "chproxy" {
  image = docker_image.chproxy.image_id
  name  = "chproxy"
  command = [
    "-config", "/config/config.yml",
    "-enableTCP6"
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::102"
  }
  volumes {
    container_path = "/config"
    host_path = "/home/matthieugouel/nxthdr/chproxy/config"
  }
}

## Redpanda
resource "docker_image" "redpanda" {
  name = "docker.vectorized.io/vectorized/redpanda:v24.2.9"
}

resource "docker_container" "redpanda" {
  image = docker_image.redpanda.image_id
  name  = "redpanda"
  command = [
    "redpanda", "start",
    "--overprovisioned",
    "--smp", "1",
    "--memory", "2G",
    "--reserve-memory", "200M",
    "--node-id", "0",
    "--check=false"
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1000:1000"
  network_mode = "bridge"
  # networks_advanced {
  #   name = docker_network.dmz.name
  #   ipv6_address = "2a06:de00:50:cafe:100::b"
  # }
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::103"
  }
  volumes {
    container_path = "/etc/redpanda"
    host_path = "/home/matthieugouel/nxthdr/redpanda/config"
  }
  volumes {
    container_path = "/var/lib/redpanda/data"
    host_path = "/home/matthieugouel/nxthdr/redpanda/data"
  }
}

## Prometheus
resource "docker_image" "prometheus" {
  name = "prom/prometheus:v3.0.1"
}

resource "docker_container" "prometheus" {
  image = docker_image.prometheus.image_id
  name  = "prometheus"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  command = [
    "--config.file=/config/prometheus.yml",
    "--web.external-url=https://prometheus.nxthdr.dev"
  ]
  user = "1000:1000"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::104"
  }
  volumes {
    container_path = "/config/prometheus.yml"
    host_path = "/home/matthieugouel/nxthdr/prometheus/config/prometheus.yml"
  }
  volumes {
    container_path = "/config/alerts.yml"
    host_path = "/home/matthieugouel/nxthdr/prometheus/config/alerts.yml"
  }
  volumes {
    container_path = "/prometheus"
    host_path = "/home/matthieugouel/nxthdr/prometheus/data"
  }
}

## Grafana
resource "docker_image" "grafana" {
  name = "grafana/grafana:11.3.2"
}

resource "docker_container" "grafana" {
  image = docker_image.grafana.image_id
  name  = "grafana"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1000:1000"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::105"
  }
  volumes {
    container_path = "/etc/grafana/grafana.ini"
    host_path = "/home/matthieugouel/nxthdr/grafana/config/grafana.ini"
  }
  volumes {
    container_path = "/var/lib/grafana"
    host_path = "/home/matthieugouel/nxthdr/grafana/data"
  }
}

## Alertmanager
resource "docker_image" "alertmanager" {
  name = "prom/alertmanager:v0.27.0"
}

resource "docker_container" "alertmanager" {
  image = docker_image.alertmanager.image_id
  name  = "alertmanager"
  command = [
    "--config.file=/config/alertmanager.yml",
    "--storage.path=/data"
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::106"
  }
  volumes {
    container_path = "/config/alertmanager.yml"
    host_path = "/home/matthieugouel/nxthdr/alertmanager/config/alertmanager.yml"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/matthieugouel/nxthdr/alertmanager/data"
  }
}

## Node Exporter
resource "docker_image" "node_exporter" {
  name = "prom/node-exporter:v1.8.2"
}

resource "docker_container" "node_exporter" {
  image = docker_image.node_exporter.image_id
  name  = "node_exporter"
  command = [
    "--path.procfs=/host/proc",
    "--path.rootfs=/rootfs",
    "--path.sysfs=/host/sys",
    "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1000:1000"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::107"
  }
  volumes {
    container_path = "/host/proc"
    host_path = "/proc"
    read_only = "true"
  }
  volumes {
    container_path = "/host/sys"
    host_path = "/sys"
    read_only = "true"
  }
    volumes {
    container_path = "/rootfs"
    host_path = "/"
    read_only = "true"
  }
}

## Cadvisor
resource "docker_image" "cadvisor" {
  name = "gcr.io/cadvisor/cadvisor:v0.51.0"
}

resource "docker_container" "cadvisor" {
  image = docker_image.cadvisor.image_id
  name  = "cadvisor"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  privileged = "true"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::108"
  }
  volumes {
    container_path = "/rootfs"
    host_path = "/"
    read_only = "true"
  }
  volumes {
    container_path = "/var/run"
    host_path = "/var/run"
    read_only = "true"
  }
  volumes {
    container_path = "/sys"
    host_path = "/sys"
    read_only = "true"
  }
  volumes {
    container_path = "/var/lib/docker"
    host_path = "/var/lib/docker"
    read_only = "true"
  }
  volumes {
    container_path = "/dev/disk"
    host_path = "/dev/disk"
    read_only = "true"
  }
}

## Loki
resource "docker_image" "loki" {
  name = "grafana/loki:3.3.0"
}

resource "docker_container" "loki" {
  image = docker_image.loki.image_id
  name  = "loki"
  command = [
    "-config.file=/config/loki.yml"
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1000:1000"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::109"
  }
  volumes {
    container_path = "/config/loki.yml"
    host_path = "/home/matthieugouel/nxthdr/loki/config/loki.yml"
  }
  volumes {
    container_path = "/loki"
    host_path = "/home/matthieugouel/nxthdr/loki/data"
  }
}

## Promtail
resource "docker_image" "promtail" {
  name = "grafana/promtail:3.3.0"
}

resource "docker_container" "promtail" {
  image = docker_image.promtail.image_id
  name  = "promtail"
  command = [
    "-config.file=/config/promtail.yml"
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  privileged = "true"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::110"
  }
  volumes {
    container_path = "/config/promtail.yml"
    host_path = "/home/matthieugouel/nxthdr/promtail/config/promtail.yml"
  }
  volumes {
    container_path = "/var/lib/docker/containers"
    host_path = "/var/lib/docker/containers"
    read_only = "true"
  }
}

## Redis
# resource "docker_image" "redis" {
#   name = "redis:7.4.1"
# }

# resource "docker_container" "redis" {
#   image = docker_image.redis.image_id
#   name  = "redis"
#   log_driver = "json-file"
#   log_opts = {
#     tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
#   }
#   user = "1000:1000"
#   network_mode = "bridge"
#   networks_advanced {
#     name = docker_network.backend.name
#     ipv6_address = "2a06:de00:50:cafe:10::111"
#   }
#   volumes {
#     container_path = "/data"
#     host_path = "/home/matthieugouel/nxthdr/redis/data"
#   }
# }

## Risotto
data "docker_registry_image" "risotto" {
  name = "ghcr.io/nxthdr/risotto:main"
}

resource "docker_image" "risotto" {
  name          = data.docker_registry_image.risotto.name
  pull_triggers = [data.docker_registry_image.risotto.sha256_digest]
}

resource "docker_container" "risotto" {
  image = docker_image.risotto.image_id
  name  = "risotto"
  command = [ "--config", "/config/risotto" ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.dmz.name
    ipv6_address = "2a06:de00:50:cafe:100::c"
  }
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::1000"
  }
  volumes {
    container_path = "/config/risotto.yml"
    host_path = "/home/matthieugouel/nxthdr/risotto/config/risotto.yml"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/matthieugouel/nxthdr/risotto/data"
  }
}

## chbot
data "docker_registry_image" "chbot" {
  name = "ghcr.io/nxthdr/chbot:main"
}

resource "docker_image" "chbot" {
  name          = data.docker_registry_image.chbot.name
  pull_triggers = [data.docker_registry_image.chbot.sha256_digest]
}

resource "docker_container" "chbot" {
  image = docker_image.chbot.image_id
  name  = "chbot"
  command = [
    "--url", "http://[2a06:de00:50:cafe:10::102]:9090",
    "--user", "read",
    "--password", "read",  # public read-only access
    "--output-limit", "20",
    "--token", var.chbot_discord_token
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::1001"
  }
}