# This module owns *how a cert gets issued and kept renewed* (a certbot
# oneshot unit, a Porkbun DNS-01 credentials file, a twice-daily renewal
# timer, and a deploy-hook that copies the result to a caller-chosen path)
# and nothing about what consumes the resulting PEM files - no provider, no
# resources, no state. It renders Butane YAML and hands it back as a
# string, the same boundary ADR-0008 drew for modules/omada, drawn here for
# the same reason: a future service besides Omada needing Porkbun DNS-01
# TLS should be able to compose this module again without this module (or
# the service it's paired with) needing to change.

locals {
  certbot_image = "docker.io/infinityofspace/certbot_dns_porkbun:${var.certbot_image_tag}"

  butane_snippet = templatefile("${path.module}/butane/porkbun-acme-tls.bu.tftpl", {
    cert_name            = var.cert_name
    domain_names         = var.domain_names
    acme_email           = var.acme_email
    porkbun_api_key      = var.porkbun_api_key
    porkbun_api_secret   = var.porkbun_api_secret
    output_dir           = var.output_dir
    output_cert_filename = var.output_cert_filename
    output_key_filename  = var.output_key_filename
    output_owner_uid     = var.output_owner_uid
    output_owner_gid     = var.output_owner_gid
    certbot_image        = local.certbot_image
  })
}
