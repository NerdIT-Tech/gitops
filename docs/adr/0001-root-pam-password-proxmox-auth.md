# ADR-0001: Authenticate to Proxmox as root@pam with a password, not an API token

**Status:** Accepted **Date:** 2026-07-30 (retroactively documented; predates this ADR log)

## Context

The `bpg/proxmox` provider needs two distinct access paths to stand up an
FCOS VM: the Proxmox REST API (creating the VM, downloading images), and an
SSH connection to the Proxmox host itself, which the provider falls back to
for some datastore/snippet operations the API alone doesn't cover — notably
uploading the rendered Ignition config as a `content_type = "snippets"`
file, which `kvm_arguments` then points the VM at during boot.

Proxmox API tokens can be scoped down with a permission role, which is the
usual best practice for Terraform providers. That's the option we'd prefer.

## Decision

Both the API provider block and the `ssh` block in
`environments/homelab/providers.tf` authenticate as `root@pam` with a
password (`var.proxmox_password`, marked `sensitive`).

## Alternatives considered

- **Scoped API token** — cannot be granted the permissions this module's
  snippet-upload path needs; Proxmox's permission model doesn't expose a
  role that covers it. Ruled out on capability grounds, not preference.
- **SSH key instead of password for the `ssh` block** — the provider
  supports `agent` or `private_key` auth for the SSH connection
  independently of how the API is authenticated. This is a legitimate
  improvement not yet made — see Consequences.

## Consequences

- `proxmox_password` is a single high-privilege credential shared between
  the API and SSH paths — compromise or required rotation affects both at
  once. A follow-up worth making: split the SSH leg onto a dedicated
  key-based credential (`private_key`) so the two access paths don't share
  a secret, and so the SSH leg isn't password-based at all.
- If Proxmox's token permission model changes in a future version to cover
  the snippet-upload path, revisit this — token auth remains preferable
  when it works, for the usual least-privilege reasons.
