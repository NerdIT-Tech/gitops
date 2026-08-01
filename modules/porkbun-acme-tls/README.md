# porkbun-acme-tls

Renders the Butane/Ignition snippet for an on-VM certbot renewal loop that
obtains a Let's Encrypt certificate via DNS-01, using Porkbun's DNS API
(the [`certbot-dns-porkbun`](https://github.com/infinityofspace/certbot_dns_porkbun)
plugin, run as a container since Fedora CoreOS has no native Python/pip):
an empty, root-only credentials directory, a oneshot `acme-<cert_name>.service`
unit that runs `certbot certonly`, a twice-daily `acme-<cert_name>.timer`,
and a `--deploy-hook` script that copies the renewed
`fullchain.pem`/`privkey.pem` to a caller-chosen directory and ownership.

**This module never sees the Porkbun API key/secret.** See "Why the
credential is never a Terraform input" below before assuming you can just
add `porkbun_api_key`/`porkbun_api_secret` variables back - a real Porkbun
API secret leaked through exactly that design once already (ADR-0010).

## What this module is (and isn't)

Same shape as [`modules/omada`](../omada) (see
[ADR-0008](../../docs/adr/0008-decouple-omada-service-from-vm-provisioning.md)
for the reasoning this mirrors, and
[ADR-0009](../../docs/adr/0009-porkbun-dns01-acme-module.md)/[ADR-0010](../../docs/adr/0010-porkbun-credential-out-of-band.md)
for why this capability is its own module rather than folded into
`modules/omada`, and why it takes no credential input at all): **no
resources, no data sources, no provider requirements.** It takes
service-shaped inputs (which domains, where the credentials file lives on
the VM, where to write the result) and produces `butane_snippet`,
`acme_service_name` (so a consuming service can order its own first start
after a successful initial issuance), and `credentials_file` (the path
whoever/whatever delivers the credential - CI, a human - must write to,
out-of-band from this module entirely). It has no opinion on what consumes
the resulting cert, or on how the credential gets there.

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

## Why the credential is never a Terraform input

The original design took `porkbun_api_key`/`porkbun_api_secret` as
`sensitive = true` Terraform variables and interpolated them into the
rendered Butane content. That leaked a real Porkbun API secret in
plaintext into a GitHub PR comment: `terraform-pr.yml`'s plan-comment step
posts raw `terraform plan` stdout, and while Terraform's sensitivity marks
correctly propagated through every *pure Terraform* hop (locals, module
outputs, list literals), they did not survive `data.ct_config` (the
`poseidon/ct` provider, which shells out to Butane to transpile the YAML
into Ignition JSON) - a provider RPC boundary. Butane converts a
`storage.files[].contents.inline:` block into a `source: "data:,..."`
percent-encoded URI, a structurally new attribute Terraform's path-based
mark propagation doesn't reach through, and `ct`'s schema doesn't declare
that attribute sensitive. The result: `local_file.rendered_ignition` (and
everything downstream of it - the install ISO build, the Proxmox upload)
showed the credential in cleartext in `terraform plan` output, unredacted,
in CI, in a PR comment. See [ADR-0010](../../docs/adr/0010-porkbun-credential-out-of-band.md)
for the full incident writeup.

The fix is structural, not "redact harder": **this module never receives
the credential's value at all.** It only creates the empty
`/etc/porkbun-credentials` directory and references `credentials_file`'s
*path* in the certbot invocation. The actual `dns_porkbun_key=.../dns_porkbun_secret=...`
content has to be written out-of-band - for `environments/homelab/omada`,
that's a dedicated CI step (`terraform-apply.yml`'s "Seed Porkbun
credentials on omada01") that reads the secret directly from GitHub
Actions secrets and SSHes it to the VM after `terraform apply` completes,
never through a `TF_VAR_*` or any file this module renders. This means
`terraform plan`/`apply` output for this module is safe to post anywhere,
including CI PR comments, unredacted - there's nothing sensitive left in
it to leak, regardless of whether whatever delivers the credential is
automated or manual.

Porkbun API keys are account-wide, not domain-scoped - restrict the key to
known egress IPs in Porkbun's dashboard if that's available to you, and
treat its compromise as an account-wide incident, not a single-domain one,
regardless of how it's delivered to the VM.

## Boot-order

`acme-<cert_name>.service` is deliberately not `enabled: true` - it's
started either by a consuming service's `After=`/`Requires=` on
`acme_service_name` (blocking that service's first start on a successful
initial issuance) or by `acme-<cert_name>.timer` (renewal, twice daily with
a randomized delay and `Persistent=true`). It has no independent boot
trigger of its own.
