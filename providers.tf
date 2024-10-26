terraform {
  required_providers {
    # porkbun = {
    #   source = "kyswtn/porkbun"
    #   version = "0.1.2"
    # }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {
  host     = "ssh://163.172.213.99:22"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

# provider "porkbun" {
#   api_key        = var.porkbun_api_key
#   secret_api_key = var.secret_api_key
# }