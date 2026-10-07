---
id: R-PROX-001
applies_to: ["environments/homelab/**/providers.tf"]
status: superseded-by: R-PROX-006
---

# Authenticate to Proxmox as root@pam with a password

MUST: authenticate both the API provider block and the `ssh` block as `root@pam` with a password (`var.proxmox_password`, `sensitive`).
MUST NOT: use a scoped API token for the API surface — no role then covered the snippet-upload path.

## Why

The `bpg/proxmox` provider needs two access paths: the REST API, and SSH for `content_type = "snippets"` upload. Superseded 2026-07-31: SSH is unavoidable regardless of API auth, but a token does work for the API surface — see [R-PROX-006](0006-scoped-api-token-plus-ssh-key.md), then [R-PROX-007](0007-kvm-arguments-requires-root-pam.md) which removed the SSH path entirely. Kept as the historical record of what was tried first.

## Verify

```bash
grep -rn --include='*.tf' --exclude-dir=.terraform 'proxmox_password' environments/ modules/ | grep -v ': *#' && echo FAIL || echo OK
```
