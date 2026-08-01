terraform {
  required_version = ">= 1.10.0"

  # No required_providers block: this module has no resources or data
  # sources of its own, only a templatefile() call and outputs - same shape
  # as modules/omada (see ADR-0008) and for the same reason. Anything that
  # needs a provider belongs to the VM-provisioning module this one's output
  # gets composed with, not to this one.
}
