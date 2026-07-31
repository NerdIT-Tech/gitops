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

  # Scoped API token, not root@pam password - see ADR-0006. Snippet upload
  # (kvm_arguments' Ignition file) still requires SSH regardless of API auth
  # method - that's a hard constraint of the provider, not something a
  # token avoids - so the ssh{} block below uses a dedicated key instead of
  # sharing a password with the API surface.
  api_token = var.proxmox_api_token

  ssh {
    agent       = false
    username    = var.proxmox_ssh_username
    private_key = var.proxmox_ssh_private_key
  }
}
