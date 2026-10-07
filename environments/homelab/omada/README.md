# Omada environment root

Provisions the homelab's TP-Link Omada SDN Controller as `omada01`
(`vm_id = 9010`) on Proxmox. Own Terraform root and state key
(`gitops/omada/terraform.tfstate`) per [ADR-0004](../../../docs/adrs/0004-per-service-terraform-root-and-state.md).

## Composition

`omada.tf` wires together four module calls (see
[ADR-0008](../../../docs/adrs/0008-decouple-omada-service-from-vm-provisioning.md)
for why it's split this way):

- `module.omada_tls` ([`modules/porkbun-acme-tls`](../../../modules/porkbun-acme-tls)) -
  *how the TLS cert gets issued and renewed*: a Porkbun DNS-01 certbot
  loop. No provider, no resources - just renders Butane YAML and outputs
  `butane_snippet`, `acme_service_name`, and `credentials_file`.
- `module.omada_service` ([`modules/omada`](../../../modules/omada)) - *what*
  Omada is: the Quadlet unit, firewalld service, storage layout. No
  provider, no resources - just renders Butane YAML and outputs it as
  `butane_snippet`. TLS is left off (`enable_tls` at its default `false`) -
  see "TLS" below for why.
- `module.omada_nginx` ([`modules/nginx-reverse-proxy`](../../../modules/nginx-reverse-proxy)) -
  *how the management UI is reached over TLS*: an nginx container that
  terminates HTTPS and proxies to the controller's plain-HTTP management
  port on `127.0.0.1`. Generic, not Omada-specific - see that module's
  README.
- `module.omada` ([`modules/fcos-quadlet-vm`](../../../modules/fcos-quadlet-vm)) -
  *where* it runs: the Proxmox VM (sizing, network, tags, ISO build/upload).
  Takes all three of the above modules' `butane_snippet` outputs as
  elements of `extra_butane_snippets`.

If Omada ever needs to run somewhere other than Proxmox, only the fourth
module call changes - `module.omada_tls`, `module.omada_service`, and
`module.omada_nginx`, and their inputs, are unaffected.

## TLS

**nginx (`module.omada_nginx`), not the controller, terminates TLS.** The
controller (`module.omada_service`) stays on plain HTTP on
`manage_http_port` (default `8088`), reachable only via `127.0.0.1` -
`module.omada_nginx`'s container shares the same host network namespace
(`Network=host` on both). nginx presents the certificate for
`omada01.canady.cloud`/`omada.canady.cloud` on `443` and 301-redirects
plaintext `80` to it. This is a deliberate single point of TLS ownership:
before this, `module.omada_service`'s own `enable_tls` mounted the cert
straight into the controller, which converted it into a Java keystore for
its own Jetty HTTPS listener - that still works today (`enable_tls`
still exists on `modules/omada`) but is now left at its default `false`
here, so exactly one thing on `omada01` ever presents a certificate for
these hostnames. See [`modules/nginx-reverse-proxy`](../../../modules/nginx-reverse-proxy)'s
README for the module itself, and its "TLS: this module is the sole
terminator" section for why mixing the two back together is a maintenance
trap, not defense in depth.

Only the management UI is proxied. The captive portal
(`portal_http_port`/`portal_https_port`) and EAP discovery (UDP
`29810`-`29813`, TCP `29814`) are not HTTP-proxyable protocols and stay
exactly as they were - directly exposed by `module.omada_service`'s own
firewalld service, unchanged.

`module.omada_tls` ([`modules/porkbun-acme-tls`](../../../modules/porkbun-acme-tls),
[ADR-0009](../../../docs/adrs/0009-porkbun-dns01-acme-module.md)) issues and
renews a Let's Encrypt certificate for `omada01.canady.cloud` +
`omada.canady.cloud` via Porkbun DNS-01, entirely on-VM. **No Porkbun
credential of any kind passes through Terraform** - not state, not the
rendered `.ign` file, not the install ISO, not CI's plan-comment output.
This isn't a redaction claim, it's structural: `module.omada_tls` takes no
credential input at all. See [ADR-0010](../../../docs/adrs/0010-porkbun-credential-out-of-band.md)
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
`acme-omada01.service` then `omada-proxy.service` (nginx, the unit gated on
TLS - see below) - its own `Restart=always` loop will have already hit
systemd's default start-limit and given up by the time this step runs, so
it can't be left to retry this on its own. `omada.service` itself (the
controller) needs no equivalent nudge - it isn't gated on TLS and will
already be up. This step is idempotent and re-runs on every apply,
including ones where nothing changed. Requires an `SSH_PRIVATE_KEY`
secret in the `homelab` GitHub Actions environment, paired with the
existing `vars.SSH_PUBLIC_KEY`.

