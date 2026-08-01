# ADR-0010: Porkbun credentials are never a Terraform input - CI seeds them directly over SSH instead

**Status:** Accepted **Date:** 2026-08-01

## Context

This is a same-day incident postmortem and correction to
[ADR-0009](0009-porkbun-dns01-acme-module.md), not an independent design
exercise.

ADR-0009 shipped `modules/porkbun-acme-tls` with `porkbun_api_key`/`porkbun_api_secret`
as `sensitive = true` Terraform variables, interpolated into the rendered
Butane content (a `0600` credentials file written via Ignition). The ADR's
own "accepted credential-exposure trade-off" section already flagged that
this value would end up in Terraform state, the CI runner's rendered
`.ign` file, and the uploaded install ISO - accepted as the cost of
keeping cert material out of Terraform's own ACME-provider state.

What that section did not anticipate: `environments/homelab/omada`'s PR
(#4) had its `terraform-pr.yml` plan job run for real, and its
plan-comment step (`steps.plan.outputs.stdout`, posted verbatim as a
sticky PR comment) contained the real `porkbun_api_secret` value in
plaintext, readable by anyone with access to the PR.

### Root cause

Terraform's sensitivity-mark propagation worked correctly through every
*pure Terraform-language* hop: `var.porkbun_api_secret` (sensitive) into
`templatefile()` (a built-in function, evaluated inside Terraform's own
expression graph) into `modules/porkbun-acme-tls`'s `butane_snippet`
output (which `terraform validate` itself refused to let through without
an explicit `sensitive = true`, correctly detecting the derivation) into
the `extra_butane_snippets` list literal into `modules/fcos-quadlet-vm`'s
variable of the same name.

It broke at `data.ct_config.merged` (the `poseidon/ct` provider), which
shells out to Butane to transpile the YAML into Ignition JSON. This is a
provider RPC boundary: Terraform's core does not send sensitivity marks
across it, and rebuilding them afterward relies on path-based
correspondence between the config that was sent and the value that came
back. Butane's own transpilation defeats that correspondence for exactly
this case: a `storage.files[].contents.inline: |` block (where the
sensitive value lived, under the `content`/`snippets` config arguments)
gets compiled into a `source: "data:,<percent-encoded>"` field in the
Ignition JSON - a new attribute at a new path, produced by logic internal
to the `ct` provider's Go code, that Terraform has no way to know
originated from a marked input. `ct`'s schema also doesn't declare its
`rendered` output attribute `Sensitive: true`. The result: `data.ct_config.merged.rendered`,
and everything computed from it downstream
(`local_file.rendered_ignition`, `terraform_data.ignition_fingerprint`,
`terraform_data.custom_iso_build`, `proxmox_virtual_environment_file.custom_iso`),
carried no sensitivity mark at all - despite being built entirely from
values that were, at every prior hop, correctly marked.

This is not specific to `ct` or Butane - it's a general property of any
Terraform provider whose computed output isn't a direct pass-through of a
marked input at the same schema path. `sensitive = true` on a variable is
weaker protection than it appears once a value crosses a provider
boundary and comes back reshaped.

### Immediate response (before this ADR)

- The exposed PR comment was deleted.
- The `tfplan-omada` artifact from the run that generated it was deleted
  (it contained the same plan text).
- The entire workflow run was deleted (removes its logs, which held the
  same plan text a second time).
- The leaked Porkbun API key was rotated in Porkbun's dashboard, on the
  operator's own action - treated as an account-wide incident per the
  already-documented understanding that Porkbun API keys aren't
  domain-scoped.

These reduce the window and copies of exposure but don't undo it -
anyone who read the comment before deletion already has the value. The
rotation is the actual remediation for that; this ADR is the remediation
for it not happening again.

## Decision

`modules/porkbun-acme-tls` no longer accepts the Porkbun API key/secret as
Terraform input, in any form. The module only:

- creates the empty, root-only (`0700`) `/etc/porkbun-credentials`
  directory via Ignition,
- takes a `credentials_file` variable (a **path**, defaulting to
  `/etc/porkbun-credentials/<cert_name>.ini`, not content) that the
  certbot invocation reads from,
- and exposes that resolved path as a `credentials_file` output, so the
  environment layer/operator knows exactly where to put the real file.

The actual `dns_porkbun_key=.../dns_porkbun_secret=...` content is written
by CI, automatically, but **out-of-band from Terraform entirely**: a new
step in `terraform-apply.yml`'s `apply` job, running after `terraform
apply`, reads `PORKBUN_API_KEY`/`PORKBUN_API_SECRET` directly from GitHub
Actions secrets into its own shell environment and SSHes to `omada01` to
write the file - the value never enters a Terraform variable, a
`.tf`/`.tftpl` file, or `terraform plan`/`apply`'s own output at any point.
GitHub Actions' own secret redaction (which masks the literal registered
`secrets.*` value anywhere it appears in logs, unlike Terraform's mark
propagation, which only tracks a value through its own expression graph)
is what protects this value in the one place it's genuinely still
processed by automation. SSH access itself doesn't depend on Omada being
up: it's part of the base Ignition bootstrap (`ssh_authorized_key`),
independent of `omada.service` (gated on the ACME unit succeeding).

This is a structural fix, not a tighter redaction: **the module cannot
leak a value it never receives.** `terraform plan`/`apply` output for
`modules/porkbun-acme-tls` is now safe to post anywhere, including CI PR
comments, without relying on Terraform's sensitivity-propagation working
correctly across a provider boundary it turned out not to. The credential
still flows through CI automation - just through a path (a shell step's
own env, masked by GitHub's log redaction) that never touches Terraform's
plan/state/output machinery at all.

## Alternatives considered

- **Keep the credential as a Terraform variable, fix the plan-comment
  workflow instead** (e.g. skip posting the diff for resources touched by
  `module.omada_tls`, or truncate/replace the comment body with a generic
  pass/fail). Rejected: this only closes the one exposure surface that
  happened to be discovered. The same unmarked `ct_config.rendered` value
  still sits in Terraform state and the CI runner's rendered `.ign` file
  in plaintext (both already-accepted surfaces per ADR-0009), and nothing
  stops a *different* future consumer of this state/output from hitting
  the same unredacted value some other way - e.g. `terraform show`, a
  different CI step, a teammate running `plan` locally and pasting output
  into Slack. Fixing the workflow treats the symptom; the module still
  can't be trusted with a secret.
- **Explicitly wrap the value with `sensitive()` at the point it enters
  `ct_config`'s config.** Investigated and rejected: `sensitive()` marks a
  value for propagation *forward* through Terraform's own expression
  graph, but the break here happens *after* the provider RPC round-trip,
  on a value Terraform's core reconstructs from the provider's response
  without any marks to propagate in the first place. There's no
  expression to wrap on the output side - `data.ct_config.merged.rendered`
  is computed by the provider, not by a Terraform expression this module
  controls.
- **Switch away from `poseidon/ct` to some other Butane-transpiling
  mechanism that does preserve marks.** Not investigated as a real option:
  the same class of problem (a value reshaped by anything outside
  Terraform's own expression evaluator) would recur with any transpilation
  step, provider-based or not - the fix needed to be "don't put the secret
  in front of any transpilation step," not "find a transpiler that
  happens to preserve marks."
- **Require a human to SSH in and write the file manually**, as an
  explicit runbook step, instead of having CI do it. This was the first
  version of this ADR. Superseded before merge, on the operator's explicit
  request: they wanted credential delivery to stay automated end-to-end
  through CI/CD, just without the credential passing through Terraform or
  Butane specifically. A CI-driven SSH step achieves both - automated, and
  outside Terraform's plan/state/output machinery.

## Consequences

- `modules/porkbun-acme-tls`'s `variables.tf` loses `porkbun_api_key`/`porkbun_api_secret`,
  gains `credentials_file` (default `null`, resolved in `main.tf` via
  `coalesce(var.credentials_file, "/etc/porkbun-credentials/${var.cert_name}.ini")`).
  `outputs.tf` gains `credentials_file`; `butane_snippet` is no longer
  marked `sensitive = true` (nothing sensitive remains in it).
- `environments/homelab/omada` drops `porkbun_api_key`/`porkbun_api_secret`
  variables entirely and gains an `omada_tls_credentials_file` output,
  read by the new CI step to know where to write the file.
  `.github/workflows/terraform-pr.yml` drops
  `TF_VAR_porkbun_api_key`/`TF_VAR_porkbun_api_secret` entirely
  (`TF_VAR_acme_email` stays - it was never secret). `terraform-apply.yml`
  drops the same two `TF_VAR_*` lines from its `plan`/`apply` jobs' Terraform
  env, but its `apply` job gains a new step ("Seed Porkbun credentials on
  omada01") that reads `PORKBUN_API_KEY`/`PORKBUN_API_SECRET` directly as
  step-scoped env vars (not `TF_VAR_*` - they never reach Terraform) and
  SSHes them to the VM after `terraform apply` completes.
- **New prerequisite**: an `SSH_PRIVATE_KEY` secret in the `homelab`
  GitHub Actions environment, paired with the existing `vars.SSH_PUBLIC_KEY`
  baked into every VM's base Ignition config. This is new - no prior
  workflow in this repo SSHed into a provisioned VM (ADR-0006/ADR-0007
  specifically removed the need for SSH *to Proxmox*; this is SSH to the
  guest VM itself, a different connection).
- **New failure mode this step has to handle explicitly**: `omada.service`
  has `Restart=always` and will fail its `Requires=acme-omada01.service`
  dependency repeatedly during the window between first boot and this
  step actually writing the credentials file. With systemd's default
  `StartLimitBurst=5`/`StartLimitIntervalSec=10`, that retry loop hits the
  start-limit and gives up (permanently failed, no more auto-retries)
  within the first few seconds - long before the credentials exist. The
  CI step accounts for this: after writing the file, it explicitly runs
  `systemctl reset-failed` followed by `systemctl start` on both
  `acme-omada01.service` and `omada.service`, rather than assuming the
  unit's own restart loop will eventually succeed on its own.
- The CI step's SSH connection uses `StrictHostKeyChecking=no` - a
  deliberate homelab-scale trade-off (private LAN, self-hosted runner
  already on that network per ADR-0005, host keys legitimately change on
  every rebuild since these are disposable single-instance VMs re-installed
  from a fresh ISO) rather than maintaining `known_hosts` pinning across
  rebuilds. Not appropriate to copy onto anything internet-facing.
- **Explicitly not addressed by this ADR**: whether other secrets already
  flowing through this repo's existing Terraform (e.g.
  `proxmox_api_token`, used directly as a `provider` block argument rather
  than templated Butane content) have a comparable gap. Provider-block
  arguments are a different, narrower case - HashiCorp's provider
  configuration handling has stronger sensitivity guarantees than an
  arbitrary computed data-source attribute - but that assumption hasn't
  been independently verified against this repo's actual CI output the
  way this incident forced verification here. Worth a deliberate check,
  not assumed safe by analogy.
