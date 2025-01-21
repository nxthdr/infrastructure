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

variable "redpanda_superuser_username" {
  description = "Redpanda Superuser Username"
  type        = string
}

variable "redpanda_superuser_password" {
  description = "Redpanda Superuser Password"
  type        = string
}

variable "redpanda_saimiris_username" {
  description = "Redpanda Saimiris Username"
  type        = string
}

variable "redpanda_saimiris_password" {
  description = "Redpanda Saimiris Password"
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