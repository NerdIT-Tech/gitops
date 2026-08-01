# ADR-0009: Porkbun DNS-01 ACME as a reusable module, decoupled from Omada

**Status:** Accepted, partially superseded by [ADR-0010](0010-porkbun-credential-out-of-band.md) **Date:** 2026-08-01

> **2026-08-01, same day:** the "Inputs" bullet below (`porkbun_api_key`/`porkbun_api_secret`
> as module inputs) and the entire "accepted credential-exposure trade-off"
> section were the actual design that shipped in this ADR's first version -
> and that design leaked a real Porkbun API secret into a GitHub PR comment
> within hours, because the "trade-off" assumed Terraform's sensitivity
> marks would at least keep the value out of CI output, and they didn't
> survive the `poseidon/ct` provider boundary. ADR-0010 replaces that part
> of this decision: the module now takes no credential input at all. Left
> the rest of this ADR (module boundary, certbot choice, DNS-01 reasoning,
> restart-trigger design, boot-order) unchanged below as the accurate
> historical record of what was decided and why - only the credential
> handling was wrong.

## Context

The request was to give service "groups" (plural, deliberately) valid TLS
certificates on `canady.cloud` - concretely, starting with `omada01`
answering to both its own hostname (`omada01.canady.cloud`) and a shared
group name (`omada.canady.cloud`) that would stay valid if `omada01` were
ever replaced by a differently-named host. A third SAN, the VM's private
RFC1918 IP address, was requested but ruled out early: no public CA
(including Let's Encrypt, and Porkbun's own SSL product, which is Let's
Encrypt under the hood) will sign a certificate containing a private IP
SAN. That constraint isn't a design choice this ADR makes, it's a fact
about public CAs; the accepted scope is DNS names only.

Two more decisions were made before any design started, and this ADR
doesn't re-litigate them:

1. **Issuance mechanism**: an on-VM ACME client performing DNS-01 against
   Porkbun's DNS API, not a Terraform-side ACME/DNS provider. No cert
   material passes through Terraform state as ACME resources - the
   trade-off this creates for the Porkbun API credential itself is
   accepted explicitly below, not ignored.
2. **Client**: certbot (with the `certbot-dns-porkbun` plugin), not
   acme.sh - specifically for certbot's `--deploy-hook` mechanism, a
   well-documented feature that fires only on an actual issuance/renewal,
   not on every timer tick.

## Decision

Split the ACME renewal loop into its own module, `modules/porkbun-acme-tls`,
composed alongside `modules/omada` in `environments/homelab/omada` rather
than folded into `modules/omada` itself.

- **Inputs**: `cert_name`, `domain_names` (the SAN list), `acme_email`,
  `porkbun_api_key`/`porkbun_api_secret` (both `sensitive = true`),
  `output_dir`/`output_cert_filename`/`output_key_filename`/`output_owner_uid`/`output_owner_gid`,
  `certbot_image_tag` (pinned, not `latest`).
- **Outputs**: `butane_snippet` (the renewal loop itself: a `0600`
  credentials file, a oneshot `acme-<cert_name>.service` running certbot
  in a container against `infinityofspace/certbot_dns_porkbun`, a
  twice-daily `acme-<cert_name>.timer`, and a `--deploy-hook` script that
  copies the renewed PEM pair to `output_dir`) and `acme_service_name` (so
  a consuming service can order its own first start after it).
- **No resources, no data sources, no `required_providers`** - identical
  shape to `modules/omada` (ADR-0008), for the identical reason: it cannot
  fail `terraform validate` for provider reasons and needs no credentials
  to plan.
- One certificate with two SANs (`omada01.canady.cloud` +
  `omada.canady.cloud`), not two separate certificates - simpler for one
  physical controller answering to both names today.

### Why a separate module, not folded into `modules/omada`

`modules/omada` owns *what Omada is*; this module owns *how a Porkbun
DNS-01 cert gets issued and renewed* - two capabilities that happen to be
composed together for `omada01` today but aren't inherently coupled. The
user's own framing ("service groups," plural) is the actual test: a future
service on a different VM needing the same DNS-01-via-Porkbun capability
should be able to compose `modules/porkbun-acme-tls` again with its own
`cert_name`/`domain_names`/`output_dir`, without `modules/omada` - or this
module - needing to change. Folding ACME issuance into `modules/omada`
would tie a generically-useful capability to one service's Quadlet
definition, the same mistake ADR-0008 already un-made once for VM
provisioning ("does this need to change when the next thing comes along"
is ADR-0008's own test, reapplied here).

The seam is drawn the same place ADR-0008 draws it for
`fcos-quadlet-vm`/`modules/omada`: this module's only obligation is
*produce a fullchain/privkey PEM pair at a caller-chosen path, with
caller-chosen filenames, owned by a caller-chosen uid/gid.* Everything
about what a specific service needs from that - the `/cert` volume mount,
the expected filenames, restarting the right unit - stays in the consuming
service's own module (`modules/omada` gained `enable_tls`/`tls_cert_dir`/`acme_service_name`
inputs for exactly this).

### Why the restart trigger is a `systemd.path` unit in `modules/omada`, not a hook inside the certbot container

