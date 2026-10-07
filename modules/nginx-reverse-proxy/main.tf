# This module owns *what* an nginx TLS-terminating reverse proxy in front
# of one upstream host:port is - the Quadlet unit, its rendered nginx.conf,
# its firewalld service, and a cert-reload trigger - and nothing about
# *where* it runs or what's on the other end of upstream_host/upstream_port
# beyond that. No provider, no resources, no state - same boundary
# ADR-0008 drew for modules/omada, drawn here for the same reason: a future
# service besides Omada that wants nginx terminating TLS in front of it
# should be able to compose this module again without a copy-paste fork.
#
# Pairs with modules/porkbun-acme-tls the same way modules/omada previously
# did directly (before this module existed) - now this module is the one
# consuming tls_cert_dir/acme_service_name, not the proxied service. The
# proxied service itself goes back to plain HTTP on its loopback port; see
# environments/homelab/omada/omada.tf for the composition and
# environments/homelab/omada/README.md for why TLS moved here.

locals {
  # Only open http_port in firewalld if anything actually listens on it.
  # distinct() (not toset()/sort()) for the same reason modules/omada uses
  # it for tcp_ports: stable first-seen ordering across plans so the
  # rendered firewalld XML - and therefore ignition_fingerprint upstream -
  # doesn't flap when listen_port and http_port happen to collide in some
  # future caller's config.
  tcp_ports = var.redirect_http ? distinct([var.listen_port, var.http_port]) : [var.listen_port]

  # nginx's server_name directive takes a space-separated list, not a YAML
  # list - joined here so the template itself stays a straight
  # interpolation, not another for-loop to review.
  server_names_string = join(" ", var.server_names)

  butane_snippet = templatefile("${path.module}/butane/nginx-reverse-proxy.bu.tftpl", {
    proxy_name        = var.proxy_name
    server_names      = local.server_names_string
    listen_port       = var.listen_port
    redirect_http     = var.redirect_http
    http_port         = var.http_port
    upstream_host     = var.upstream_host
    upstream_port     = var.upstream_port
    tls_cert_dir      = var.tls_cert_dir
    tls_cert_filename = var.tls_cert_filename
    tls_key_filename  = var.tls_key_filename
    acme_service_name = var.acme_service_name
    nginx_image_tag   = var.nginx_image_tag
    tcp_ports         = local.tcp_ports
  })
}
