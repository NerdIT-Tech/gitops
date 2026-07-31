# "What Omada is" - Quadlet unit, firewalld service, storage layout.
# Provisioning-agnostic (no provider, no resources) - see ADR-0008 and
# modules/omada/README.md. Its only job here is to produce the rendered
# Butane snippet fed into module.omada below.
module "omada_service" {
  source = "../../../modules/omada"

  omada_image_tag = "5.15" # pin to your current controller's version when migrating - see runbook
  container_puid  = 508
  container_pgid  = 508
  timezone        = "America/New_York"
}

# "Where Omada runs" - Proxmox VM sizing/networking/identity. Unchanged in
# shape from before ADR-0008: still the same module block name/source, so
# the VM/ISO/fingerprint resources already tracked in state keep the exact
# same addresses (module.omada.*) - splitting the snippet out into
# module.omada_service above only changes how extra_butane_snippets' value
# is computed, not this module call's identity.
module "omada" {
  source = "../../../modules/fcos-quadlet-vm"

  proxmox_node   = var.proxmox_node
  ssh_public_key = var.ssh_public_key

  vm_id   = 9010
  vm_name = "omada01"

  vm_cpu_cores    = 2
  vm_memory_mb    = 2048
  vm_disk_size_gb = 24

  network_bridge = "vmbr0"
  vlan_id        = null # set if Omada lives on a management VLAN

  timezone   = "America/New_York"
  extra_tags = ["omada", "networking"]

  extra_butane_snippets = [module.omada_service.butane_snippet]
}

output "omada_ipv4_addresses" {
  value = module.omada.ipv4_addresses
}

output "omada_ignition_fingerprint" {
  value = module.omada.ignition_fingerprint
}
