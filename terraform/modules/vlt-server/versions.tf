terraform {
  required_version = ">= 1.0"

  required_providers {
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
