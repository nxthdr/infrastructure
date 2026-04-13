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
  name = "grafana/alloy:v1.15.1"
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
  name = "prom/node-exporter:v1.11.1"
}

resource "docker_container" "node_exporter" {
  image   = docker_image.node_exporter.image_id
  name    = "node_exporter"
  command = [
    "--path.procfs=/host/proc",
    "--path.rootfs=/rootfs",
    "--path.sysfs=/host/sys",
    "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
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

# Saimiris
data "docker_registry_image" "saimiris" {
  name = "ghcr.io/nxthdr/saimiris:main"
}

resource "docker_image" "saimiris" {
  name          = data.docker_registry_image.saimiris.name
  pull_triggers = [data.docker_registry_image.saimiris.sha256_digest]
}

resource "docker_container" "saimiris" {
  image      = docker_image.saimiris.image_id
  name       = "saimiris"
  command    = ["-v", "agent", "--config=/config/saimiris.yml"]
  restart    = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns          = ["2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1"]
  network_mode = "host"
  volumes {
    container_path = "/config/saimiris.yml"
    host_path      = "/home/nxthdr/saimiris/config/saimiris.yml"
  }
}
