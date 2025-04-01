resource "docker_network" "vlt_cdg01_backend" {
  name = "backend"
  provider = docker.vlt_cdg01
  driver = "bridge"
  ipv6 = true
}

# Alloy
resource "docker_image" "vlt_cdg01_alloy" {
  name = "grafana/alloy:v1.7.5"
  provider = docker.vlt_cdg01
}

resource "docker_container" "vlt_cdg01_alloy" {
  image = docker_image.vlt_cdg01_alloy.image_id
  name  = "alloy"
  provider = docker.vlt_cdg01
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
    name = docker_network.vlt_cdg01_backend.name
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
resource "docker_image" "vlt_cdg01_node_exporter" {
  name = "prom/node-exporter:v1.9.1"
  provider = docker.vlt_cdg01
}

resource "docker_container" "vlt_cdg01_node_exporter" {
  image = docker_image.vlt_cdg01_node_exporter.image_id
  name  = "node_exporter"
  provider = docker.vlt_cdg01
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
  hostname = "vltcdg01"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.vlt_cdg01_backend.name
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
