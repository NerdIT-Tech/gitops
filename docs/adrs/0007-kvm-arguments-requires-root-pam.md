---
id: R-PROX-007
applies_to: ["modules/fcos-quadlet-vm/**", "environments/homelab/**"]
status: accepted
---

# `kvm_arguments`/`args` is root@pam-only — deliver Ignition via a customized install ISO instead

MUST: deliver Ignition by building a customized FCOS live ISO with `coreos-installer iso customize --dest-device --dest-ignition` and booting the VM from it.
MUST NOT: set `kvm_arguments`/`args` on the VM resource.
MUST NOT: configure an `ssh {}` block in the Proxmox provider.
MUST: authenticate the API as a scoped token (`provider.proxmox.api_token`), never `root@pam` password.
SHOULD: upload the custom ISO with `content_type = "iso"` (goes over the plain HTTP API even for token auth), size the disk blank, and use `boot_order = ["virtio0", "ide2"]` so first boot falls through to the installer.
SHOULD: require `coreos-installer` on any host that runs `terraform apply` for these services.

## Why

The VM config's `args` field is gated in Proxmox source (`check_vm_modify_config_perm`) to literal `root@pam` ticket sessions; token auth always arrives as `root@pam!tokenid`, so no token — even root's — can set it (upstream bug #2582, unmerged since 2022). The ISO path avoids `args` entirely and also removes the SSH upload path (snippets uploads were what forced SSH; ISO uploads never need it). Verified end-to-end on a live host with a throwaway VM before landing. Supersedes [R-PROX-006](0006-scoped-api-token-plus-ssh-key.md); complements [R-FCOS-002](0002-ignition-fingerprint-not-replace-triggered.md) (rebuild runbook now means "rebuild and re-upload the custom ISO").

## Verify

```bash
grep -rn --include='*.tf' --exclude-dir=.terraform 'kvm_arguments\|proxmox_password\|ssh_private_key' modules/fcos-quadlet-vm/ environments/ | grep -v ': *#' && echo FAIL || echo OK
```
