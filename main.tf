resource "docker_network" "dmz" {
  name = "dmz"
  driver = "bridge"
  ipv6 = true
  ipam_config {
    subnet = "2a06:de00:50:cafe:100::/80"
  }
}

resource "docker_network" "upstream" {
  name = "upstream"
  driver = "bridge"
  ipv6 = true
  ipam_config {
    subnet = "2a06:de00:50:cafe:10::/80"
  }
}

# Load-Balancer
resource "docker_image" "caddy" {
  name = "caddy:latest"
}


resource "docker_container" "lb" {
  image = docker_image.caddy.image_id
  name  = "lb"
  
  networks_advanced {
    name = docker_network.dmz.name
    ipv6_address = "2a06:de00:50:cafe:100::a"
  }
  
  networks_advanced {
    name = docker_network.upstream.name
    ipv6_address = "2a06:de00:50:cafe:10::a"
  }

  volumes {
    container_path = "/etc/caddy/Caddyfile"
    host_path = "/home/matthieugouel/nxthdr/lb/Caddyfile"
  }
}

# `as215011.net` upstream services
## `as215011.net` 
resource "docker_image" "website_nxthdr" {
  name = "ghcr.io/nxthdr/nxthdr.dev:main"
}

resource "docker_container" "website_as215011" {
  image = docker_image.website_nxthdr.image_id
  name  = "website_as215011"
  networks_advanced {
    name = docker_network.upstream.name
    ipv6_address = "2a06:de00:50:cafe:10::10"
  }
}

## `geofeed.as215011.net`
resource "docker_image" "nginx" {
  name = "nginx:latest"
}

resource "docker_container" "geofeed" {
  image = docker_image.nginx.image_id
  name  = "geofeed"
  networks_advanced {
    name = docker_network.upstream.name
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



# `nxthdr.dev` upstream services
## `nxthdr.dev`
resource "docker_container" "website_nxthdr" {
  image = docker_image.website_nxthdr.image_id
  name  = "website_nxthdr"
  networks_advanced {
    name = docker_network.upstream.name
    ipv6_address = "2a06:de00:50:cafe:10::12"
  }
}