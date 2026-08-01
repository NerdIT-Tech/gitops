output "butane_snippet" {
  description = <<-EOT
    Rendered Butane YAML for the Porkbun DNS-01 ACME renewal loop (oneshot
    certbot unit, twice-daily timer, deploy-hook script, and the empty
    credentials directory - not the credentials file itself, see
    credentials_file below). Feed this into a VM-provisioning module's
    extra_butane_snippets alongside the consuming service's own snippet.
    Produces cert/key PEM files at
    output_dir/{output_cert_filename,output_key_filename} - this module has
    no knowledge of what consumes them.

    Contains no secret material - safe to appear in terraform plan output
    (e.g. CI's plan-comment workflow) unredacted.
  EOT
  value       = local.butane_snippet
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

output "credentials_file" {
  description = <<-EOT
    Path on the VM where the Porkbun DNS-01 credentials INI file
    (dns_porkbun_key=.../dns_porkbun_secret=...) must be written
    out-of-band (e.g. over SSH, mode 0600) before acme_service_name can
    succeed. This module creates the containing directory but never the
    file itself - see ADR-0010.
  EOT
  value       = local.credentials_file
}
