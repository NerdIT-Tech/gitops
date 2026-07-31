# fcos-quadlet-vm

Provisions a single Fedora CoreOS VM on Proxmox, bootstrapped via Ignition
(rendered from Butane), intended to run one Podman Quadlet-managed service.

## What it does

1. Resolves the latest FCOS image for `var.fcos_stream` (default `stable`)
   from the [CoreOS stream metadata endpoint](https://builds.coreos.fedoraproject.org)
   and downloads it into a Proxmox datastore.
2. Renders `butane/base.bu.tftpl` (hostname, SSH key, timezone, firewalld,
   zincati auto-update policy, optional qemu-guest-agent installer) and
   merges in whatever the caller passes as `var.extra_butane_snippets` —
   this is how a service under `services/` layers its own Quadlet unit,
   firewall rules, and volumes on top of the common bootstrap. The merge
   uses Ignition's native config-merge via `poseidon/ct`'s `snippets` arg;
   each snippet is transpiled independently, then merged.
3. Uploads the merged Ignition config as a Proxmox snippet and boots the VM
   with it wired in via `kvm_arguments` (`-fw_cfg ... opt/com.coreos/config`).

## Why SSH is still required despite using an API token

Proxmox's snippet-upload operation (how this module gets the rendered
Ignition config onto the node before `kvm_arguments` points the VM at it)
requires SSH regardless of how the API itself is authenticated - a scoped
API token works fine for everything else this module does. The
environment's `providers.tf` therefore uses a scoped API token for the API
surface and a dedicated SSH key (not a password, and not the same
credential as the token) for the SSH surface. See
[ADR-0006](../../docs/adr/0006-scoped-api-token-plus-ssh-key.md) for the
full rationale, and [ADR-0001](../../docs/adr/0001-root-pam-password-proxmox-auth.md)
for the earlier root@pam+password setup this refined.

## Ignition-only-runs-once, and what that means for edits

Ignition applies **once**, on first boot. If you change `extra_butane_snippets`
or anything in `base.bu.tftpl` for an **already-provisioned** VM, Terraform
will re-render and re-upload the `.ign` snippet, but the running VM will
never see it — Ignition does not re-run on reboot.

The module makes this drift visible instead of silent via the
`ignition_fingerprint` output, deliberately **not** wired into
`replace_triggered_by` (which would auto-destroy the VM's stateful data
disk on every routine edit). See
[ADR-0002](../../docs/adr/0002-ignition-fingerprint-not-replace-triggered.md)
for why.

**Manual rebuild runbook**, when you see an `ignition_fingerprint` diff you
want applied:

1. Back up the service's stateful data (e.g. for Omada:
   `/var/lib/omada/data`) off the VM.
2. `terraform destroy -target <the module instance>` (or taint +
   apply) to tear down and recreate the VM with the new Ignition config.
3. Restore the stateful data onto the fresh VM.
4. Confirm the service comes back healthy before removing the backup.

There is currently no automation for this — it's a deliberate manual gate
given the blast radius of getting it wrong on a homelab's only copy of the
data.

## FCOS stream tracking

`var.fcos_stream` defaults to `stable` and the module always resolves the
**latest** release in that stream at `terraform plan` time — it is not
pinned to a specific FCOS version, since `zincati` keeps the running VM
current on its own regardless. Expect `terraform plan` noise on the
download resource whenever Fedora publishes a new release; this is not a
bug. See [ADR-0003](../../docs/adr/0003-floating-fcos-stream.md) for the
full rationale.

## Variables of note

- `timezone` (default `Etc/UTC`) sets the VM host's `/etc/localtime` via a
  Butane-managed symlink. This is independent from any `TZ=` environment
  variable a service sets for its own container — set both if a service
  needs its container's timezone to match the host's.
- `extra_tags` are appended to the Proxmox VM's tag list alongside the
  fixed `terraform`/`fcos` tags this module always applies.
