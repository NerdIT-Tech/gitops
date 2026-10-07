---
id: R-DNS-010
applies_to: ["modules/porkbun-acme-tls/**", "environments/homelab/**", ".github/workflows/**"]
status: accepted
---

# Porkbun credentials are never a Terraform input — CI seeds them directly over SSH

MUST NOT: accept Porkbun API key/secret as a Terraform variable, in any form, in any module.
MUST NOT: interpolate the credentials into rendered Butane/Ignition content.
MUST: have `modules/porkbun-acme-tls` create only the empty `0700` credentials directory via Ignition, take `credentials_file` as a path variable, and expose that path as an output.
MUST: seed the credentials file out-of-band from Terraform — a step in `terraform-apply.yml` that reads `PORKBUN_API_KEY`/`PORKBUN_API_SECRET` from GitHub Actions secrets and SSHes the file to the VM after `terraform apply`.
MUST: after seeding, run `systemctl reset-failed` + `systemctl start` on the ACME oneshot and dependent service units (the first-boot `Restart=always` retry loop hits the start-limit before credentials exist).
SHOULD: keep `TF_VAR_*` for non-secret config only (`TF_VAR_acme_email`); never name a secret `TF_VAR_*`.

## Why

Same-day incident, 2026-08-01. ADR-0009 shipped the secret as a `sensitive` Terraform variable; it rendered into Butane and passed through the `poseidon/ct` provider, which shells out to Butane — a provider RPC boundary that drops Terraform's sensitivity marks (the value came back as a new `source:` attribute at a new path, and `ct` schema doesn't mark its output). The real secret landed in a GitHub PR comment via plan output; it was rotated and the run deleted. Structural fix: the module cannot leak a value it never receives. GitHub Actions' own secret redaction protects the value through the CI shell step; Terraform never sees it. Supersedes the credential portion of [R-DNS-009](0009-porkbun-dns01-acme-module.md).

## Verify

```bash
grep -rn --include='*.tf' --include='*.tftpl' --include='*.yml' --exclude-dir=.terraform -E 'porkbun_api_(key|secret)|TF_VAR_porkbun' modules/ environments/ .github/workflows/ | grep -v ': *#' && echo FAIL || echo OK
```
