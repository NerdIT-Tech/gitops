# omada

Renders the Butane/Ignition snippet for a TP-Link Omada SDN Controller
running as a Podman Quadlet unit: the `[Container]` unit itself
(`docker.io/mbentley/omada-controller`), a `firewalld` service definition
covering its management/portal/discovery ports, a oneshot systemd unit that
registers that firewalld service before the container starts, and the
PUID/PGID-scoped `/var/lib/omada/{data,logs}` storage directories.

## What this module is (and isn't)

This module has **no resources, no data sources, and no provider
requirements** - it takes service-shaped inputs (image tag, PUID/PGID,
timezone, ports) and produces one output, `butane_snippet`: a fully
rendered Butane YAML string. It does not know or care what boots that
config. That's the point - see
[ADR-0008](../../docs/adr/0008-decouple-omada-service-from-vm-provisioning.md)
for the full reasoning behind drawing the boundary here.

To actually run Omada, compose this module's `butane_snippet` output into a
VM-provisioning module's `extra_butane_snippets` list - today that's
[`modules/fcos-quadlet-vm`](../fcos-quadlet-vm), which boots it on Proxmox.
See `environments/homelab/omada/omada.tf` for the composition, and that
environment's README for the operational (stateful-data,
rebuild-runbook) side of running it.

## Why this used to be `services/omada/butane/*.bu.tftpl`, and isn't anymore

Before ADR-0008, this template was a bare Butane file rendered directly via
`templatefile()` inside `environments/homelab/omada/omada.tf` - no module
boundary, no reuse, no independent `terraform validate`. `services/gha-runner`
still follows that lighter-weight shape, and that's fine: not every service
needs to graduate to a full module. Omada was promoted here specifically
because the goal was portability (running the same service definition
against a VM-provisioning module other than `fcos-quadlet-vm`, e.g. an
eventual Azure or GCP one) and that requires the service definition to be a
self-contained unit with its own interface, not a template path reached
into from an environment root.

## Ports

`manage_http_port` / `manage_https_port` / `portal_http_port` /
`portal_https_port` are parameterized because the container image itself
exposes them via env vars (`MANAGE_HTTP_PORT` etc.) - a real, supported
reconfiguration point, useful if something else on the host already owns
one of the defaults. The EAP discovery ports (UDP `29810`-`29813`, TCP
`29814`) are **not** parameterized - they're fixed by the discovery
protocol itself, not exposed as env vars by the image, and are hardcoded in
`butane/omada.bu.tftpl`.

The rendered firewalld service XML de-duplicates the four configurable TCP
ports via `distinct()` (see `main.tf`) rather than `toset()`/`sort()` -
`manage_http_port` and `portal_http_port` both default to `8088`, and a set
would both risk reordering the list across plans (no stable iteration
order) and needlessly flap `ignition_fingerprint` upstream.

## Stateful data

Omada's controller state (device inventory, adopted APs, settings) lives on
`/var/lib/omada/data`, on the VM's own disk - this module has no opinion on
backup/snapshotting, that's the provisioning module's and environment's
job. Combined with [ADR-0002](../../docs/adr/0002-ignition-fingerprint-not-replace-triggered.md)
(Ignition is first-boot-only, drift is surfaced not auto-applied), any
change to this module's rendered output on an **already-provisioned** VM
needs the manual rebuild+restore runbook documented in
`fcos-quadlet-vm`'s README, not a routine `terraform apply`.
