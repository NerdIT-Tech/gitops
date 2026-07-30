output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "fcos_version_deployed" {
  value = local.fcos_version
}

output "ipv4_addresses" {
  value = try(proxmox_virtual_environment_vm.this.ipv4_addresses, null)
}

output "ignition_fingerprint" {
  description = "Changes whenever rendered Butane content changes. A diff here on an existing VM means: Ignition WILL NOT re-apply automatically - follow the rebuild runbook."
  value       = terraform_data.ignition_fingerprint.output
}
