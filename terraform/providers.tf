terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.3.0"
    }
    # porkbun = {
    #   source = "kyswtn/porkbun"
    #   version = "0.1.2"
    # }
  }
}

# provider "porkbun" {
#   api_key        = var.porkbun_api_key
#   secret_api_key = var.secret_api_key
# }

# Core
provider "docker" {
  host     = "ssh://nxthdr@ams01.core.infra.nxthdr.dev:22"
  alias = "core_ams01"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

# IPv4 Proxy servers
provider "docker" {
  host     = "ssh://nxthdr@ams01.scw.infra.nxthdr.dev:22"
  alias = "scw_ams01"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

# IXP servers
provider "docker" {
  host     = "ssh://nxthdr@ams01.ixp.infra.nxthdr.dev:22"
  alias = "ixp_ams01"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

provider "docker" {
  host     = "ssh://nxthdr@fra01.ixp.infra.nxthdr.dev:22"
  alias = "ixp_fra01"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

# Probing servers
provider "docker" {
  host     = "ssh://nxthdr@atl01.vlt.infra.nxthdr.dev:22"
  alias = "vlt_atl01"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}

provider "docker" {
  host     = "ssh://nxthdr@cdg01.vlt.infra.nxthdr.dev:22"
  alias = "vlt_cdg01"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
}
