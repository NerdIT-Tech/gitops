module "omada" {
  source = "../../../modules/fcos-quadlet-vm"

  proxmox_node   = var.proxmox_node
  ssh_public_key = var.ssh_public_key

  vm_id   = 9010
  vm_name = "omada-controller"

  vm_cpu_cores    = 2
  vm_memory_mb    = 2048
  vm_disk_size_gb = 24

  network_bridge = "vmbr0"
  vlan_id        = null # set if Omada lives on a management VLAN

  timezone   = "America/New_York"
  extra_tags = ["omada", "networking"]

  extra_butane_snippets = [
    templatefile("${path.module}/../../../services/omada/butane/omada.bu.tftpl", {
      omada_image_tag = "5.15" # pin to your current controller's version when migrating - see runbook
      container_puid  = 508
      container_pgid  = 508
      timezone        = "America/New_York"
    })
  ]
}

output "omada_ipv4_addresses" {
  value = module.omada.ipv4_addresses
}

output "omada_ignition_fingerprint" {
  value = module.omada.ignition_fingerprint
}
