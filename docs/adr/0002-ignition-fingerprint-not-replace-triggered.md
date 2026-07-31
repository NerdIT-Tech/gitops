# ADR-0002: Track Ignition drift via a visible fingerprint, not `replace_triggered_by`

**Status:** Accepted **Date:** 2026-07-30 (retroactively documented; predates this ADR log)

## Context

Ignition applies once, on first boot. If `extra_butane_snippets` or
`butane/base.bu.tftpl` change for an already-provisioned VM, Terraform will
happily re-render the config, rebuild the custom install ISO, and upload
it (see [ADR-0007](0007-kvm-arguments-requires-root-pam.md) for how
Ignition is delivered), but the running VM never sees it — Ignition does
not re-run on reboot. Left unaddressed, this drift is silent: `terraform
plan` shows the ISO-build/upload resources updating and nothing else,
giving no signal that the *running* VM is now out of sync with the repo.

The VMs this module provisions are stateful, single-instance appliances
(e.g. Omada, with its controller data on the VM's own disk). Automatically
recreating the VM whenever Butane content changes would apply the new
config, but would also destroy that data disk.

## Decision

`terraform_data.ignition_fingerprint` hashes the rendered Butane content
and is exposed as an output. A diff on that output in `terraform plan` for
an existing VM is the signal: "this VM's actual config no longer matches
what's in the repo." It is deliberately **not** wired into
`replace_triggered_by` on the VM resource.

## Alternatives considered

- **Wire the fingerprint into `replace_triggered_by`** — makes drift
  self-healing (any Butane edit forces a rebuild), but auto-destroys the
  data disk on every routine config change, including changes unrelated to
  the stateful data (e.g. a firewall port tweak). Rejected: too destructive
  a default for a homelab's only copy of appliance data.
- **Ignore drift entirely** (no fingerprint) — simplest, but Butane edits
  would silently do nothing on existing VMs with no way to notice short of
  manually diffing rendered output. Rejected as the status quo this ADR
  moves away from.

## Consequences

- Applying a Butane change to an existing VM requires a manual rebuild:
  back up the stateful data, destroy/recreate the VM (or `taint` + apply),
  restore the data, verify. See the module README's rebuild runbook.
- There is currently no automation for that runbook — the manual gate is
  deliberate given the blast radius of getting it wrong, but it does mean
  drift can sit unaddressed if nobody looks at `plan` output. This is part
  of the case for CI running `terraform plan` on every PR (see the
  `terraform-pr.yml` workflow) rather than relying on someone remembering
  to run it locally.
