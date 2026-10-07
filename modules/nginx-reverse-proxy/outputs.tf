output "butane_snippet" {
  description = <<-EOT
    Rendered Butane YAML for the nginx Quadlet unit, its nginx.conf, its
    firewalld service, and its cert-reload path unit. Feed this into a
    VM-provisioning module's extra_butane_snippets (fcos-quadlet-vm's list
    argument of the same name) alongside the proxied service's own snippet
    and the paired porkbun-acme-tls instance's snippet - this module
    produces content, not infrastructure, and has no opinion on what runs
    it.
  EOT
  value       = local.butane_snippet
}
