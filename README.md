# gitops

Terraform GitOps for a Proxmox homelab: FCOS VMs running Podman Quadlet units, deployed via CI.

## Layout

| Path | What lives there |
|---|---|
| `modules/` | Reusable modules. `fcos-quadlet-vm` owns VM/ISO; `omada`, `porkbun-acme-tls`, `nginx-reverse-proxy` render Butane snippets (R-TF-008). |
| `environments/homelab/<service>/` | One Terraform root + one state key per service (R-TF-004). Each has `README.md` and `vars.tfvars.example`. |
| `services/<service>/butane/` | Service-level Butane templates composed by the env root (R-TF-011). |
| `docs/adrs/` | Architecture decision records — read before changing patterns they cover. |
| `.github/workflows/` | PR checks (fmt/tflint/Trivy/validate/plan) and apply pipeline. |

## Golden paths

**Add a new service**
1. `cp -r environments/homelab/omada environments/homelab/<service>` and edit.
2. Give it its own backend key in `backend.tf`.
3. Compose snippets: `extra_butane_snippets = [module.<service>.butane_snippet, ...]`.
4. `cp vars.tfvars.example vars.tfvars`, fill in, `terraform init && terraform plan`.

**Change a module**
1. Edit `modules/<name>/`.
2. `terraform fmt -recursive && tflint --recursive`.
3. PR — CI runs validate on the module and plan on affected services.

**Render-only modules** (snippet modules) emit `butane_snippet` and own no Proxmox resources — keep them provider-less so they can compose anywhere (R-TF-008).

## Rules of the road

- One Terraform root and one state file per service. Never share state across services.
- No credentials through Terraform state for third-party secrets (R-DNS-010) — inject out-of-band via SSH seed.
- Auth to Proxmox is scoped API token, never root PAM password (R-PROX-006, R-PROX-007).
- FCOS stream floats; pinning requires an ADR (R-FCOS-003).

## Operations

See `docs/operations.md` for health checks, backup, and restore expectations.
