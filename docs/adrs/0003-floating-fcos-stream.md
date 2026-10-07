---
id: R-FCOS-003
applies_to: ["modules/fcos-quadlet-vm/**", "environments/homelab/**"]
status: accepted
---

# Track the latest FCOS release in a stream, don't pin a specific version

MUST: resolve the FCOS image from the live stream metadata endpoint (`data.http.fcos_stream`) per `var.fcos_stream` channel.
MUST NOT: pin a specific FCOS release/version.
SHOULD: treat `download_file` wanting to replace on new-release as expected noise; protect the running VM via `lifecycle.ignore_changes` on `disk[0].file_id`.

## Why

`zincati` (enabled in `base.bu.tftpl`) keeps the running system current regardless of the booted image, so pinning would only fix the starting point, not the running state. The stream channel (`stable`/`testing`/`next`) selects the moving target; pinning buys reproducibility only at VM-rebuild time and costs manual bumps.

## Verify

```bash
grep -rn --include='*.tf' --exclude-dir=.terraform -E 'fcos[_-]?version[[:space:]]*=[[:space:]]*"' modules/ environments/ | grep -v ': *#' && echo FAIL || echo OK
```
