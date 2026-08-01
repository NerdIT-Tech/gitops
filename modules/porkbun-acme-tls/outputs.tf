output "butane_snippet" {
  description = <<-EOT
    Rendered Butane YAML for the Porkbun DNS-01 ACME renewal loop
    (credentials file, oneshot certbot unit, twice-daily timer, deploy-hook
    script). Feed this into a VM-provisioning module's extra_butane_snippets
    alongside the consuming service's own snippet. Produces cert/key PEM
    files at output_dir/{output_cert_filename,output_key_filename} - this
    module has no knowledge of what consumes them.

    Marked sensitive: this string has porkbun_api_key/porkbun_api_secret
    interpolated into it in plaintext (see this module's README for that
    trade-off) - Terraform requires this annotation for any output derived
    from a sensitive input, it does not itself add any protection beyond
    redacting plan/apply CLI output.
  EOT
  value       = local.butane_snippet
  sensitive   = true
}

output "acme_service_name" {
  description = <<-EOT
    The systemd unit name (acme-<cert_name>.service) that performs
    issuance/renewal. A consuming service's Quadlet unit can add
    After=/Requires= on this name to block its own first start on a
    successful initial issuance, the way modules/omada's enable_tls does.
  EOT
  value       = "acme-${var.cert_name}.service"
}
