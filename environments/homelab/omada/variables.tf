variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token, format user@realm!token-id=secret. Needs enough role permissions for VM lifecycle + image download + datastore operations - see ADR-0006."
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_username" {
  type    = string
  default = "root"
}

variable "proxmox_ssh_private_key" {
  description = "Private key (PEM) for the SSH connection bpg/proxmox falls back to for snippet upload - see ADR-0006. A separate credential from the API token, not a shared password."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  type    = bool
  default = false
}

variable "proxmox_node" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
