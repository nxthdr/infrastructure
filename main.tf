locals {
  network_dmz_ipv4_prefix = "172.18.0.0/16"
  network_dmz_ipv6_prefix = "2a06:de00:50:cafe:100::/80"
  network_backend_ipv4_prefix = "172.19.0.0/16"
  network_backend_ipv6_prefix = "2a06:de00:50:cafe:10::/80"
}

resource "docker_network" "dmz" {
  name = "dmz"
  driver = "bridge"
  ipv6 = true
  ipam_config {
    subnet = local.network_dmz_ipv4_prefix
    gateway = cidrhost(local.network_dmz_ipv4_prefix, 1)
  }
  ipam_config {
    subnet = local.network_dmz_ipv6_prefix
  }
}

resource "docker_network" "backend" {
  name = "backend"
  driver = "bridge"
  ipv6 = true
  ipam_config {
    subnet = local.network_backend_ipv4_prefix
    gateway = cidrhost(local.network_backend_ipv4_prefix, 1)
  }
  ipam_config {
    subnet = local.network_backend_ipv6_prefix
  }
}

# DMZ services
## Reverse Proxy
resource "docker_image" "caddy" {
  name = "caddy:latest"
}

resource "docker_container" "lb" {
  image = docker_image.caddy.image_id
  name  = "lb"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.dmz.name
    ipv6_address = "2a06:de00:50:cafe:100::a"
  }
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::a"
  }
  volumes {
    container_path = "/etc/caddy/Caddyfile"
    host_path = "/home/matthieugouel/nxthdr/lb/Caddyfile"
  }
}

# `as215011.net` backend services
## as215011 Website 
data "docker_registry_image" "website_nxthdr" {
  name = "ghcr.io/nxthdr/nxthdr.dev:main"
}

resource "docker_image" "website_nxthdr" {
  name          = data.docker_registry_image.website_nxthdr.name
  pull_triggers = [data.docker_registry_image.website_nxthdr.sha256_digest]
}

resource "docker_container" "website_as215011" {
  image = docker_image.website_nxthdr.image_id
  name  = "website_as215011"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::10"
  }
}

## Geofeed
resource "docker_image" "nginx" {
  name = "nginx:latest"
}

resource "docker_container" "geofeed" {
  image = docker_image.nginx.image_id
  name  = "geofeed"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::11"
  }
  volumes {
    container_path = "/etc/nginx/conf.d/default.conf"
    host_path = "/home/matthieugouel/nxthdr/geofeed/default.conf"
  }
  volumes {
    container_path = "/usr/share/nginx/html"
    host_path = "/home/matthieugouel/nxthdr/geofeed/html"
  }
}

# `nxthdr.dev` backend services
## nxthdr Website
resource "docker_container" "website_nxthdr" {
  image = docker_image.website_nxthdr.image_id
  name  = "website_nxthdr"
  network_mode = "bridge"
  networks_advanced {
    name = docker_network.backend.name
    ipv6_address = "2a06:de00:50:cafe:10::100"
  }
}