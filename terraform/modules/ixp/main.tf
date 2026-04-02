resource "docker_network" "backend" {
  name   = "backend"
  driver = "bridge"
  ipv6   = true
  ipam_config {
    subnet  = "172.18.0.0/16"
    gateway = "172.18.0.1"
  }
  ipam_config {
    subnet  = "fdf5:d891:ede::/64"
    gateway = "fdf5:d891:ede::1"
  }
}

# Alloy
resource "docker_image" "alloy" {
  name = "grafana/alloy:v1.15.0"
}

resource "docker_container" "alloy" {
  image   = docker_image.alloy.image_id
  name    = "alloy"
  command = [
    "run", "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy"
  ]
  restart    = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns          = ["2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1"]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
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
    host_path      = "/home/nxthdr/alloy/config/config.alloy"
  }
  volumes {
    container_path = "/var/lib/alloy/data"
    host_path      = "/home/nxthdr/alloy/data"
  }
  volumes {
    container_path = "/var/lib/docker/containers"
    host_path      = "/var/lib/docker/containers"
    read_only      = "true"
  }
}

# Node Exporter
resource "docker_image" "node_exporter" {
  name = "prom/node-exporter:v1.10.2"
}

resource "docker_container" "node_exporter" {
  image   = docker_image.node_exporter.image_id
  name    = "node_exporter"
  command = [
    "--path.procfs=/host/proc",
    "--path.rootfs=/rootfs",
    "--path.sysfs=/host/sys",
    "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)",
    "--collector.systemd",
    "--collector.systemd.unit-include=peerlab-bird-config.service"
  ]
  restart    = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  user         = "1000:1000"
  pid_mode     = "host"
  hostname     = var.hostname
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
  }
  volumes {
    container_path = "/host/proc"
    host_path      = "/proc"
    read_only      = true
  }
  volumes {
    container_path = "/host/sys"
    host_path      = "/sys"
    read_only      = true
  }
  volumes {
    container_path = "/rootfs"
    host_path      = "/"
    read_only      = true
  }
  volumes {
    container_path = "/run/dbus/system_bus_socket"
    host_path      = "/run/dbus/system_bus_socket"
    read_only      = true
  }
}

# Cadvisor
resource "docker_image" "cadvisor" {
  name = "gcr.io/cadvisor/cadvisor:v0.55.1"
}

resource "docker_container" "cadvisor" {
  image      = docker_image.cadvisor.image_id
  name       = "cadvisor"
  restart    = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  privileged   = true
  network_mode = "bridge"
  command = [
    "--housekeeping_interval=30s",
    "--docker_only=true",
  ]
  networks_advanced {
    name = docker_network.backend.name
  }
  volumes {
    container_path = "/rootfs"
    host_path      = "/"
    read_only      = true
  }
  volumes {
    container_path = "/var/run"
    host_path      = "/var/run"
    read_only      = true
  }
  volumes {
    container_path = "/sys"
    host_path      = "/sys"
    read_only      = true
  }
  volumes {
    container_path = "/var/lib/docker"
    host_path      = "/var/lib/docker"
    read_only      = true
  }
  volumes {
    container_path = "/dev/disk"
    host_path      = "/dev/disk"
    read_only      = true
  }
}

# Tailscale
resource "docker_image" "tailscale" {
  name = "tailscale/tailscale:latest"
}

resource "docker_container" "tailscale" {
  image      = docker_image.tailscale.image_id
  name       = "tailscale"
  restart    = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag      = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
    max-size = "2m"
    max-file = "1"
  }
  privileged   = true
  network_mode = "host"
  env = [
    "TS_AUTHKEY=${var.headscale_authkey}",
    "TS_STATE_DIR=/var/lib/tailscale",
    "TS_HOSTNAME=${var.hostname}",
    "TS_EXTRA_ARGS=--login-server=https://headscale.nxthdr.dev --advertise-tags=tag:ixp",
    "TS_USERSPACE=false",
    "TS_DEBUG=false"
  ]
  volumes {
    container_path = "/var/lib/tailscale"
    host_path      = "/home/nxthdr/tailscale/state"
  }
  volumes {
    container_path = "/dev/net/tun"
    host_path      = "/dev/net/tun"
  }
}
