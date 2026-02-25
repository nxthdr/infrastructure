locals {
  network_dmz_ipv4_prefix = "172.18.0.0/16"
  network_dmz_ipv6_prefix = "2a06:de00:50:cafe:100::/80"

  network_backend_ipv4_prefix = "172.19.0.0/16"
  network_backend_ipv6_prefix = "2a06:de00:50:cafe:10::/80"
}

resource "docker_network" "dmz" {
  name = "dmz"
  provider = docker.coreams01
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
  provider = docker.coreams01
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

resource "docker_network" "dmz_ipv4" {
  name = "dmz-ipv4"
  provider = docker.coreams01
  driver = "bridge"
  ipv6 = true
}

# IPv6 Reverse Proxy
resource "docker_image" "caddy" {
  name = "caddy:2.11"
  provider = docker.coreams01
}

resource "docker_container" "proxy" {
  image = docker_image.caddy.image_id
  name  = "proxy"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  env = [ "CADDY_ADMIN=[::]:2019" ]
  user = "1001:1001"
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
    host_path = "/home/nxthdr/proxy/config/Caddyfile"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/nxthdr/proxy/data"
  }
}

# IPv4 Reverse Proxy
resource "docker_container" "proxy_ipv4" {
  image = docker_image.caddy.image_id
  name  = "proxy-ipv4"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  env = [ "CADDY_ADMIN=[::]:2019" ]
  user = "1001:1001"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.dmz_ipv4.name
  }
  networks_advanced {
    name = docker_network.backend.name
  }
  ports {
    internal = 80
    external = 80
    protocol = "tcp"
  }
  ports {
    internal = 443
    external = 443
    protocol = "tcp"
  }
  volumes {
    container_path = "/etc/caddy/Caddyfile"
    host_path = "/home/nxthdr/proxy-ipv4/config/Caddyfile"
  }
  volumes {
    container_path = "/data/caddy/certificates"
    host_path = "/home/nxthdr/proxy/data/caddy/certificates"
  }
}

# Main Website
data "docker_registry_image" "nxthdr_dev" {
  name = "ghcr.io/nxthdr/nxthdr.dev:main"
  provider = docker.coreams01
}

resource "docker_image" "nxthdr_dev" {
  name = data.docker_registry_image.nxthdr_dev.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.nxthdr_dev.sha256_digest ]
}

resource "docker_container" "nxthdr_dev" {
  image = docker_image.nxthdr_dev.image_id
  name  = "nxthdr_dev"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  env = [ "CADDY_ADMIN=[::]:2019" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::100"
  }
}

# ClickHouse
resource "docker_image" "clickhouse" {
  name = "docker.io/clickhouse/clickhouse-server:25.12.6"
  provider = docker.coreams01
}

resource "docker_container" "clickhouse" {
  image = docker_image.clickhouse.image_id
  name  = "clickhouse"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1001:1001"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::101"
  }
  volumes {
    container_path = "/etc/clickhouse-server/config.d"
    host_path = "/home/nxthdr/clickhouse/config/config.d"
  }
  volumes {
    container_path = "/etc/clickhouse-server/users.d"
    host_path = "/home/nxthdr/clickhouse/config/users.d"
  }
  volumes {
    container_path = "/var/lib/clickhouse"
    host_path = "/home/nxthdr/clickhouse/data"
  }
  capabilities {
    add = [ "CAP_SYS_NICE", "CAP_NET_ADMIN", "CAP_IPC_LOCK" ]
  }
  ulimit {
    name = "nofile"
    soft = 262144
    hard = 262144
  }
}

# Chproxy
resource "docker_image" "chproxy" {
  name = "contentsquareplatform/chproxy:v1.30.0"
  provider = docker.coreams01
}

resource "docker_container" "chproxy" {
  image = docker_image.chproxy.image_id
  name  = "chproxy"
  provider = docker.coreams01
  command = [
    "-config", "/config/config.yml",
    "-enableTCP6"
  ]
  restart = "unless-stopped"
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
    host_path = "/home/nxthdr/chproxy/config"
  }
}

# Redpanda
resource "docker_image" "redpanda" {
  name = "redpandadata/redpanda:v25.3.8"
  provider = docker.coreams01
}

