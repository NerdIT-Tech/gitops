data "http" "fcos_stream" {
  url = "https://builds.coreos.fedoraproject.org/streams/${var.fcos_stream}.json"
}

locals {
  fcos_metadata   = jsondecode(data.http.fcos_stream.response_body)
  fcos_qemu_image = local.fcos_metadata.architectures.x86_64.artifacts.qemu.formats["qcow2.xz"].disk
  fcos_version    = local.fcos_metadata.architectures.x86_64.artifacts.qemu.release
}

resource "proxmox_virtual_environment_download_file" "fcos_image" {
  content_type            = "iso"
  datastore_id            = var.image_datastore_id
  node_name               = var.proxmox_node
  url                     = local.fcos_qemu_image.location
  checksum                = local.fcos_qemu_image.sha256
  checksum_algorithm      = "sha256"
  decompression_algorithm = "zst"
  file_name               = "fedora-coreos-${local.fcos_version}-qemu.qcow2.img"
  overwrite               = false
}

# Base bootstrap (user, firewalld, zincati, guest agent) + whatever the
# calling service passes in as extra_butane_snippets, merged via Ignition's
# native config-merge (this is what poseidon/ct's `snippets` arg does under
# the hood - each snippet is transpiled on its own, then merged).
data "ct_config" "merged" {
  content = templatefile("${path.module}/butane/base.bu.tftpl", {
    ssh_authorized_key       = var.ssh_public_key
    hostname                 = var.vm_name
    qemu_guest_agent_enabled = var.qemu_guest_agent_enabled
    timezone                 = var.timezone
  })
  snippets = var.extra_butane_snippets
  strict   = true
}

resource "proxmox_virtual_environment_file" "ignition" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.proxmox_node

  source_raw {
    data      = data.ct_config.merged.rendered
    file_name = "${var.vm_name}.ign"
  }
}

# Ignition only runs on first boot - it will NOT re-apply if this content
# changes on an already-provisioned VM. This fingerprint makes that drift
# *visible* in `terraform plan`/CI output rather than silently doing nothing.
# It is deliberately NOT wired into replace_triggered_by: for a stateful
# single-instance appliance like Omada, auto-recreating the VM on every
# Butane edit would also blow away its data disk. See the environment
# README for the manual rebuild+restore runbook instead.
resource "terraform_data" "ignition_fingerprint" {
  input = sha256(join("\n", concat([
    templatefile("${path.module}/butane/base.bu.tftpl", {
      ssh_authorized_key       = var.ssh_public_key
      hostname                 = var.vm_name
      qemu_guest_agent_enabled = var.qemu_guest_agent_enabled
      timezone                 = var.timezone
    })
  ], var.extra_butane_snippets)))
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  node_name = var.proxmox_node
  vm_id     = var.vm_id
  tags      = concat(["terraform", "fcos"], var.extra_tags)

  machine = "q35"
  bios    = "seabios"

  agent {
    enabled = var.qemu_guest_agent_enabled
    timeout = "5m"
  }

  cpu {
    cores = var.vm_cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  disk {
    datastore_id = var.vm_datastore_id
    file_id      = proxmox_virtual_environment_download_file.fcos_image.id
    interface    = "virtio0"
    size         = var.vm_disk_size_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_id
    model   = "virtio"
  }

  serial_device {}

  operating_system {
    type = "l26"
  }

  kvm_arguments = "-fw_cfg name=opt/com.coreos/config,file=${var.snippet_fs_path}/${var.vm_name}.ign"

  stop_on_destroy = true

  lifecycle {
    ignore_changes = [
      disk[0].file_id,
    ]
  }

  depends_on = [proxmox_virtual_environment_file.ignition]
}
