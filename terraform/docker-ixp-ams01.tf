resource "docker_network" "ixp_ams01_backend" {
  name = "backend"
  provider = docker.ixp_ams01
  driver = "bridge"
  ipv6 = true
}

resource "docker_image" "ixp_ams01_alloy" {
  name = "grafana/alloy:v1.7.5"
  provider = docker.ixp_ams01
}

resource "docker_container" "ixp_ams01_alloy" {
  image = docker_image.ixp_ams01_alloy.image_id
  name  = "alloy"
  provider = docker.ixp_ams01
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
    name = docker_network.ixp_ams01_backend.name
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