resource "docker_container" "redpanda" {
  image = docker_image.redpanda.image_id
  name  = "redpanda"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1001:1001"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.dmz.name
    ipv6_address = "2a06:de00:50:cafe:100::b"
  }
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::103"
  }
  volumes {
    container_path = "/entrypoint.sh"
    host_path = "/home/nxthdr/redpanda/config/entrypoint.sh"
  }
  volumes {
    container_path = "/etc/redpanda"
    host_path = "/home/nxthdr/redpanda/config"
  }
  volumes {
    container_path = "/var/lib/redpanda/data"
    host_path = "/home/nxthdr/redpanda/data"
  }
}

# Prometheus
resource "docker_image" "prometheus" {
  name = "prom/prometheus:v3.9.1"
  provider = docker.coreams01
}

resource "docker_container" "prometheus" {
  image = docker_image.prometheus.image_id
  name  = "prometheus"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  command = [
    "--config.file=/config/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=30d",  # 30 days retention
    "--web.enable-remote-write-receiver",
    "--web.external-url=https://prometheus.nxthdr.dev",
    "--web.config.file=/config/web.yml",
  ]
  user = "1001:1001"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::104"
  }
  volumes {
    container_path = "/config/prometheus.yml"
    host_path = "/home/nxthdr/prometheus/config/prometheus.yml"
  }
  volumes {
    container_path = "/config/alerts.yml"
    host_path = "/home/nxthdr/prometheus/config/alerts.yml"
  }
  volumes {
    container_path = "/config/web.yml"
    host_path = "/home/nxthdr/prometheus/config/web.yml"
  }
  volumes {
    container_path = "/prometheus"
    host_path = "/home/nxthdr/prometheus/data"
  }
}

# Grafana
resource "docker_image" "grafana" {
  name = "grafana/grafana:12.4.0"
  provider = docker.coreams01
}

resource "docker_container" "grafana" {
  image = docker_image.grafana.image_id
  name  = "grafana"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1001:1001"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::105"
  }
  env = [
    "GF_INSTALL_PLUGINS=grafana-clickhouse-datasource",
  ]
  volumes {
    container_path = "/etc/grafana/grafana.ini"
    host_path = "/home/nxthdr/grafana/config/grafana.ini"
  }
  volumes {
    container_path = "/etc/grafana/provisioning/datasources/datasources.yml"
    host_path = "/home/nxthdr/grafana/config/datasources.yml"
  }
  volumes {
    container_path = "/etc/grafana/provisioning/dashboards/dashboards.yml"
    host_path = "/home/nxthdr/grafana/config/dashboards.yml"
  }
  volumes {
    container_path = "/var/lib/grafana/dashboards"
    host_path = "/home/nxthdr/grafana/config/dashboards"
  }
  volumes {
    container_path = "/var/log/grafana"
    host_path = "/home/nxthdr/grafana/data"
  }
}

# Alertmanager
resource "docker_image" "alertmanager" {
  name = "prom/alertmanager:v0.31.1"
  provider = docker.coreams01
}

resource "docker_container" "alertmanager" {
  image = docker_image.alertmanager.image_id
  name  = "alertmanager"
  provider = docker.coreams01
  command = [
    "--config.file=/config/alertmanager.yml",
    "--storage.path=/data"
  ]
  restart = "unless-stopped"
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
    host_path = "/home/nxthdr/alertmanager/config/alertmanager.yml"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/nxthdr/alertmanager/data"
  }
}

# Node Exporter
resource "docker_image" "node_exporter" {
  name = "prom/node-exporter:v1.10.2"
  provider = docker.coreams01
}

