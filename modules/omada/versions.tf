terraform {
  required_version = ">= 1.10.0"

  # No required_providers block: this module has no resources or data
  # sources of its own, only a templatefile() call and outputs. That's
  # deliberate - see main.tf's header comment and ADR-0008. Anything that
  # needs a provider (Proxmox, Butane transpilation via poseidon/ct, an
  # eventual Azure/GCP equivalent) belongs to the VM-provisioning module
  # this one's output gets composed with, not to this one.
}
