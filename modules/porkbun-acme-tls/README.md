# porkbun-acme-tls

Renders the Butane/Ignition snippet for an on-VM certbot renewal loop that
obtains a Let's Encrypt certificate via DNS-01, using Porkbun's DNS API
(the [`certbot-dns-porkbun`](https://github.com/infinityofspace/certbot_dns_porkbun)
plugin, run as a container since Fedora CoreOS has no native Python/pip):
a `0600` Porkbun credentials file, a oneshot `acme-<cert_name>.service` unit
that runs `certbot certonly`, a twice-daily `acme-<cert_name>.timer`, and a
`--deploy-hook` script that copies the renewed `fullchain.pem`/`privkey.pem`
to a caller-chosen directory and ownership.

## What this module is (and isn't)

Same shape as [`modules/omada`](../omada) (see
[ADR-0008](../../docs/adr/0008-decouple-omada-service-from-vm-provisioning.md)
for the reasoning this mirrors, and
[ADR-0009](../../docs/adr/0009-porkbun-dns01-acme-module.md) for why this
capability is its own module rather than folded into `modules/omada`): **no
resources, no data sources, no provider requirements.** It takes
service-shaped inputs (which domains, whose credentials, where to write the
result) and produces one output, `butane_snippet`, plus `acme_service_name`
so a consuming service can order its own first start after a successful
initial issuance. It has no opinion on what consumes the resulting cert.

## Why DNS-01 (not HTTP-01), and why certbot (not acme.sh)

DNS-01 needs zero inbound ports - it proves domain ownership by creating a
`_acme-challenge` TXT record via Porkbun's API, not by serving a challenge
file over HTTP. That matters here because the VMs this issues certs for
(e.g. `omada01`) sit behind RFC1918 addressing with no public inbound path;
HTTP-01 would need port-forwarding or a public-facing reverse proxy this
repo doesn't have. certbot was chosen over acme.sh specifically for its
`--deploy-hook` mechanism (a real, well-documented certbot feature that only
fires on an actual issuance/renewal, not on every timer tick) and the
maintained `certbot-dns-porkbun` plugin.

## Why one cert with two SANs, not two certs

A single `certbot certonly -d a -d b ...` invocation requests one
certificate covering every name in `domain_names` - simpler than juggling
two separate lineages, two keystores, two restart triggers for what is, in
Omada's case, one physical controller answering to both its own hostname
and its group name. If a service ever needs genuinely independent
certificates for genuinely independent hosts, compose this module twice
with different `cert_name`s rather than growing this module to manage
multiple lineages per instance.

## The credential-exposure trade-off

`porkbun_api_key`/`porkbun_api_secret` are `sensitive = true`, but sensitivity
in Terraform only redacts CLI/plan output - it doesn't stop the values being
interpolated into the rendered Butane/Ignition content in plaintext. That
content lands in Terraform state, the CI runner's rendered `.ign` file, and
(for `fcos-quadlet-vm` callers) the uploaded install ISO on Proxmox, in
addition to the `0600` file on the VM itself where it's actually needed.
This is the accepted cost of the "no cert material passes through a
Terraform-side ACME/DNS provider" decision behind this module (see
ADR-0009) - not a gap to fix later. Porkbun API keys are account-wide, not
domain-scoped, which makes this a meaningfully bigger blast radius than
this repo's other credentials (e.g. `ssh_authorized_key`, a public key with
no secrecy requirement) - restrict the key to known egress IPs in Porkbun's
dashboard if that's available to you, and treat its compromise as an
account-wide incident, not a single-domain one.

## Boot-order

`acme-<cert_name>.service` is deliberately not `enabled: true` - it's
started either by a consuming service's `After=`/`Requires=` on
`acme_service_name` (blocking that service's first start on a successful
initial issuance) or by `acme-<cert_name>.timer` (renewal, twice daily with
a randomized delay and `Persistent=true`). It has no independent boot
trigger of its own.
