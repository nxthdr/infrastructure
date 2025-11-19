# Extract location code from hostname (e.g., vltatl01 -> atl01)
locals {
  location_code = substr(var.hostname, 3, 5)  # Extract location+number (e.g., atl01)
  fqdn          = "${local.location_code}.${var.dns_subdomain}.${var.porkbun_domain}"
}

# Create Vultr server
resource "vultr_instance" "vlt_server" {
  label              = var.hostname
  hostname           = var.hostname
  region             = var.region
  plan               = var.plan
  os_id              = var.os_id
  enable_ipv6        = var.enable_ipv6
  ddos_protection    = var.ddos_protection
  activation_email   = var.activation_email
  ssh_key_ids        = var.ssh_key_ids
  tags               = var.tags
  backups            = "disabled"

  lifecycle {
    ignore_changes = [
      # Ignore changes to SSH keys after initial creation
      # This prevents Terraform from recreating the server if keys change
      ssh_key_ids,
    ]
  }
}

# Create Porkbun A record (IPv4)
resource "porkbun_dns_record" "ipv4" {
  domain = var.porkbun_domain
  name   = "${local.location_code}.${var.dns_subdomain}"
  type   = "A"
  content = vultr_instance.vlt_server.main_ip
  ttl    = "600"
}

# Create Porkbun AAAA record (IPv6)
resource "porkbun_dns_record" "ipv6" {
  domain = var.porkbun_domain
  name   = "${local.location_code}.${var.dns_subdomain}"
  type   = "AAAA"
  content = vultr_instance.vlt_server.v6_main_ip
  ttl    = "600"
}
