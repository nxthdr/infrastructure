terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
    # porkbun = {
    #   source = "kyswtn/porkbun"
    #   version = "0.1.2"
    # }
  }
}

provider "docker" {
  host     = "ssh://nxthdr@core.infra.nxthdr.dev:22"
  alias = "core"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

provider "docker" {
  host     = "ssh://nxthdr@ams.sw.infra.nxthdr.dev:22"
  alias = "ams_sw"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

provider "docker" {
  host     = "ssh://nxthdr@waw.sw.infra.nxthdr.dev:22"
  alias = "waw_sw"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

# provider "porkbun" {
#   api_key        = var.porkbun_api_key
#   secret_api_key = var.secret_api_key
# }