variable "hostname" {
  description = "Hostname for the VLT server"
  type        = string
}

variable "enable_saimiris" {
  description = "Deploy the saimiris probing agent. False for a VLT-provisioned host that must never probe (inventory `probing: false`): it still gets the observability stack, but no probe source can appear on it via `make apply`."
  type        = bool
  default     = true
}
