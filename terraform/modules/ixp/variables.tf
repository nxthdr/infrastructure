variable "hostname" {
  description = "Hostname for the IXP server"
  type        = string
}

variable "headscale_authkey" {
  description = "Headscale authentication key for Tailscale"
  type        = string
  sensitive   = true
}
