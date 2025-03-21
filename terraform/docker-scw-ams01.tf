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

resource "docker_image" "scw_ams01_alloy" {
  name = "grafana/alloy:v1.7.5"
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
    name = docker_network.ixp_fra01_backend.name
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
