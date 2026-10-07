---
id: R-TF-005
applies_to: ["environments/homelab/gha-runner/**", "services/gha-runner/**", ".github/workflows/**"]
status: accepted
---

# Run the CI self-hosted runner as a service managed by this same repo

MUST: provision the `self-hosted, homelab` runner as a service in this repo (`environments/homelab/gha-runner/`, own root + state per R-TF-004) via `fcos-quadlet-vm` + the `myoung34/github-runner` Quadlet unit.
MUST NOT: register the runner with a PAT (`ACCESS_TOKEN`) or a manual UI token.
MUST: authenticate registration via a GitHub App (`APP_ID` + `APP_PRIVATE_KEY`) with Administration: Read and write on the repo.
MUST: deliver `APP_PRIVATE_KEY` through a podman secret (`gha-runner-secret.service` seeds it before the container starts), not a plain `Environment=` line, and render it into Butane with a YAML block scalar (`indent()`), since the PEM is multi-line.
MUST: set `DISABLE_AUTO_UPDATE=true` on the runner container; use podman `AutoUpdate=registry` + `podman-auto-update.timer` for updates, matching R-FCOS-003's float-and-auto-update shape.
MUST: run the very first `terraform apply` for this service locally by hand (chicken-and-egg: CI needs the runner to already exist).

## Why

The CI `plan` job runs on `runs-on: [self-hosted, homelab]` because Proxmox and the MinIO state backend are only reachable on the private LAN, so something in the homelab must provide that runner — and it should be IaC like everything else. Manual registration tokens expire in ~1h; a PAT-backed token would work but reintroduces a long-lived user-bound credential the GitHub App avoids. Ephemeral one-job runners were rejected: single always-on runner, low-volume CI.

## Verify

```bash
grep -rn --include='*.tftpl' --exclude-dir=.terraform 'ACCESS_TOKEN\|Environment=APP_PRIVATE_KEY' services/gha-runner/ | grep -v ': *#' && echo FAIL || echo OK
```
