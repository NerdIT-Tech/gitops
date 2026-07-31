# ADR-0007: `kvm_arguments`/`args` is root@pam-only - deliver Ignition via a customized install ISO instead

**Status:** Accepted **Date:** 2026-07-31

**Relates to [ADR-0006](0006-scoped-api-token-plus-ssh-key.md)**: this ADR
replaces ADR-0006's API-token half. ADR-0006's SSH-key change is now moot in
a different way than expected - the redesign below needs no SSH connection
to Proxmox at all, not even a keyed one.

## Context

First real `terraform apply` of the `gha-runner` service, authenticating to
the API as a scoped token per ADR-0006, failed creating the VM resource:

```
Error: VM create
All attempts fail:
#1: error creating VM: received an HTTP 500 response - Reason: only root can
set 'args' config
```

Confirmed against the Proxmox support forum, a Proxmox staff response, and
the actual `qemu-server` source (`PVE/API2/Qemu.pm`,
`check_vm_modify_config_perm`): the VM config's `args` field - which is
exactly what this module's `kvm_arguments` output sets, via
`-fw_cfg name=opt/com.coreos/config,file=...`, to point the VM at its
uploaded Ignition snippet - is gated by a literal string check,
`return 1 if $authuser eq 'root@pam'`, before falling through to
`die "only root can set '$opt' config\n"` for `args`/`lock`. Every other VM
config option (`cdrom`, `boot`, `disk`, `network`, `memory`, `cpu`,
`smbios1`, ...) goes through normal grantable privileges
(`VM.Config.CDROM`, `VM.Config.Disk`, etc.) - `args`/`lock` are the only two
gated this way.

