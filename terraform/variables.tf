variable "porkbun_api_key" {
  description = "Porkbun API Key"
  type        = string
}
variable "porkbun_secret_api_key" {
  description = "Porkbun Secret Key"
  type        = string
}

variable "alertmanager_discord_webhook_url" {
  description = "Alertmanager Discord Webhook URL"
  type        = string
}

variable "chbot_discord_token" {
  description = "chbot Discord Token"
  type        = string
}

variable "dyndns_auth_token" {
  description = "DynDNS Auth Token"
  type        = string
}

variable "saimiris_agent_key" {
  description = "Saimiris Gateway agent key"
  type        = string
}

variable "peerlab_agent_key" {
  description = "Peerlab Gateway agent key"
  type        = string
}

variable "peerlab_m2m_app_id" {
  description = "Peerlab Gateway Auth0 M2M App ID"
  type        = string
}

variable "peerlab_m2m_app_secret" {
  description = "Peerlab Gateway Auth0 M2M App Secret"
  type        = string
  sensitive   = true
}

variable "saimiris_redpanda_username" {
  description = "Saimiris Redpanda username"
  type        = string
}

variable "saimiris_redpanda_password" {
  description = "Saimiris Redpanda password"
  type        = string
}

variable "pesto_redpanda_username" {
  description = "Pesto Redpanda username"
  type        = string
}

variable "pesto_redpanda_password" {
  description = "Pesto Redpanda password"
  type        = string
}

variable "postgresql_username" {
  description = "PostgreSQL username"
  type        = string
}

variable "postgresql_password" {
  description = "PostgreSQL password"
  type        = string
}

variable "headscale_authkey" {
  description = "Headscale authentication key"
  type        = string
  sensitive   = true
}

variable "vultr_api_key" {
  description = "Vultr API Key"
  type        = string
  sensitive   = true
}

variable "vultr_ssh_key_names" {
  description = "List of SSH key names in Vultr account to add to servers"
  type        = list(string)
  default     = ["Matthieu Gouel"]
}
