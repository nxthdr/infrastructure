terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
    porkbun = {
      source  = "cullenmcdermott/porkbun"
      version = "~> 0.2"
    }
  }
}

# Vultr Provider
provider "vultr" {
  api_key = var.vultr_api_key
}

# Porkbun Provider
provider "porkbun" {
  api_key    = var.porkbun_api_key
  secret_key = var.porkbun_secret_api_key
}

# Docker providers are generated in docker-providers.tf by render_terraform.py
