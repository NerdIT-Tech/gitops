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

  # root@pam + password required - see module README for why an API token
  # doesn't work for the kvm_arguments/snippet-upload path.
  username = var.proxmox_username
  password = var.proxmox_password

  ssh {
    agent    = false
    username = var.proxmox_ssh_username
    password = var.proxmox_password
  }
}
