variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token, format user@realm!token-id=secret. Needs enough role permissions for VM lifecycle + image/ISO upload + datastore operations - see ADR-0007."
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

variable "acme_email" {
  description = "Contact email for Let's Encrypt expiry/revocation notices on omada01's certificate."
  type        = string
}
