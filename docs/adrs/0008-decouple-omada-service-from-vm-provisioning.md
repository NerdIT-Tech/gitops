---
id: R-TF-008
applies_to: ["modules/omada/**", "modules/fcos-quadlet-vm/**", "modules/nginx-reverse-proxy/**", "environments/homelab/**"]
status: accepted
---

# Decouple the service definition (`modules/omada`) from VM provisioning (`modules/fcos-quadlet-vm`)

MUST: keep service-definition modules (`modules/omada`, `modules/nginx-reverse-proxy`) free of any `proxmox_*` resources, data sources, and Proxmox-shaped inputs.
MUST: have such a module expose pure rendering outputs only — inputs like image tag/ports/puid/pgid/timezone, output `butane_snippet`, no resources, no `required_providers`, no `variables` referencing Proxmox.
SHOULD: compose the environment root as `module.<svc>_service` (definition module) feeding `extra_butane_snippets` of `module.<svc>` (`fcos-quadlet-vm`).
SHOULD: keep Proxmox specifics (`vm_id`, `network_bridge`, sizing) in the environment root's VM-module call, not the service module.

## Why

The portability contract: the rendered Butane/Ignition content would be identical on Azure/GCP/libvirt, so it shouldn't be welded to the Proxmox provisioner. "Does it need to change when the next thing comes along?" is the test. A service definition that references `proxmox_*` fails it; a pure `templatefile()` module passes. `services/omada/` was removed; the template moved inside `modules/omada/butane/`.

## Verify

```bash
grep -rn --include='*.tf' --exclude-dir=.terraform 'proxmox_' modules/omada/ modules/nginx-reverse-proxy/ | grep -v ': *#' && echo FAIL || echo OK
```
