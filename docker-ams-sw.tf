resource "docker_image" "ams-sw-caddy" {
  name = "caddy:2.9"
  provider = docker.ams-sw
}

resource "docker_container" "ams-sw-proxy" {
  image = docker_image.ams-sw-caddy.image_id
  name  = "proxy"
  provider = docker.ams-sw
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
    host_path = "/root/nxthdr/proxy/config/Caddyfile"
  }
  volumes {
    container_path = "/data"
    host_path = "/root/nxthdr/proxy/data"
  }
}