**Why no token can ever satisfy this, including root's own token**: Proxmox
API tokens authenticate as `USER@REALM!TOKENID` (`pveum` documented format).
A token request's `$authuser` is therefore always `root@pam!sometoken`,
never the bare string `root@pam` - so the check can never pass for token
auth, no matter whose token or how privileged. Only an actual
password-authenticated ticket session produces literal `root@pam`. This is
a known, still-open upstream gap (Proxmox
[bug #2582](https://bugzilla.proxmox.com/show_bug.cgi?id=2582), patches
proposed in 2022, unmerged - the original author left Proxmox and nobody
has picked the work back up as of the most recent activity found).

This is a **different** constraint from the one ADR-0006 addressed. SSH as
a non-root user (`gh-deploy`, with scoped `sudo` rules) was verified
working in this same apply run - the Ignition snippet file itself uploaded
fine over SSH. The `args` restriction is specific to the VM resource's API
call, and is orthogonal to how the SSH connection is authenticated.

## Decision

Replace `kvm_arguments`/`args`-based Ignition delivery with a **customized
FCOS live ISO that performs an unattended install**, using
`coreos-installer iso customize --dest-device --dest-ignition`. This avoids
`args` entirely - `cdrom`/`boot`/disk fields are all grantable to a scoped
token - and, as a consequence nobody was specifically hunting for, also
eliminates the need for the `ssh{}` block in the provider altogether: ISO
file uploads use the plain HTTP API regardless of content type
(`bpg/proxmox` docs: "Has no effect for `iso`, `vztmpl`, and `import`
content types, which always use the HTTP API"), unlike `snippets`.

**Prototyped end-to-end against the real Proxmox host, isolated from every
managed service** (separate scratch Terraform root, local state, throwaway
`vm_id`, no `environments/homelab/*` state touched):

1. Downloaded the FCOS `live-iso` artifact for the same stream/release this
   module already tracks.
2. `coreos-installer iso customize --dest-device /dev/vda --dest-ignition
   <rendered .ign> -o custom.iso live.iso` - `/dev/vda` because the disk is
   attached as `virtio0` (`interface = "virtio0"` in this module), which
   Linux enumerates as `/dev/vda`, not `/dev/sda`. (First attempt used
   `/dev/sda` by mistake, matching the docs' generic example verbatim
   without adjusting for this module's actual disk interface - the VM came
   up and sat idle with `wr_bytes=0` on the disk indefinitely, since the
   installer had no matching device to write to. Corrected and re-verified.)
3. Uploaded the custom ISO via `proxmox_virtual_environment_file`
   (`content_type = "iso"`) - succeeded over the API token alone.
4. Created a VM with a blank disk (no `file_id`), a `cdrom` block pointing
   at the uploaded ISO, and `boot_order = ["virtio0", "ide2"]` (disk first
   - blank/unbootable on the very first boot, so SeaBIOS falls through to
   the CD-ROM automatically; once installed, the disk takes over without
   touching boot order again). No `kvm_arguments` at all. No `ssh{}` block
   in the provider at all. Creation succeeded over the API token alone.
5. Verified the install actually ran and completed, not just that Terraform
   returned success: `info blockstats` via `qm monitor` showed ~3.2GB
   written to the disk, then flat/idle - consistent with a full FCOS
   install that finished, not one that hung. The VM's MAC then appeared in
   the host's ARP table as `REACHABLE` with a DHCP-assigned IP, and a raw
   TCP connection to port 22 returned a real `SSH-2.0-OpenSSH_10.2` banner
   - a live, freshly-installed, network-reachable system.
6. Destroyed the throwaway ISO and VM afterward; nothing here touched
   `gha-runner`'s or `omada`'s real state.

## Alternatives considered

- **Revert the API surface to `root@pam` password auth**, keeping
  ADR-0006's SSH-key change. Smaller diff, but reintroduces a single
  high-privilege shared-password credential for the API surface - strictly
  worse than the chosen option once the chosen option was confirmed to
  work, so not worth the tradeoff now that it's verified rather than
  hypothetical.
- **`smbios1` or FCOS's cloud-init-based provisioning**, as a lighter-weight
  alternative to a full custom-ISO install. Not pursued - the ISO approach
  was already verified working end-to-end by the time these were
  considered in depth, and cloud-init would be a materially different
  provisioning path than what ADR-0002/ADR-0003 already document (Ignition
  first-boot-only semantics).
- **Wait on Proxmox's upstream superuser-privilege fix** (bug #2582). Not
  viable - unmerged since 2022, no ETA, no indication anyone is actively
  working it.

## Consequences

- **New build-time dependency**: `coreos-installer` must be available
  wherever `terraform apply` runs for these services - your local machine,
  and eventually the `gha-runner` CI environment itself (a chicken-and-egg
  note similar to the one already in
  [ADR-0005](0005-self-hosted-runner-as-managed-service.md) for the runner
  bootstrap itself). Built from source via `cargo install coreos-installer`
  in this prototype, since no prebuilt static binary is published upstream
  and running it via its container image failed in a sandboxed/nested
  container environment (rootless `podman` couldn't set up user namespaces
  here) - worth confirming which install path is viable whenever this is
  folded into the real module/CI.
- **Image resolution changes**: `modules/fcos-quadlet-vm/main.tf` currently
  resolves and downloads the `qemu`/`qcow2.xz` artifact
  (`local.fcos_metadata.architectures.x86_64.artifacts.qemu...`). This
  needs to resolve the `metal`/`iso` artifact instead
  (`artifacts.metal.formats.iso.disk`), then run `coreos-installer iso
  customize` as a build step before the resulting file is uploaded -
  currently no such build step exists in this repo (likely a
  `local-exec`/`null_resource`, or a small wrapper script Terraform shells
  out to).
- **VM resource changes**: `kvm_arguments` is dropped entirely. `disk`
  loses its `file_id` (now blank, sized for the eventual install rather
  than cloned from a pre-built image) and a `cdrom` block plus
  `boot_order` are added. `depends_on = [proxmox_virtual_environment_file
  .ignition]` becomes `depends_on` the ISO upload resource instead; the
  `ignition` snippet resource goes away.
- **`environments/homelab/*/providers.tf` loses the `ssh {}` block and
  `proxmox_ssh_username`/`proxmox_ssh_private_key` variables entirely** -
  not just switches key type, as ADR-0006 assumed. No SSH connection to the
  Proxmox host is needed anywhere in the redesigned flow.
- **ADR-0002's rebuild runbook needs a wording update**: "re-upload the
  Ignition snippet" is replaced by "rebuild and re-upload the custom ISO,
  then reinstall" as the mechanism - the underlying drift-is-visible-not-
  automatic principle ADR-0002 documents is unaffected.
- **`docs/adr/0006-scoped-api-token-plus-ssh-key.md` is superseded** by this
  ADR for the API-token half; needs a pointer note added the way ADR-0001
  got one from ADR-0006, rather than being deleted.
- This ADR documents the design and its verification; **the actual
  `modules/fcos-quadlet-vm` and `environments/homelab/*` changes are not
  yet implemented** - this was deliberately prototyped in isolation first,
  without touching any managed service or state.
