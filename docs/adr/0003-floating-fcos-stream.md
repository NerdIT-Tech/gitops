# ADR-0003: Track the latest FCOS release in a stream, don't pin a specific version

**Status:** Accepted **Date:** 2026-07-30 (retroactively documented; predates this ADR log)

## Context

`modules/fcos-quadlet-vm` resolves the FCOS image to download from the live
[CoreOS stream metadata endpoint](https://builds.coreos.fedoraproject.org)
(`data.http.fcos_stream`) at `terraform plan` time, for whichever channel
`var.fcos_stream` selects (default `stable`). It does not pin to a specific
FCOS release/version.

Fedora CoreOS ships `zincati` by default, which this module enables in
`base.bu.tftpl` with a periodic update strategy — the running VM stays
current on its own, independent of whatever image it was originally booted
from.

## Decision

Keep tracking the latest release in the configured stream rather than
pinning a specific FCOS version. `var.fcos_stream` selects the channel
(`stable`/`testing`/`next`); the specific release within that channel is
always "whatever's current."

## Alternatives considered

- **Pin a specific `fcos_version`** — makes the initial image reproducible
  from the repo alone, and removes the `terraform plan` noise described
  below. Rejected because zincati already makes the *running* system's
  version a moving target post-boot regardless of what's pinned at
  provisioning time — pinning would only give a reproducible *starting*
  point, not a reproducible running state, at the cost of needing manual
  version bumps to pick up new images for VM rebuilds.

## Consequences

- `terraform plan` can show
  `proxmox_virtual_environment_download_file.fcos_image` wanting to
  replace whenever Fedora publishes a new stable release, even with
  nothing else in the repo changed. This is expected noise, not a bug —
  don't chase it as a regression.
- The already-provisioned VM's own disk is protected from this via
  `lifecycle.ignore_changes` on `disk[0].file_id` in `main.tf` — a new
  image being downloaded does not, by itself, force the VM to rebuild.
- "What FCOS build is currently running" is not reproducible from the repo
  at any point in time — it depends on both whatever was live at the VM's
  last provisioning/rebuild and however far zincati has since updated it.
