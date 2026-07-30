module "gha_runner" {
  source = "../../../modules/fcos-quadlet-vm"

  proxmox_node   = var.proxmox_node
  ssh_public_key = var.ssh_public_key

  vm_id   = 9011
  vm_name = "gha-runner"

  network_bridge = "vmbr0"
  vlan_id        = null

  extra_tags = ["gha-runner", "ci"]

  extra_butane_snippets = [
    templatefile("${path.module}/../../../services/gha-runner/butane/gha-runner.bu.tftpl", {
      github_repo       = var.github_repo
      github_runner_pat = var.github_runner_pat
      runner_labels     = var.runner_labels
      runner_image_tag  = var.runner_image_tag
      container_puid    = 509
      container_pgid    = 509
    })
  ]
}

output "gha_runner_ipv4_addresses" {
  value = module.gha_runner.ipv4_addresses
}

output "gha_runner_ignition_fingerprint" {
  value = module.gha_runner.ignition_fingerprint
}
