# ADR-0006: Scoped Proxmox API token for the API, SSH key (not password) for the SSH fallback

**Status:** Accepted **Date:** 2026-07-31

**Superseded by [ADR-0007](0007-kvm-arguments-requires-root-pam.md)** for
the API-token half: setting `kvm_arguments`/`args` turns out to be
hardcoded to root@pam password auth in Proxmox itself, regardless of token
scope - discovered on the first real `terraform apply` after this ADR was
written. ADR-0007's redesign (ISO-embedded Ignition instead of `-fw_cfg`)
also removes the `ssh{}` block this ADR introduced entirely, not just its
credential type. Left as-is below for the historical record - the
API-token reasoning here was reasonable given what was verified at the
time, just incomplete.

**Refines [ADR-0001](0001-root-pam-password-proxmox-auth.md)**, which this
repo started with (`root@pam` + a single shared password for both the API
and SSH surfaces). That decision's core technical premise was correct but
imprecisely framed - this ADR corrects the framing and changes the actual
credentials in use.

## Context

ADR-0001 stated a scoped API token "cannot be granted the permissions this
module's snippet-upload path needs." Checked against the `bpg/proxmox`
provider's own documentation while implementing this ADR: that's not quite
right. The provider's docs state SSH is "strictly required" for a specific,
narrow set of operations - uploading snippets via
`proxmox_virtual_environment_file` (exactly what this module uses to
deliver the rendered Ignition config) being one of them - and that this
holds **regardless of how the API itself is authenticated**. Every other
operation this module performs (creating/modifying the VM, downloading the
FCOS image, etc.) works fine over the API alone, token or not.

In other words: ADR-0001 correctly identified that SSH can't be avoided,
but incorrectly concluded from that where the constraint actually applies -
it's a property of the snippet-upload operation itself, not a limitation
on what an API token can authenticate. A scoped token works fine for the
API surface; SSH is unavoidable for the one operation it's unavoidable for,
independent of that choice.

## Decision

- **API surface**: `provider.proxmox.api_token`, a scoped Proxmox API
  token (`user@realm!token-id=secret`) tied to a dedicated service account
  (not `root@pam`), instead of username/password.
- **SSH surface**: `provider.proxmox.ssh.private_key`, a dedicated SSH
  keypair, instead of a password. Per the provider's docs, SSH username
  must be set explicitly when using token auth (no password to inherit
  from), which `proxmox_ssh_username` already did.

The API token and the SSH key are two independent credentials now, not one
shared password reused for both surfaces - directly resolving the
Consequence ADR-0001 flagged but didn't act on yet.

## Alternatives considered

- **Eliminate SSH entirely** by switching Ignition delivery from
  snippet-file upload to inlining the config directly via
  `-fw_cfg name=opt/com.coreos/config,string=<content>` in `kvm_arguments`,
  instead of `file=<snippet path>`. Considered and explicitly not chosen:
  Ignition configs here run several KB (base bootstrap + service Quadlet
  units + firewall rules), and there's no verified guarantee that's within
  whatever length limit applies to an inlined QEMU `-fw_cfg` argument
  through Proxmox's API - untested against a live instance, and risky to
  commit to without that verification. Revisit if avoiding SSH entirely
  becomes a hard requirement rather than a preference.
- **Keep the shared root password, just for SSH** - rejected; the whole
  point is decoupling the two credentials, and a dedicated key is a
  smaller-blast-radius credential than root's password by design.

## Consequences

- The Proxmox-side service account backing the API token (e.g. `gh-deploy`
  or similar, not `root`) needs a role granting whatever permissions VM
  lifecycle + image download + datastore operations require. Getting this
  role right is Proxmox-instance-specific and wasn't verified here -
  expect to iterate on the role/permissions the first time `terraform
  apply` actually runs against it.
- The SSH user does **not** need to be `root` either - confirmed against
  the `bpg/proxmox` provider's own docs. It can be a dedicated non-root
  Linux user (e.g. `gh-deploy`), but note this is a **separate identity**
  from the API token's realm user (`gh-deploy@pve` or similar) - a real
  system account on the Proxmox host with its own `authorized_keys`, not
  a Proxmox API/PAM realm concept. It needs passwordless `sudo` scoped to
  exactly the commands the provider shells out to, added via
  `visudo -f /etc/sudoers.d/terraform`:
  ```
  gh-deploy ALL=(root) NOPASSWD: /usr/sbin/pvesm
  gh-deploy ALL=(root) NOPASSWD: /usr/sbin/qm
  gh-deploy ALL=(root) NOPASSWD: /usr/bin/tee /var/lib/vz/snippets/[a-zA-Z0-9_][a-zA-Z0-9_.-]*
  ```
  The `tee` rule must stay scoped to the snippets path pattern shown -
  the docs explicitly warn a wildcard like `/var/lib/vz/*` is a path
  traversal risk. If snippets live on a non-default datastore, that
  path needs its own rule too.
- `proxmox_username`/`proxmox_password` variables are gone from every
  service root (`environments/homelab/*/variables.tf`) - replaced with
  `proxmox_api_token` and `proxmox_ssh_private_key`, both `sensitive`.
  Anyone with an existing `.tfvars`/env-var setup from before this ADR
  needs to update it - see the affected root's variables for exact names.
- CI (`terraform-pr.yml`) needs updated secrets:
  `TF_PROXMOX_API_TOKEN` and `TF_PROXMOX_SSH_PRIVATE_KEY` replace
  `TF_PROXMOX_USERNAME`/`TF_PROXMOX_PASSWORD`.
