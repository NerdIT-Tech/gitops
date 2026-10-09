# omada01 (vm_id 9010) is no longer managed by Terraform.
#
# This block forgets every resource the module.omada instance
# (modules/fcos-quadlet-vm) tracked - the Proxmox VM, its install ISO, the
# rendered Ignition file, and the terraform_data bookkeeping resources -
# from state (gitops/omada/terraform.tfstate) WITHOUT destroying them. It is
# the GitOps equivalent of `terraform state rm module.omada`: the VM keeps
# running on Proxmox and its data disk (/var/lib/omada/data) is untouched.
#
# This root is kept - not deleted - until this plan has been applied at
# least once, because only an apply can act on a removed block. Deleting the
# configuration first would leave the state entries orphaned. The apply
# workflow still targets this root; once it has run, this root and its
# `omada` workflow entries can be deleted.
removed {
  from = module.omada

  lifecycle {
    destroy = false
  }
}
