resource "docker_network" "scw_ams01_backend" {
  name = "backend"
  provider = docker.scw_ams01
  driver = "bridge"
  ipv6 = true
}

resource "docker_image" "scw_ams01_caddy" {
  name = "caddy:2.9"
  provider = docker.scw_ams01
}

resource "docker_container" "scw_ams01_proxy" {
  image = docker_image.scw_ams01_caddy.image_id
  name  = "proxy"
  provider = docker.scw_ams01
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  env = ["CADDY_ADMIN=[::]:2019"]
#   user = "1000:1000"
  network_mode = "host"
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
resource "docker_image" "scw_ams01_alloy" {
  name = "grafana/alloy:v1.8.1"
  provider = docker.scw_ams01
}

resource "docker_container" "scw_ams01_alloy" {
  image = docker_image.scw_ams01_alloy.image_id
  name  = "alloy"
  provider = docker.scw_ams01
  command = [
    "run", "--storage.path=/var/lib/alloy/data",
    "/etc/alloy/config.alloy"
  ]
  log_driver = "json-file"
  log_opts = {
    tag = "{{.ImageName}}|{{.Name}}|{{.ImageFullID}}|{{.FullID}}"
  }
  dns = [ "2a00:1098:2c::1", "2a00:1098:2c::1", "2a00:1098:2b::1" ]
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.scw_ams01_backend.name
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
resource "docker_image" "scw_ams01_node_exporter" {
  name = "prom/node-exporter:v1.9.1"
  provider = docker.scw_ams01
}

resource "docker_container" "scw_ams01_node_exporter" {
  image = docker_image.scw_ams01_node_exporter.image_id
  name  = "node_exporter"
  provider = docker.scw_ams01
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
  pid_mode = "host"
  hostname = "scwams01"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.scw_ams01_backend.name
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