resource "docker_container" "node_exporter" {
  image = docker_image.node_exporter.image_id
  name  = "node_exporter"
  provider = docker.coreams01
  command = [
    "--path.procfs=/host/proc",
    "--path.rootfs=/rootfs",
    "--path.sysfs=/host/sys",
    "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user = "1001:1001"
  pid_mode = "host"
  hostname = "coreams01"
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

# Cadvisor
resource "docker_image" "cadvisor" {
  name = "gcr.io/cadvisor/cadvisor:v0.55.1"
  provider = docker.coreams01
}

resource "docker_container" "cadvisor" {
  image = docker_image.cadvisor.image_id
  name  = "cadvisor"
  provider = docker.coreams01
  restart = "unless-stopped"
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

# Loki
resource "docker_image" "loki" {
  name = "grafana/loki:3.6.7"
  provider = docker.coreams01
}

resource "docker_container" "loki" {
  image = docker_image.loki.image_id
  name  = "loki"
  provider = docker.coreams01
  command = [
    "-config.file=/config/loki.yml"
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::109"
  }
  volumes {
    container_path = "/config/loki.yml"
    host_path = "/home/nxthdr/loki/config/loki.yml"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/nxthdr/loki/data"
  }
}

# Alloy
resource "docker_image" "alloy" {
  name = "grafana/alloy:v1.13.2"
  provider = docker.coreams01
}

resource "docker_container" "alloy" {
  image = docker_image.alloy.image_id
  name  = "alloy"
  provider = docker.coreams01
  command = [
    "run", "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy"
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::110"
  }
  ports {
    internal = 514
    external = 514
    protocol = "udp"
  }
  ports {
    internal = 601
    external = 601
    protocol = "tcp"
  }
  volumes {
    container_path = "/etc/alloy/config.alloy"
    host_path = "/home/nxthdr/alloy/config/config.alloy"
  }
  volumes {
    container_path = "/var/lib/alloy/data"
    host_path = "/home/nxthdr/alloy/data"
  }
  volumes {
    container_path = "/var/lib/docker/containers"
    host_path = "/var/lib/docker/containers"
    read_only = "true"
  }
}

# Risotto
data "docker_registry_image" "risotto" {
  name = "ghcr.io/nxthdr/risotto:main"
  provider = docker.coreams01
}

resource "docker_image" "risotto" {
  name = data.docker_registry_image.risotto.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.risotto.sha256_digest ]
}

resource "docker_container" "risotto" {
  image = docker_image.risotto.image_id
  name  = "risotto"
  provider = docker.coreams01
  command = [
    "--bmp-address", "[::]:4000",
    "--metrics-address", "[2a06:de00:50:cafe:10::112]:8080",
    "--kafka-brokers", "[2a06:de00:50:cafe:10::103]:9092",
    "--kafka-topic", "risotto-updates",
    "--curation-state-path", "/data/state.bin",
    "--curation-state-interval", "10",
  ]
  restart = "unless-stopped"
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
    ipv6_address = "2a06:de00:50:cafe:10::112"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/nxthdr/risotto/data"
  }
}

# Pesto
data "docker_registry_image" "pesto" {
  name = "ghcr.io/nxthdr/pesto:main"
  provider = docker.coreams01
}

resource "docker_image" "pesto" {
  name = data.docker_registry_image.pesto.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.pesto.sha256_digest ]
}

resource "docker_container" "pesto" {
  image = docker_image.pesto.image_id
  name  = "pesto"
  provider = docker.coreams01
  command = [
    "--sflow-address", "[2a06:de00:50:cafe:100::d]:6343",
    "--kafka-brokers", "[2a06:de00:50:cafe:10::103]:9092",
    "--kafka-topic", "pesto-sflow",
    "--metrics-address", "[2a06:de00:50:cafe:10::113]:8080",
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.dmz.name
    ipv6_address = "2a06:de00:50:cafe:100::d"
  }
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::113"
  }
}

# Saimiris Gateway
data "docker_registry_image" "saimiris_gateway" {
  name = "ghcr.io/nxthdr/saimiris-gateway:main"
  provider = docker.coreams01
}

resource "docker_image" "saimiris_gateway" {
  name = data.docker_registry_image.saimiris_gateway.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.saimiris_gateway.sha256_digest ]
}

