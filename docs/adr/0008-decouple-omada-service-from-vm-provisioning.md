# ADR-0008: Decouple the Omada service definition (`modules/omada`) from VM provisioning (`modules/fcos-quadlet-vm`)

**Status:** Accepted **Date:** 2026-07-31

## Context

Before this ADR, Omada's Quadlet unit, firewalld service, and storage
layout lived at `services/omada/butane/omada.bu.tftpl` - a bare Butane
template with no Terraform interface of its own, rendered directly via
`templatefile()` inside `environments/homelab/omada/omada.tf` and passed
straight into `modules/fcos-quadlet-vm`'s `extra_butane_snippets`. This is
still exactly how `gha-runner` works today, and there was nothing wrong
with it as a pattern - it's simple, and it's this repo's default shape for
a service.

The request that prompted this ADR was explicit: abstract Omada into a real
module, and do it in a way that doesn't assume Proxmox - "ideally it should
be setup so this could run in azure or gcp or any vm host." Two different
things were being asked for, and they matter separately:

1. Give Omada's service definition an actual module interface (inputs,
   outputs, its own `terraform validate`), instead of a template path
   reached into from the environment root.
2. Make sure that interface doesn't quietly assume Proxmox, so a
   Proxmox-alternative VM-provisioning module could consume it later
   without reshaping it.

`modules/fcos-quadlet-vm` is, and has to remain, Proxmox-specific in its
resources (`proxmox_virtual_environment_vm`, `proxmox_virtual_environment_file`)
- that's not something this ADR changes or could change without a rewrite
unrelated to Omada. What *can* be made portable is the half of the problem
that was never inherently Proxmox-shaped in the first place: the rendered
Butane/Ignition content describing what Omada is. That content doesn't
reference Proxmox anywhere - it's plain Quadlet/firewalld/systemd config
that would look identical if the VM under it were booted by Azure, GCP, or
bare `libvirt`.

## Decision

Split the service definition out into its own module, `modules/omada`:

- **Inputs**: `omada_image_tag`, `container_puid`/`container_pgid`,
  `timezone`, and the four controller-configurable ports
  (`manage_http_port`, `manage_https_port`, `portal_http_port`,
  `portal_https_port`). No Proxmox-shaped inputs (no `vm_id`, no
  `network_bridge`, nothing sizing- or hypervisor-related) - those stay
  where they belong, in the environment's call to the VM-provisioning
  module.
- **Output**: `butane_snippet`, a single rendered Butane YAML string.
- **No resources, no data sources, no `required_providers`.** The module
  is pure `templatefile()` plus a couple of `locals` for port
  deduplication. It cannot fail a `terraform validate` for provider
  reasons and needs no credentials to plan.
- `services/omada/` is removed; `butane/omada.bu.tftpl` moves to
  `modules/omada/butane/omada.bu.tftpl`. A module that's meant to be a
  self-contained, portable unit shouldn't reach outside its own directory
  for a template it owns, the same way `fcos-quadlet-vm` already owns
  `butane/base.bu.tftpl` internally rather than sourcing it from
  elsewhere.

`environments/homelab/omada/omada.tf` now composes two module calls:
`module.omada_service` (`modules/omada`) feeds its `butane_snippet` output
into `module.omada` (`modules/fcos-quadlet-vm`), unchanged in name, source,
and every other argument except `extra_butane_snippets`'s value now coming
from the new module instead of an inline `templatefile()` call.

### The portability contract

`modules/omada`'s only obligation to whatever provisions the VM is: *accept
these inputs, produce a rendered Ignition-mergeable Butane/Ignition
snippet.* A hypothetical alternate VM-provisioning module (Azure, GCP,
libvirt, ...) would need to, symmetrically:

- Accept a list (or equivalent) of pre-rendered Butane/Ignition snippet
  strings the same shape as `fcos-quadlet-vm`'s `extra_butane_snippets`,
  merge them with its own base bootstrap the same way (Ignition's native
  config-merge, or equivalent), and boot a Fedora CoreOS (or other
  Ignition-consuming) image with the result. Concretely, on the two
  platforms named in the request: Azure's FCOS gallery images accept
  Ignition via `custom_data`; GCP's FCOS images accept it via the
  `user-data` instance metadata key. Both are documented, native paths -
  neither needs this repo's ISO-customization workaround, which exists
  specifically because of Proxmox's `args`-field restriction (ADR-0007),
  not because Ignition delivery is hard in general.
