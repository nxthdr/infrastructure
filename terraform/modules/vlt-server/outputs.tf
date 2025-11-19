output "id" {
  description = "Vultr instance ID"
  value       = vultr_instance.vlt_server.id
}

output "hostname" {
  description = "Server hostname"
  value       = var.hostname
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = local.fqdn
}

output "main_ip" {
  description = "Primary IPv4 address"
  value       = vultr_instance.vlt_server.main_ip
}

output "v6_main_ip" {
  description = "Primary IPv6 address"
  value       = vultr_instance.vlt_server.v6_main_ip
}

output "v6_network" {
  description = "IPv6 network"
  value       = vultr_instance.vlt_server.v6_network
}

output "v6_network_size" {
  description = "IPv6 network size"
  value       = vultr_instance.vlt_server.v6_network_size
}

output "internal_ip" {
  description = "Internal IP address"
  value       = vultr_instance.vlt_server.internal_ip
}

output "region" {
  description = "Vultr region"
  value       = vultr_instance.vlt_server.region
}

output "status" {
  description = "Server status"
  value       = vultr_instance.vlt_server.status
}

output "power_status" {
  description = "Server power status"
  value       = vultr_instance.vlt_server.power_status
}

output "gateway_v4" {
  description = "IPv4 gateway"
  value       = vultr_instance.vlt_server.gateway_v4
}

output "netmask_v4" {
  description = "IPv4 netmask"
  value       = vultr_instance.vlt_server.netmask_v4
}
