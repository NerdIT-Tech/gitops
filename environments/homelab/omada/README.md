# Omada environment root (decommissioned)

`omada01` (`vm_id = 9010`) is no longer managed by Terraform. The VM was
left running on Proxmox; this root now holds only the `removed` block that
drops it from state (`gitops/omada/terraform.tfstate`), because a `removed`
block can only act when it is applied against existing configuration.

## What changed

- `omada.tf` declares no modules. Its `removed` block forgets `module.omada`
  ([`modules/fcos-quadlet-vm`](../../../modules/fcos-quadlet-vm) - the VM,
  its install ISO, the rendered Ignition file, and the `terraform_data`
  bookkeeping) with `destroy = false`, so nothing is destroyed on Proxmox.
- The Omada service-definition wiring was removed: `module.omada_tls`
  ([`modules/porkbun-acme-tls`](../../../modules/porkbun-acme-tls)),
  `module.omada_service` ([`modules/omada`](../../../modules/omada)), and
  `module.omada_nginx`
  ([`modules/nginx-reverse-proxy`](../../../modules/nginx-reverse-proxy)).
  Those modules manage no resources and held no state.
- Provider configuration and variables were removed; this root no longer
  talks to Proxmox or Let's Encrypt. Both workflows no longer build the
  install ISO or seed Porkbun credentials on `omada01`.

Applying this root once (via `terraform-apply.yml` on merge to `main`)
drops the VM from state. After that apply, this root and its `omada` entries
in `terraform-pr.yml`/`terraform-apply.yml` can be deleted.

## The VM is still running

Terraform no longer manages `omada01`, but the VM and its controller data
(`/var/lib/omada/data`) are untouched. To manage it again, re-add the
`module.omada` block and `terraform import` its resources. See
[ADR-0004](../../../docs/adrs/0004-per-service-terraform-root-and-state.md)
for why this root/state key is separate from every other service.