- Own whatever sizing/networking/identity/tagging shape is idiomatic to
  that platform (Azure VM size + resource group + NSG; GCP machine type +
  project + VPC; ...) - these don't need to mirror
  `vm_cpu_cores`/`network_bridge`/`vlan_id` 1:1, they just need to be that
  platform's own equivalent, wired into the environment root the same way.
- Expose at minimum an IP/address output and *some* drift-visibility
  signal for "the rendered config no longer matches what's running" -
  it doesn't have to be named `ignition_fingerprint` or implemented
  identically, but ADR-0002's underlying principle (surface drift, don't
  silently auto-recreate a stateful appliance) should carry over to any
  provisioning module used for a stateful service.

Nothing about this list requires touching `modules/omada` again. That's the
actual test of whether the boundary was drawn in the right place.

## Alternatives considered

- **Leave Omada as a bare `templatefile()` call, just document the
  portability intent.** Rejected - this achieves nothing enforceable. The
  boundary the request asked for (service definition genuinely reusable
  against a different provisioner) needs an actual module interface with
  its own inputs/outputs/validate, not a comment. This is also exactly
  `gha-runner`'s current shape, which is fine for `gha-runner` but doesn't
  answer the question that was asked for Omada specifically.
- **One monolithic multi-cloud VM-provisioning module**, with conditionals
  inside `fcos-quadlet-vm` (or a new module) switching between
  Proxmox/Azure/GCP resources based on a variable. Rejected on this repo's
  own terms: the platform-engineering guidance for this repo explicitly
  prefers composing modules over forking/growing one, and a conditional
  monolith would force every environment to declare every cloud's provider
  in `required_providers` regardless of which one it actually uses -
  worse than today, not better.
- **Build working `modules/azure-vm` and/or `modules/gcp-vm` counterparts
  now**, so the portability claim is demonstrated end-to-end rather than
  asserted. Deferred, not rejected outright - see Consequences.

## Consequences

- `services/omada/` no longer exists. `services/gha-runner/` is
  deliberately left as-is - not every service needs to graduate to a full
  module, and this ADR isn't a mandate to convert it. Promote a service to
  its own module when something actually needs the boundary (here:
  portability across provisioning modules), not by default.
- `environments/homelab/omada/omada.tf` gains a second module block
  (`module.omada_service`). `module.omada`'s block name, source, and every
  argument except `extra_butane_snippets` are unchanged, and
  `module.omada_service` has zero resources of its own - so this is a
  state-safe refactor for the resources already tracked for `omada01`
  (verified by inspection; see the accompanying PR/session notes for the
  `terraform plan -backend=false`/module-graph check, since this sandbox
  has no real Proxmox/MinIO credentials to run a real `plan` against). The
  rendered `butane_snippet` content was written to match the pre-refactor
  template byte-for-byte for the values `environments/homelab/omada`
  actually passes today, so `omada_ignition_fingerprint` should not show a
  diff either - but this is exactly the kind of thing to double-check
  against the real `terraform plan` output before applying, not to take on
  faith from this ADR.
- `.github/workflows/terraform-pr.yml`'s `validate.matrix.root` gains
  `modules/omada` (it has its own `versions.tf`, even though that file
  declares no providers - see `modules/omada/versions.tf`'s own comment for
  why). `plan.matrix.service` is unchanged - `modules/omada`, like
  `modules/fcos-quadlet-vm`, has no state of its own to plan.
- `.claude/hooks/terraform-check.sh`'s path-to-root mapping, previously
  hardcoded to recognize only `modules/fcos-quadlet-vm/*`, is generalized
  to route any `modules/<name>/*` edit to `modules/<name>` - it needed to
  stop assuming there would only ever be one module the moment a second one
  existed.
- **Explicitly deferred**: actual `modules/azure-vm`/`modules/gcp-vm` (or
  equivalent) implementations. This repo has no Azure/GCP credentials,
  provider configuration, or environment precedent today. Building one now
  would be unverified against any real cloud - exactly the kind of
  hypothetical-over-prototyped design ADR-0007 avoided by insisting on a
  live-host prototype before landing a decision, and there's no reason to
  hold this ADR to a lower bar. The actual, load-bearing portability work -
  making sure `modules/omada` doesn't need to change when that module
  eventually gets written - is done by this ADR. Writing the second
  provisioning module is a separable, independently-sized follow-up, best
  done against a real Azure or GCP account when one is actually available
  to prototype and verify against, the same way ADR-0007 was.
