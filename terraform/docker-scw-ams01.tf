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
