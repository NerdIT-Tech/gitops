---
id: R-DNS-009
applies_to: ["modules/porkbun-acme-tls/**"]
status: superseded-by: R-DNS-010
---

# Porkbun DNS-01 ACME as a reusable module, decoupled from Omada

MUST: issue and renew certs on-VM with certbot + `certbot-dns-porkbun` via DNS-01 (zero inbound ports needed; the VMs sit behind RFC1918 with no public path, so HTTP-01 is out).
MUST: trigger service restarts with a `systemd.path` unit in the consuming service's module, not a Podman socket or host access inside the certbot container (a third-party image gets no root-equivalent host control).
MUST: block the service's first start on initial ACME success via `After=`/`Requires=` on the service unit — fail closed rather than serve a default cert window.
SHOULD: keep the renewal loop (0600 credentials file, oneshot certbot service, twice-daily timer, deploy-hook copying PEMs) in `modules/porkbun-acme-tls`, with no resources/`required_providers` — same pure-render shape as R-TF-008.
SHOULD: use one certificate with multiple SANs for one physical host answering to several names.

## Why

Service groups need valid TLS on `*.canady.cloud`; the renewal capability should be composable across services, so it lives in its own module, not folded into `modules/omada`. DNS-01 needs no public inbound path and leaves firewalld unchanged. The `.path`-unit restart pattern keeps least privilege: certbot's deploy-hook only copies files; it must not get a Podman socket. NOTE: the credential-input design in the first version of this record (`porkbun_api_key`/`porkbun_api_secret` as module inputs, accepted in Terraform state/ISO) is superseded — see [R-DNS-010](0010-porkbun-credential-out-of-band.md).

## Verify

```bash
grep -rn 'certbot' modules/porkbun-acme-tls/ >/dev/null || echo FAIL
```
