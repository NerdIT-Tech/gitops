---
id: R-PROX-006
applies_to: ["environments/homelab/**/providers.tf"]
status: superseded-by: R-PROX-007
---

# Scoped Proxmox API token for the API, SSH key (not password) for the SSH fallback

MUST: authenticate the API with `provider.proxmox.api_token` from a dedicated service account (not `root@pam`).
MUST: authenticate the `ssh` block with a dedicated `provider.proxmox.ssh.private_key`, never a password.
MUST: set the SSH username explicitly when using token auth (`proxmox_ssh_username`); the two credentials stay independent.
SHOULD: give the SSH user passwordless `sudo` scoped only to the exact provider shell-outs (`pvesm`, `qm`, `tee` on the snippets path pattern).

## Why

ADR-0001's shared root password for both surfaces was the wrong default; a scoped token + dedicated key splits the blast radius. Superseded for the API-token half on 2026-07-31: setting `kvm_arguments`/`args` is hardcoded to `root@pam` password auth in Proxmox itself regardless of token scope (see [R-PROX-007](0007-kvm-arguments-requires-root-pam.md)), and the SSH path is gone entirely. The API-token reasoning here was reasonable given what was verified then. The "inline Ignition via `-fw_cfg`" alternative was rejected: several-KB configs exceed any verified `-fw_cfg` length limit.

## Verify

Superseded; live invariant is R-PROX-007's check.
