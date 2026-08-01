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
`omada.canady.cloud` via Porkbun DNS-01, entirely on-VM. **No Porkbun
credential of any kind passes through Terraform** - not state, not the
rendered `.ign` file, not the install ISO, not CI's plan-comment output.
This isn't a redaction claim, it's structural: `module.omada_tls` takes no
credential input at all. See [ADR-0010](../../../docs/adr/0010-porkbun-credential-out-of-band.md)
for why - a real Porkbun API secret leaked into a GitHub PR comment under
this environment's original design, because Terraform's sensitivity marks
didn't survive the `poseidon/ct` provider's Butane transpilation. That
secret has been rotated and the leaked PR comment/artifact/run log purged;
the fix here is the module no longer being able to leak what it never
receives.

**How the credential actually reaches the VM**: `.github/workflows/terraform-apply.yml`'s
`apply` job runs a dedicated step ("Seed Porkbun credentials on omada01")
after `terraform apply` completes. It reads `PORKBUN_API_KEY`/`PORKBUN_API_SECRET`
directly from GitHub Actions secrets into its own shell (never a
`TF_VAR_*`, never seen by Terraform), waits for `omada01` to become
reachable over SSH (first boot runs an unattended install + reboot that
`terraform apply` doesn't wait for), writes the credentials file at
`module.omada_tls.credentials_file`'s path (surfaced as this root's
`omada_tls_credentials_file` output, default
`/etc/porkbun-credentials/omada01.ini`), and explicitly starts
`acme-omada01.service` then `omada.service` - the controller's own
`Restart=always` loop will have already hit systemd's default start-limit
and given up by the time this step runs, so it can't be left to retry
this on its own. This step is idempotent and re-runs on every apply,
including ones where nothing changed. Requires an `SSH_PRIVATE_KEY`
secret in the `homelab` GitHub Actions environment, paired with the
existing `vars.SSH_PUBLIC_KEY`.

**Before enabling this on `omada01`, as part of the rebuild runbook
below:**

1. **Confirm no certificate has ever been installed through `omada01`'s
   controller web UI.** A UI-installed cert lives in MongoDB and silently
   overrides the `/cert` volume method `module.omada_service`'s
   `enable_tls` relies on.
2. **Confirm `SSH_PRIVATE_KEY`, `PORKBUN_API_KEY`, and `PORKBUN_API_SECRET`
   are set in the `homelab` GitHub Actions environment** before merging -
   without them the new CI step in `terraform-apply.yml` will fail after
   `terraform apply` has already rebuilt the VM, leaving `omada.service`
   stuck waiting on a credentials file nothing wrote.
3. **Confirm your Porkbun API key's blast radius regardless.** Porkbun API
   keys are account-wide by default (every domain on the account, not just
   `canady.cloud`) - restrict it to known egress IPs in Porkbun's dashboard
   if you can. Being kept out of Terraform doesn't change what the key can
   do if `omada01` itself is compromised; it only removes the extra copies
   Terraform would otherwise have made.

`omada.service` is gated (`After=`/`Requires=`) on `acme-omada01.service`
succeeding - fails closed by design, at the cost of first boot now
depending on the CI step above completing successfully. Renewals after the
first issuance are decoupled from that gate - a `systemd.path` unit
restarts the controller only when the cert file actually changes, no CI
involvement needed.

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
