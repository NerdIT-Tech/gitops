# This module owns *what* Omada is (the Quadlet unit, its firewalld
# service, its storage layout) and nothing about *where* it runs - no
# provider, no resources, no state. It renders Butane YAML and hands it
# back as a string. See ../../docs/adr/0008-decouple-omada-service-from-vm-provisioning.md
# for why the boundary is drawn here and what a VM-provisioning module
# (fcos-quadlet-vm today; conceivably an Azure/GCP/libvirt one later) is
# expected to accept in return.

locals {
  # distinct() (not toset()/sort()) both de-duplicates the default overlap
  # (manage_http_port and portal_http_port both default to 8088, and a
  # literal duplicate <port> entry in the firewalld service XML is at best
  # redundant) and keeps the ports in the same first-seen order every plan -
  # a set's iteration order isn't guaranteed stable, which would otherwise
  # make the rendered file (and therefore ignition_fingerprint upstream)
  # flap for no reason.
  tcp_ports = distinct([
    var.manage_http_port,
    var.manage_https_port,
    var.portal_http_port,
    var.portal_https_port,
    29814, # EAP discovery TCP port - not configurable, see variables.tf
  ])

  butane_snippet = templatefile("${path.module}/butane/omada.bu.tftpl", {
    omada_image_tag   = var.omada_image_tag
    container_puid    = var.container_puid
    container_pgid    = var.container_pgid
    timezone          = var.timezone
    manage_http_port  = var.manage_http_port
    manage_https_port = var.manage_https_port
    portal_http_port  = var.portal_http_port
    portal_https_port = var.portal_https_port
    tcp_ports         = local.tcp_ports
    enable_tls        = var.enable_tls
    tls_cert_dir      = var.tls_cert_dir
    acme_service_name = var.acme_service_name
  })
}
