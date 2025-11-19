variable "hostname" {
  description = "Short hostname (e.g., vltatl01)"
  type        = string
}

variable "region" {
  description = "Vultr region code (e.g., atl, cdg, fra)"
  type        = string
}

variable "plan" {
  description = "Vultr plan ID"
  type        = string
  default     = "vc2-1c-1gb"
}

variable "os_id" {
  description = "Vultr OS ID (Debian 13 x64 trixie)"
  type        = number
  default     = 2625  # Debian 13 x64 (trixie)
}

variable "ssh_key_ids" {
  description = "List of SSH key IDs to add to the server"
  type        = list(string)
}

variable "enable_ipv6" {
  description = "Enable IPv6 on the server"
  type        = bool
  default     = true
}

variable "ddos_protection" {
  description = "Enable DDoS protection"
  type        = bool
  default     = false
}

variable "activation_email" {
  description = "Send activation email"
  type        = bool
  default     = false
}

variable "porkbun_domain" {
  description = "Base domain for DNS records (e.g., nxthdr.dev)"
  type        = string
  default     = "nxthdr.dev"
}

variable "dns_subdomain" {
  description = "DNS subdomain pattern (e.g., vlt.infra)"
  type        = string
  default     = "vlt.infra"
}

variable "tags" {
  description = "Tags to apply to the server"
  type        = list(string)
  default     = ["nxthdr", "vlt", "automated"]
}