**Before enabling this on `omada01`, as part of the rebuild runbook
below:**

1. **Confirm no certificate has ever been installed through `omada01`'s
   controller web UI.** This matters less than it used to now that nginx,
   not the controller, is the one presenting a certificate to clients - but
   a UI-installed cert still lives in MongoDB and would still affect the
   controller's own Jetty HTTPS listener on `manage_https_port` if
   `module.omada_service`'s `enable_tls` is ever turned back on directly
   (see "TLS" above for why it's off by default now).
2. **Confirm `SSH_PRIVATE_KEY`, `PORKBUN_API_KEY`, and `PORKBUN_API_SECRET`
   are set in the `homelab` GitHub Actions environment** before merging -
   without them the CI step in `terraform-apply.yml` will fail after
   `terraform apply` has already rebuilt the VM, leaving `omada-proxy.service`
   (nginx) stuck waiting on a credentials file nothing wrote.
3. **Confirm your Porkbun API key's blast radius regardless.** Porkbun API
   keys are account-wide by default (every domain on the account, not just
   `canady.cloud`) - restrict it to known egress IPs in Porkbun's dashboard
   if you can. Being kept out of Terraform doesn't change what the key can
   do if `omada01` itself is compromised; it only removes the extra copies
   Terraform would otherwise have made.
4. **Confirm `443` (and `80`, for the HTTP→HTTPS redirect) can actually
   reach `omada01`** from wherever `omada.canady.cloud`/`omada01.canady.cloud`
   are meant to resolve/route to it - DNS records and any upstream
   firewall/NAT rule are outside this Terraform root entirely, this only
   opens the ports in `omada01`'s own `firewalld`.

`omada-proxy.service` (nginx) is gated (`After=`/`Requires=`) on
`acme-omada01.service` succeeding - fails closed by design, at the cost of
first boot now depending on the CI step above completing successfully.
`omada.service` (the controller) is not gated on it and starts
independently, since it no longer serves the certificate itself. Renewals
after the first issuance are decoupled from that gate - a `systemd.path`
unit reloads nginx only when the cert file actually changes (a graceful
`nginx -s reload`, not a restart - see
[`modules/nginx-reverse-proxy`](../../../modules/nginx-reverse-proxy)'s
README), no CI involvement needed.

## This is a live, stateful production VM

`omada01` holds real controller state on its own disk
(`/var/lib/omada/data`) - device inventory, adopted APs, settings. There is
no snapshot/backup automation here.

Ignition only applies on **first boot** (ADR-0002/ADR-0003). A Butane change
here - whether it's `modules/omada`'s inputs above, `module.omada_nginx`'s,
`module.omada_tls`'s, or `modules/fcos-quadlet-vm` itself - does **not** get
re-applied to the already-running VM. This applies to the TLS wiring above
too: retargeting `module.omada_nginx` (a new hostname, a different upstream
port, a bumped `nginx_image_tag`) does not change anything on the
currently-running `omada01` by itself - that VM needs the same
rebuild+restore runbook below as any other Butane change, even though
`module.omada_nginx`'s own container holds no state of its own (see
[`modules/nginx-reverse-proxy`](../../../modules/nginx-reverse-proxy)'s
README's "Stateless" section - it's `omada01` as a whole, via
`module.omada_service`'s data, that forces the manual runbook, not this
module). Watch
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
