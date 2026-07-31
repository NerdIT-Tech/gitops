# fcos-quadlet-vm

Provisions a single Fedora CoreOS VM on Proxmox, bootstrapped via Ignition
(rendered from Butane), intended to run one Podman Quadlet-managed service.

## What it does

1. Resolves the latest FCOS **live ISO** for `var.fcos_stream` (default
   `stable`) from the
   [CoreOS stream metadata endpoint](https://builds.coreos.fedoraproject.org).
2. Renders `butane/base.bu.tftpl` (hostname, SSH key, timezone, firewalld,
   zincati auto-update policy, optional qemu-guest-agent installer) and
   merges in whatever the caller passes as `var.extra_butane_snippets` —
   this is how a service under `services/` layers its own Quadlet unit,
   firewall rules, and volumes on top of the common bootstrap. The merge
   uses Ignition's native config-merge via `poseidon/ct`'s `snippets` arg;
   each snippet is transpiled independently, then merged.
3. Downloads the pristine live ISO locally (cached by checksum under
   `~/.cache/fcos-quadlet-vm`) and runs `coreos-installer iso customize
   --dest-device /dev/vda --dest-ignition <rendered config>` to embed the
   merged Ignition config into a per-service custom ISO, via a
   `local-exec` provisioner (`scripts/build-custom-iso.sh`).
4. Uploads that custom ISO to Proxmox and boots the VM from it with a
   blank data disk attached. The ISO's embedded config makes
   `coreos-installer` install itself onto the disk and reboot,
   unattended, on first boot - no console interaction. Boot order puts the
   disk first: it's blank/unbootable on the very first boot so the CD-ROM
   is used automatically, and once installed the disk takes over without
   needing the boot order touched again.

## Why this needs `coreos-installer` locally, and why there's no SSH involved

Earlier versions of this module set the VM's `kvm_arguments` (`-fw_cfg
name=opt/com.coreos/config,file=...`) to point at an Ignition config
uploaded as a Proxmox snippet. That turned out to have two costs a scoped
API token couldn't avoid: the snippet upload itself needs SSH regardless of
API auth method, and - the harder blocker - Proxmox hardcodes the VM's
`args` field (what `kvm_arguments` sets) to root@pam **password** auth,
with no grantable privilege a token can hold, even root's own token. See
[ADR-0007](../../docs/adr/0007-kvm-arguments-requires-root-pam.md) for the
full finding, verified against Proxmox's own source and a live prototype.

The install-ISO approach in this module needs no SSH connection to Proxmox
at all - ISO uploads always go over the plain HTTP API regardless of
content type - and every VM operation it performs (`cdrom`, `boot`, disk,
network, ...) is grantable to a scoped token, unlike `args`. The tradeoff:
`coreos-installer` must be installed wherever `terraform apply` runs for
these services (`cargo install coreos-installer --locked` - no prebuilt
static binary is published upstream). This only matters for `apply`, not
`plan`/`validate` - the build step is a provisioner, which Terraform never
executes during a plan. See
[ADR-0006](../../docs/adr/0006-scoped-api-token-plus-ssh-key.md) and
[ADR-0001](../../docs/adr/0001-root-pam-password-proxmox-auth.md) for the
earlier setups this superseded.

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
2. `terraform apply` first if you haven't - this rebuilds and uploads the
   custom install ISO for the new fingerprint (via `custom_iso_build`), but
   does not by itself touch the running VM.
3. `terraform destroy -target <the module instance>` (or taint +
   apply) to tear down and recreate the VM, which reinstalls from the
   now-current custom ISO.
4. Restore the stateful data onto the fresh VM.
5. Confirm the service comes back healthy before removing the backup.

There is currently no automation for this — it's a deliberate manual gate
given the blast radius of getting it wrong on a homelab's only copy of the
data.

## FCOS stream tracking

`var.fcos_stream` defaults to `stable` and the module always resolves the
**latest** release in that stream at `terraform plan` time — it is not
pinned to a specific FCOS version, since `zincati` keeps the running VM
current on its own regardless. Expect `terraform plan` noise on
`custom_iso_build` (and a real ISO rebuild on `apply`) whenever Fedora
publishes a new release; this is not a bug. See
[ADR-0003](../../docs/adr/0003-floating-fcos-stream.md) for the full
rationale.

## Variables of note

- `timezone` (default `Etc/UTC`) sets the VM host's `/etc/localtime` via a
  Butane-managed symlink. This is independent from any `TZ=` environment
  variable a service sets for its own container — set both if a service
  needs its container's timezone to match the host's.
- `extra_tags` are appended to the Proxmox VM's tag list alongside the
  fixed `terraform`/`fcos` tags this module always applies.
