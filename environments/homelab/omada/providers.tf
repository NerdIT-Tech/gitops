terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    ct = {
      source  = "poseidon/ct"
      version = "~> 0.13"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # Scoped API token, not root@pam password - see ADR-0007. No ssh{} block:
  # this module delivers Ignition via an install ISO uploaded through the
  # plain HTTP API, not the snippet-upload path ADR-0006 originally needed
  # SSH for - there's no Proxmox operation left here that requires it.
  api_token = var.proxmox_api_token
}
