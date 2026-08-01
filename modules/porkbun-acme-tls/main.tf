# This module owns *how a cert gets issued and kept renewed* (a certbot
# oneshot unit, a twice-daily renewal timer, and a deploy-hook that copies
# the result to a caller-chosen path) and nothing about what consumes the
# resulting PEM files - no provider, no resources, no state. It renders
# Butane YAML and hands it back as a string, the same boundary ADR-0008
# drew for modules/omada, drawn here for the same reason: a future service
# besides Omada needing Porkbun DNS-01 TLS should be able to compose this
# module again without this module (or the service it's paired with)
# needing to change.
#
# Deliberately does NOT take the Porkbun API key/secret as inputs - see
# ADR-0010. A real credential leaked through this module's original design
# (interpolated into Butane content, which flows through this repo's
# terraform-pr.yml plan-comment workflow) because Terraform's sensitivity
# marks don't survive the poseidon/ct provider's Butane->Ignition
# transpilation. The fix is structural, not a redaction: this module never
# sees the credential's value at all, so there is nothing for Terraform to
# fail to redact. See this module's README for the operational
# consequence (the credentials file has to be written out-of-band, over
# SSH, before the first issuance can succeed).

locals {
  certbot_image    = "docker.io/infinityofspace/certbot_dns_porkbun:${var.certbot_image_tag}"
  credentials_file = coalesce(var.credentials_file, "/etc/porkbun-credentials/${var.cert_name}.ini")

  butane_snippet = templatefile("${path.module}/butane/porkbun-acme-tls.bu.tftpl", {
    cert_name            = var.cert_name
    domain_names         = var.domain_names
    acme_email           = var.acme_email
    credentials_file     = local.credentials_file
    output_dir           = var.output_dir
    output_cert_filename = var.output_cert_filename
    output_key_filename  = var.output_key_filename
    output_owner_uid     = var.output_owner_uid
    output_owner_gid     = var.output_owner_gid
    certbot_image        = local.certbot_image
  })
}
