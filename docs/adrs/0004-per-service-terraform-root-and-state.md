---
id: R-TF-004
applies_to: ["environments/homelab/**", "**/*.tfvars"]
status: accepted
---

# One Terraform root and state file per service, not one shared environment root

MUST: give each service its own Terraform root with its own backend key at `environments/homelab/<service>/` (`backend.tf`, `providers.tf`, `variables.tf`, `<service>.tf`).
MUST NOT: keep shared root-level `.tf` files or one shared state at `environments/homelab/` itself.
MUST: scope CI fmt/validate/plan to the changed service root (matrix entry in `terraform-pr.yml`); each new service adds one matrix line.
SHOULD: keep service names matching between `environments/homelab/<name>/` and `services/<name>/` so the local hook routes generically.

## Why

A bad `apply` in a shared state jeopardizes every service in it. Splitting repos was rejected: module `source` would become a versioned cross-repo dependency and CI/secrets would be duplicated, while the blast-radius fix is isolating state anyway. `-target` applies were rejected as a manual, error-prone substitute for a structural boundary.

## Verify

```bash
ls environments/homelab/*.tf 2>/dev/null && echo FAIL || echo OK
```