resource "docker_container" "saimiris_gateway" {
  image = docker_image.saimiris_gateway.image_id
  name  = "saimiris_gateway"
  provider = docker.coreams01
  command = [
    "--address", "[2a06:de00:50:cafe:10::114]:8080",
    "--agent-key", var.saimiris_agent_key,
    "--kafka-brokers", "redpanda.nxthdr.dev:9092",
    "--kafka-topic", "saimiris-probes",
    "--kafka-auth-protocol", "SASL_PLAINTEXT",
    "--kafka-sasl-username", var.saimiris_redpanda_username,
    "--kafka-sasl-password", var.saimiris_redpanda_password,
    "--kafka-sasl-mechanism", "SCRAM-SHA-512",
    "--auth0-jwks-uri", "https://dev-zk3qmxl3o0m8lvk3.eu.auth0.com/.well-known/jwks.json",
    "--auth0-issuer", "https://dev-zk3qmxl3o0m8lvk3.eu.auth0.com/",
    "--database-url", "postgresql://[2a06:de00:50:cafe:10::116]:5432/saimiris?user=${var.postgresql_username}&password=${var.postgresql_password}&sslmode=disable",
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::114"
  }
}

# Peerlab Gateway
data "docker_registry_image" "peerlab_gateway" {
  name = "ghcr.io/nxthdr/peerlab-gateway:main"
  provider = docker.coreams01
}

resource "docker_image" "peerlab_gateway" {
  name = data.docker_registry_image.peerlab_gateway.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.peerlab_gateway.sha256_digest ]
}

resource "docker_container" "peerlab_gateway" {
  image = docker_image.peerlab_gateway.image_id
  name  = "peerlab_gateway"
  provider = docker.coreams01
  command = [
    "--address", "[2a06:de00:50:cafe:10::118]:8080",
    "--database-url", "postgresql://[2a06:de00:50:cafe:10::116]:5432/peerlab_gateway?user=${var.postgresql_username}&password=${var.postgresql_password}&sslmode=disable",
    "--prefix-pool-file", "/config/prefixes.txt",
    "--asn-pool-start", "65000",
    "--asn-pool-end", "65999",
    "--auth0-jwks-uri", "https://dev-zk3qmxl3o0m8lvk3.eu.auth0.com/.well-known/jwks.json",
    "--auth0-issuer", "https://dev-zk3qmxl3o0m8lvk3.eu.auth0.com/",
    "--agent-key", var.peerlab_agent_key,
    "--auth0-management-api", "https://dev-zk3qmxl3o0m8lvk3.eu.auth0.com",
    "--auth0-m2m-app-id", var.peerlab_m2m_app_id,
    "--auth0-m2m-app-secret", var.peerlab_m2m_app_secret,
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::118"
  }
  volumes {
    container_path = "/config/prefixes.txt"
    host_path = "/home/nxthdr/peerlab-gateway/config/prefixes.txt"
  }
}

# nxthdr blog
data "docker_registry_image" "blog" {
  name = "ghcr.io/nxthdr/blog:main"
  provider = docker.coreams01
}

resource "docker_image" "blog" {
  name = data.docker_registry_image.blog.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.blog.sha256_digest ]
}

resource "docker_container" "blog" {
  image = docker_image.blog.image_id
  name  = "blog"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  env = [ "CADDY_ADMIN=[::]:2019" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::115"
  }
}

# PostgreSQL
resource "docker_image" "postgresql" {
  name = "postgres:17"
  provider = docker.coreams01
}

resource "docker_container" "postgresql" {
  image = docker_image.postgresql.image_id
  name  = "postgresql"
  provider = docker.coreams01
  command = [
    "postgres",
    "-c", "config_file=/etc/postgresql/postgresql.conf",
    "-c", "hba_file=/etc/postgresql/pg_hba.conf",
    "-c", "ident_file=/etc/postgresql/pg_ident.conf"
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::116"
  }
  env = [
    "POSTGRES_DB=saimiris",
    "POSTGRES_USER=${var.postgresql_username}",
    "POSTGRES_PASSWORD=${var.postgresql_password}",
    "PGDATA=/var/lib/postgresql/pgdata"
  ]
  volumes {
    container_path = "/var/lib/postgresql"
    host_path = "/home/nxthdr/postgresql/data"
  }
  volumes {
    container_path = "/etc/postgresql/postgresql.conf"
    host_path = "/home/nxthdr/postgresql/config/postgresql.conf"
  }
  volumes {
    container_path = "/etc/postgresql/pg_hba.conf"
    host_path = "/home/nxthdr/postgresql/config/pg_hba.conf"
  }
  volumes {
    container_path = "/etc/postgresql/pg_ident.conf"
    host_path = "/home/nxthdr/postgresql/config/pg_ident.conf"
  }
}

