variable "proxmox_node" {
  type = string
}

variable "image_datastore_id" {
  type    = string
  default = "local"
}

variable "vm_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "fcos_stream" {
  type    = string
  default = "stable"
  validation {
    condition     = contains(["stable", "testing", "next"], var.fcos_stream)
    error_message = "fcos_stream must be one of: stable, testing, next."
  }
}

variable "vm_id" {
  type = number
}

variable "vm_name" {
  type = string
}

variable "vm_cpu_cores" {
  type    = number
  default = 2
}

variable "vm_memory_mb" {
  type    = number
  default = 2048
}

variable "vm_disk_size_gb" {
  type    = number
  default = 24
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  type    = number
  default = null
}

variable "qemu_guest_agent_enabled" {
  type    = bool
  default = true
}

variable "ssh_public_key" {
  type = string
}

variable "timezone" {
  description = "IANA zone name (e.g. America/New_York) symlinked to /etc/localtime on the VM host. Independent of any TZ= a service sets for its own container."
  type        = string
  default     = "Etc/UTC"
}

variable "extra_tags" {
  type    = list(string)
  default = []
}

variable "extra_butane_snippets" {
  description = <<-EOT
    Rendered (post-templatefile) Butane YAML strings that get merged into the
    base config via Ignition's merge mechanism (poseidon/ct's `snippets`).
    This is how a service (e.g. services/omada) layers its Quadlet unit and
    firewall rules on top of this module's common FCOS bootstrap.
  EOT
  type        = list(string)
  default     = []
}
