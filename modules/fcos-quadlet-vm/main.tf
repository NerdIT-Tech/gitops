data "http" "fcos_stream" {
  url = "https://builds.coreos.fedoraproject.org/streams/${var.fcos_stream}.json"
}

locals {
  fcos_metadata  = jsondecode(data.http.fcos_stream.response_body)
  fcos_live_iso  = local.fcos_metadata.architectures.x86_64.artifacts.metal.formats.iso.disk
  fcos_version   = local.fcos_metadata.architectures.x86_64.artifacts.metal.release
  build_dir      = pathexpand("~/.cache/fcos-quadlet-vm")
  custom_iso_dir = "${local.build_dir}/${var.vm_name}"
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

# Ignition only runs on first boot - it will NOT re-apply if this content
# changes on an already-provisioned VM. This fingerprint makes that drift
# *visible* in `terraform plan`/CI output rather than silently doing nothing.
# It is deliberately NOT wired into replace_triggered_by: for a stateful
# single-instance appliance like Omada, auto-recreating the VM on every
# Butane edit would also blow away its data disk. See the environment
# README for the manual rebuild+restore runbook instead. It also drives
# custom_iso_build below - a content change rebuilds the install ISO, but
# (same reasoning) does not by itself force the VM to reinstall.
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

resource "local_file" "rendered_ignition" {
  content  = data.ct_config.merged.rendered
  filename = "${local.custom_iso_dir}/${var.vm_name}.ign"
}

# Proxmox hardcodes the VM 'args' field (what a -fw_cfg-based Ignition
# delivery would need) to root@pam password auth, with no grantable
# privilege that a scoped API token can hold - see ADR-0007. This builds an
# FCOS live ISO with the Ignition config embedded, that unattended-installs
# itself to the VM's disk on first boot instead - upload and every other
# VM.Config.* operation this module needs are all grantable to a scoped
# token, and (bonus) this needs no SSH connection to Proxmox at all, unlike
# the snippet-file approach it replaces.
resource "terraform_data" "custom_iso_build" {
  triggers_replace = {
    fingerprint  = terraform_data.ignition_fingerprint.output
    fcos_version = local.fcos_version
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/build-custom-iso.sh"
    environment = {
      PRISTINE_ISO_URL    = local.fcos_live_iso.location
      PRISTINE_ISO_SHA256 = local.fcos_live_iso.sha256
      IGNITION_FILE       = local_file.rendered_ignition.filename
      OUTPUT_ISO          = "${local.custom_iso_dir}/${var.vm_name}-${substr(terraform_data.ignition_fingerprint.output, 0, 12)}.iso"
      # Matches this module's disk interface ("virtio0" below) - Linux
      # enumerates virtio-blk disks as /dev/vda, not /dev/sda. Mismatching
      # this against the actual disk interface silently installs nothing -
      # see ADR-0007's Context for how that showed up (wr_bytes stayed 0).
      DEST_DEVICE = "/dev/vda"
    }
  }
}

resource "proxmox_virtual_environment_file" "custom_iso" {
  content_type = "iso"
  datastore_id = var.image_datastore_id
  node_name    = var.proxmox_node

  source_file {
    path      = "${local.custom_iso_dir}/${var.vm_name}-${substr(terraform_data.ignition_fingerprint.output, 0, 12)}.iso"
    file_name = "${var.vm_name}-${substr(terraform_data.ignition_fingerprint.output, 0, 12)}.iso"
  }

  # source_file.path only exists once the local-exec build script has run -
  # Terraform can't infer that ordering on its own since the path is a
  # plain string, not a reference to the build resource's own attributes.
  depends_on = [terraform_data.custom_iso_build]
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

  # Blank - coreos-installer partitions and writes the OS onto this from
  # the attached install ISO on first boot (see custom_iso_build above).
  disk {
    datastore_id = var.vm_datastore_id
    interface    = "virtio0"
    size         = var.vm_disk_size_gb
    iothread     = true
    discard      = "on"
  }

  # q35's IDE controller only exposes ide0/ide2 - the provider's ide3
  # default doesn't work on this machine type.
  cdrom {
    file_id   = proxmox_virtual_environment_file.custom_iso.id
    interface = "ide2"
  }

  # Disk first: on the very first boot the disk is blank/unbootable, so
  # SeaBIOS falls through to the CD-ROM automatically. Once the unattended
  # install completes and reboots, the disk is bootable and takes
  # precedence without needing to touch boot order again.
  boot_order = ["virtio0", "ide2"]

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_id
    model   = "virtio"
  }

  serial_device {}

  operating_system {
    type = "l26"
  }

  stop_on_destroy = true

  depends_on = [proxmox_virtual_environment_file.custom_iso]
}