# nxthdr docs
data "docker_registry_image" "docs" {
  name = "ghcr.io/nxthdr/docs:main"
  provider = docker.coreams01
}

resource "docker_image" "docs" {
  name = data.docker_registry_image.docs.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.docs.sha256_digest ]
}

resource "docker_container" "docs" {
  image = docker_image.docs.image_id
  name  = "docs"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  env = [ "CADDY_ADMIN=[::]:2019" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::117"
  }
}

# chbot
data "docker_registry_image" "chbot" {
  name = "ghcr.io/nxthdr/chbot:main"
  provider = docker.coreams01
}

resource "docker_image" "chbot" {
  name = data.docker_registry_image.chbot.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.chbot.sha256_digest ]
}

resource "docker_container" "chbot" {
  image = docker_image.chbot.image_id
  name  = "chbot"
  provider = docker.coreams01
  command = [
    "--url", "http://[2a06:de00:50:cafe:10::102]:9090",
    "--user", "read",
    "--password", "read",  # public read-only access
    "--output-limit", "20",
    "--token", var.chbot_discord_token
  ]
  restart = "unless-stopped"
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

# Geofeed
resource "docker_container" "geofeed" {
  image = docker_image.caddy.image_id
  name  = "geofeed"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  env = ["CADDY_ADMIN=[::]:2019"]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::1003"
  }
  volumes {
    container_path = "/etc/caddy/Caddyfile"
    host_path = "/home/nxthdr/geofeed/config/Caddyfile"
  }
  volumes {
    container_path = "/www/html"
    host_path = "/home/nxthdr/geofeed/data/html"
  }
}

# Peers
data "docker_registry_image" "peers" {
  name = "ghcr.io/nxthdr/peers:main"
  provider = docker.coreams01
}

resource "docker_image" "peers" {
  name = data.docker_registry_image.peers.name
  provider = docker.coreams01
  pull_triggers = [ data.docker_registry_image.peers.sha256_digest ]
}

resource "docker_container" "peers" {
  image = docker_image.peers.image_id
  name  = "peers"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::1004"
  }
}

# Headscale
resource "docker_image" "headscale" {
  name = "ghcr.io/juanfont/headscale:v0.28"
  provider = docker.coreams01
}

resource "docker_container" "headscale" {
  image = docker_image.headscale.image_id
  name  = "headscale"
  provider = docker.coreams01
  command = [
    "serve"
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::1005"
  }
  volumes {
    container_path = "/etc/headscale"
    host_path = "/home/nxthdr/headscale/config"
  }
  volumes {
    container_path = "/var/lib/headscale"
    host_path = "/home/nxthdr/headscale/data"
  }
}

# Headplane
resource "docker_image" "headplane" {
  name = "ghcr.io/tale/headplane:0.6.1"
  provider = docker.coreams01
}

resource "docker_container" "headplane" {
  image = docker_image.headplane.image_id
  name  = "headplane"
  provider = docker.coreams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::1006"
  }
  volumes {
    container_path = "/etc/headplane/config.yaml"
    host_path = "/home/nxthdr/headplane/config/config.yaml"
  }
  volumes {
    container_path = "/var/lib/headplane"
    host_path = "/home/nxthdr/headplane/data"
  }
  volumes {
    container_path = "/etc/headscale"
    host_path = "/home/nxthdr/headscale/config"
    read_only = "true"
  }
}

# Routinator
resource "docker_image" "routinator" {
  name = "nlnetlabs/routinator:v0.15.1"
  provider = docker.coreams01
}

# Routinator
resource "docker_container" "routinator" {
  image = docker_image.routinator.image_id
  name  = "routinator"
  provider = docker.coreams01
  command = [
    "server",
    "--http", "[::]:8323",
    "--rtr", "[::]:3323"
  ]
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.dmz.name
    ipv6_address = "2a06:de00:50:cafe:100::e"
  }
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::1007"
  }
  volumes {
    container_path = "/home/routinator/.routinator.conf"
    host_path = "/home/nxthdr/routinator/config/routinator.conf"
  }
  volumes {
    container_path = "/var/lib/routinator"
    host_path = "/home/nxthdr/routinator/data"
  }
}

