resource "docker_network" "vlt_atl01_backend" {
  name = "backend"
  provider = docker.vlt_atl01
  driver = "bridge"
  ipv6 = true
}

resource "docker_image" "vlt_atl01_alloy" {
  name = "grafana/alloy:v1.7.5"
  provider = docker.vlt_atl01
}

resource "docker_container" "vlt_atl01_alloy" {
  image = docker_image.vlt_atl01_alloy.image_id
  name  = "alloy"
  provider = docker.vlt_atl01
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
    name = docker_network.vlt_atl01_backend.name
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
