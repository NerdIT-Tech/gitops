---
id: R-FCOS-002
applies_to: ["modules/fcos-quadlet-vm/**", "environments/homelab/**"]
status: accepted
---

# Track Ignition drift via a visible fingerprint, not `replace_triggered_by`

MUST: keep `terraform_data.ignition_fingerprint` hashing the rendered Butane content and exposing it as an output.
MUST NOT: wire the fingerprint into `replace_triggered_by` on the VM resource.
SHOULD: treat a diff on that output in `terraform plan` as the drift signal for an existing VM.

## Why

Ignition applies once, on first boot. A Butane edit re-renders the config and uploads a new ISO, but the running VM never sees it — drift would be silent. Auto-recreating the VM on config change would destroy the stateful data disk (e.g. Omada's controller database).

## Verify

```bash
grep -rn --include='*.tf' --exclude-dir=.terraform 'replace_triggered_by' modules/fcos-quadlet-vm/ | grep -v ': *#' && echo FAIL || echo OK
```
