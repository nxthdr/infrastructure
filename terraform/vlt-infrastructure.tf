# VLT Infrastructure Management
# This file provisions Vultr servers and DNS records based on inventory.yml

# Data source to read SSH keys from Vultr account
data "vultr_ssh_key" "nxthdr_keys" {
  for_each = toset(var.vultr_ssh_key_names)

  filter {
    name   = "name"
    values = [each.value]
  }
}

# vlt_servers local is generated in vlt.tf by render_terraform.py from inventory.yml

locals {
  # Extract SSH key IDs
  ssh_key_ids = [for key in data.vultr_ssh_key.nxthdr_keys : key.id]
}

# Create VLT servers using the module
module "vlt_server" {
  source   = "./modules/vlt-server"
  for_each = local.vlt_servers

  hostname     = each.key
  region       = each.value.region
  ssh_key_ids  = local.ssh_key_ids

  # Optional: Override defaults if needed
  # plan         = "vc2-1c-1gb"  # Default
  # os_id        = 2625  # Debian 13 x64 trixie (default)
}

# Outputs for all VLT servers
output "vlt_servers" {
  description = "Information about all VLT servers"
  value = {
    for hostname, server in module.vlt_server : hostname => {
      id          = server.id
      fqdn        = server.fqdn
      main_ip     = server.main_ip
      v6_main_ip  = server.v6_main_ip
      v6_network  = server.v6_network
      region      = server.region
      status      = server.status
    }
  }
}
