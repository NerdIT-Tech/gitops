# Omada environment root

Provisions the homelab's TP-Link Omada SDN Controller as `omada01`
(`vm_id = 9010`) on Proxmox. Own Terraform root and state key
(`gitops/omada/terraform.tfstate`) per [ADR-0004](../../../docs/adr/0004-per-service-terraform-root-and-state.md).

## Composition

`omada.tf` wires together two module calls (see
[ADR-0008](../../../docs/adr/0008-decouple-omada-service-from-vm-provisioning.md)
for why it's split this way):

- `module.omada_service` ([`modules/omada`](../../../modules/omada)) - *what*
  Omada is: the Quadlet unit, firewalld service, storage layout. No
  provider, no resources - just renders Butane YAML and outputs it as
  `butane_snippet`.
- `module.omada` ([`modules/fcos-quadlet-vm`](../../../modules/fcos-quadlet-vm)) -
  *where* it runs: the Proxmox VM (sizing, network, tags, ISO build/upload).
  Takes both `module.omada_service.butane_snippet` and
  `module.omada_tls.butane_snippet` as elements of `extra_butane_snippets`.

If Omada ever needs to run somewhere other than Proxmox, only the third
module call changes - `module.omada_service`, `module.omada_tls`, and their
inputs are unaffected.

## TLS

`module.omada_tls` ([`modules/porkbun-acme-tls`](../../../modules/porkbun-acme-tls),
[ADR-0009](../../../docs/adr/0009-porkbun-dns01-acme-module.md)) issues and
renews a Let's Encrypt certificate for `omada01.canady.cloud` +
`omada.canady.cloud` via Porkbun DNS-01, entirely on-VM - no cert material
passes through Terraform's own state as ACME provider resources (the
Porkbun API key/secret do, though - see the module's README for that
trade-off before setting `porkbun_api_key`/`porkbun_api_secret` here).

Before enabling this on `omada01`:

- **Confirm no certificate has ever been installed through `omada01`'s
  controller web UI.** A UI-installed cert lives in MongoDB and silently
  overrides the `/cert` volume method `module.omada_service`'s `enable_tls`
  relies on.
- **Confirm your Porkbun API key's blast radius.** Porkbun API keys are
  account-wide by default (every domain on the account, not just
  `canady.cloud`) - restrict it to known egress IPs in Porkbun's dashboard
  if you can, since this key ends up embedded in Terraform state, the CI
  runner's rendered `.ign` file, and the uploaded install ISO, not just on
  `omada01` itself.
- **Confirm the `nerdit-tech-terraform-state` S3 bucket has encryption at
  rest enabled.** This change adds a live, reusable API credential to state
  for the first time in this environment.

`omada.service`'s first start is gated on a successful initial ACME
issuance (`After=`/`Requires=` on `module.omada_tls.acme_service_name`) -
first boot now depends on `omada01` reaching Porkbun's API and Let's
Encrypt over the network. Renewals afterward are decoupled from that gate;
a `systemd.path` unit restarts the controller only when the cert file
actually changes.

## This is a live, stateful production VM

`omada01` holds real controller state on its own disk
(`/var/lib/omada/data`) - device inventory, adopted APs, settings. There is
no snapshot/backup automation here.

Ignition only applies on **first boot** (ADR-0002/ADR-0003). A Butane change
here - whether it's `modules/omada`'s inputs above, `module.omada_tls`, or
`modules/fcos-quadlet-vm` itself - does **not** get re-applied to the
already-running VM. This applies to the TLS wiring above too: enabling it
here does not turn TLS on for the currently-running `omada01` by itself -
that VM needs the same rebuild+restore runbook below as any other Butane
change. Watch
`terraform plan`'s `omada_ignition_fingerprint` output: a diff there means
this environment's config has drifted from what the running VM actually has,
and applying it silently does nothing to the VM itself (it only rebuilds and
re-uploads the install ISO for next time). To actually apply it, follow the
manual rebuild+restore runbook in
[`fcos-quadlet-vm`'s README](../../../modules/fcos-quadlet-vm/README.md#ignition-only-runs-once-and-what-that-means-for-edits) -
back up `/var/lib/omada/data` first.

## Applying

Same credential/tooling requirements as every other service root in this
repo - see [`gha-runner`'s README](../gha-runner/README.md) for the full
list (Proxmox API token, SSH public key, MinIO/S3 credentials,
`coreos-installer` installed locally for the ISO build step). This root has
no service-specific variables beyond the shared ones in `variables.tf`.
