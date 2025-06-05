resource "docker_network" "scwams01_backend" {
  name = "backend"
  provider = docker.scwams01
  driver = "bridge"
  ipv6 = true
}

resource "docker_image" "scwams01_caddy" {
  name = "caddy:2.10"
  provider = docker.scwams01
}

resource "docker_container" "scwams01_proxy" {
  image = docker_image.scwams01_caddy.image_id
  name  = "proxy"
  provider = docker.scwams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  env = [ "CADDY_ADMIN=[::]:2019" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.scwams01_backend.name
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
    host_path = "/home/nxthdr/proxy/config/Caddyfile"
  }
  volumes {
    container_path = "/data"
    host_path = "/home/nxthdr/proxy/data"
  }
}

# Alloy
resource "docker_image" "scwams01_alloy" {
  name = "grafana/alloy:v1.9.1"
  provider = docker.scwams01
}

resource "docker_container" "scwams01_alloy" {
  image = docker_image.scwams01_alloy.image_id
  name  = "alloy"
  provider = docker.scwams01
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
    name = docker_network.scwams01_backend.name
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
}

# Node Exporter
resource "docker_image" "scwams01_node_exporter" {
  name = "prom/node-exporter:v1.9.1"
  provider = docker.scwams01
}

resource "docker_container" "scwams01_node_exporter" {
  image = docker_image.scwams01_node_exporter.image_id
  name  = "node_exporter"
  provider = docker.scwams01
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
  user = "1000:1000"
  pid_mode = "host"
  hostname = "scwams01"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.scwams01_backend.name
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
resource "docker_image" "scwams01_cadvisor" {
  name = "gcr.io/cadvisor/cadvisor:v0.52.1"
  provider = docker.scwams01
}

resource "docker_container" "scwams01_cadvisor" {
  image = docker_image.scwams01_cadvisor.image_id
  name  = "cadvisor"
  provider = docker.scwams01
  restart = "unless-stopped"
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  privileged = "true"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.scwams01_backend.name
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
