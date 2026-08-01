output "butane_snippet" {
  description = <<-EOT
    Rendered Butane YAML for the Omada Quadlet unit, its firewalld service,
    and its storage directories. Feed this into a VM-provisioning module's
    extra_butane_snippets (fcos-quadlet-vm's list argument of the same name)
    to actually boot it - this module produces content, not infrastructure.
  EOT
  value       = local.butane_snippet
}