The certbot container's `--deploy-hook` only copies files - it does not
restart Omada. The alternative, giving the certbot container a Podman
socket (or host PID/dbus access) so its deploy-hook could itself run
`podman restart omada-controller`, was rejected: that grants a
third-party, comparatively less-scrutinized community image
(`infinityofspace/certbot_dns_porkbun`) root-equivalent host control, a
materially larger privilege grant than the DNS API credential it's meant
to protect against leaking. A `systemd.path` unit (`omada-cert-reload.path`,
owned by `modules/omada`, watching `tls_cert_dir/tls.crt`) achieves the
identical outcome - restart within seconds of the cert file changing -
with zero extra container privileges, and keeps "react to my own cert
directory changing" where it belongs: in the module that owns that
directory's consumer.

### Why DNS-01 (not HTTP-01)

DNS-01 needs zero inbound ports - it proves domain ownership by writing an
`_acme-challenge` TXT record via Porkbun's API. The VMs this targets sit
behind RFC1918 addressing with no public inbound path; HTTP-01 would need
port-forwarding or a public reverse proxy this repo doesn't have.
Firewalld configuration is unaffected by this ADR - confirmed, no new
inbound rules of any kind.

### The accepted credential-exposure trade-off

Decision #1 above (on-VM ACME client, not a Terraform-side ACME/DNS
provider) means the Porkbun API key/secret get interpolated into the
rendered Butane/Ignition content in plaintext, which lands in Terraform
state, the CI runner's rendered `.ign` file, and the uploaded install ISO
on Proxmox - not just on the one VM that needs it. Porkbun API keys are
account-wide, not domain-scoped, which makes this a materially bigger
blast radius than this repo's other embedded credential
(`ssh_authorized_key`, a public key with no secrecy requirement to begin
with). This is the accepted cost of decision #1, not a gap this ADR failed
to close - the alternative was already ruled out before this module's
design started. Mitigation available outside Terraform: Porkbun's
dashboard supports restricting an API key to specific egress IPs.

### Ignition-first-boot-only interaction

The renewal loop itself (timer, oneshot certbot invocation, deploy-hook,
`.path`-triggered restart) runs at runtime via systemd on every boot going
forward, the same category as the existing `podman-auto-update.timer` -
not subject to "Ignition only applies on first boot." The *initial* Butane
content that installs all of this **is** subject to that limitation
(ADR-0002) exactly like any other Butane change to an already-provisioned
VM - applying it to the currently-running `omada01` requires the same
manual rebuild+restore runbook as any other Butane edit, not a routine
`terraform apply`.

### Boot-order

`omada.service` (generated by Quadlet from `omada.container`) gets
`After=`/`Requires=` on `acme_service_name`, blocking Omada's first start
until the initial ACME issuance succeeds - chosen over starting Omada
immediately on its own default cert and swapping in the real one later,
because the operator explicitly preferred failing closed over a window
where the controller answers without the intended certificate. The cost:
`omada01`'s first boot now depends on reaching Porkbun's API and Let's
Encrypt over the network. Renewals afterward are decoupled from this gate
entirely - they go through the `.path`-triggered restart, not through
re-satisfying `Requires=`.

## Alternatives considered

- **Terraform-side ACME provider** (e.g. the `acme` Terraform provider
  plus a Porkbun DNS provider for the challenge). Rejected by the
  operator's own decision before this ADR's design started: cert material
  would then live in Terraform state as first-class resources, which was
  explicitly the outcome to avoid.
- **acme.sh instead of certbot.** Rejected: certbot's `--deploy-hook` is a
  cleaner, better-documented mechanism for "run this only on an actual
  renewal" than acme.sh's hook equivalents, and certbot's Porkbun plugin
  ecosystem is comparably mature.
- **Fold ACME issuance into `modules/omada` directly.** Rejected - see
  "Why a separate module" above; fails the same portability test ADR-0008
  already established a precedent for.
- **Two separate certificates** (one for `omada01.canady.cloud`, one for
  `omada.canady.cloud`) instead of one cert with two SANs. Rejected for
  now as unnecessary complexity for one physical controller answering to
  both names - revisit if a genuine `omada02` ever exists as an
  independent host.
- **Grant the certbot container Podman-socket/host restart access**
  instead of a `systemd.path` unit. Rejected - see "Why the restart
  trigger" above; unjustified privilege grant to a third-party image for
  no behavioral benefit over a path unit.

## Consequences

- New module `modules/porkbun-acme-tls`, added to
  `.github/workflows/terraform-pr.yml`'s `validate.matrix.root` (mirrors
  ADR-0008's addition of `modules/omada` there).
- `modules/omada` gains three new inputs (`enable_tls`, `tls_cert_dir`,
  `acme_service_name`), all optional and defaulted off, so existing callers
  are unaffected until they opt in.
- `environments/homelab/omada` gains `module.omada_tls` and three new
  sensitive/plain variables (`porkbun_api_key`, `porkbun_api_secret`,
  `acme_email`), plumbed through CI the same way `proxmox_api_token`
  already is (`TF_VAR_*` env vars sourced from GitHub Actions
  secrets/vars in the `homelab` environment).
- `omada01` (already provisioned) does not get TLS from a routine
  `terraform apply` - it needs the manual rebuild+restore runbook, per the
  Ignition-first-boot-only interaction above. Two pre-flight checks belong
  to that runbook specifically for this change: confirm no certificate was
  ever installed through `omada01`'s controller web UI (a UI-installed
  cert silently overrides the `/cert` volume method via MongoDB), and
  confirm the `nerdit-tech-terraform-state` S3 bucket has encryption at
  rest enabled, since this is the first credential of this sensitivity
  entering that state.
- **Explicitly deferred**: scoping the Porkbun API key to specific egress
  IPs is a mitigation available in Porkbun's own dashboard, not something
  Terraform or this module can enforce - operational follow-up, not a gap
  in this design.
