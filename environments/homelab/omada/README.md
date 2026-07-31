# Omada environment root

Provisions the homelab's TP-Link Omada SDN Controller as `omada01`
(`vm_id = 9010`) on Proxmox. Own Terraform root and state key
(`gitops/omada/terraform.tfstate`) per [ADR-0004](../../../docs/adr/0004-per-service-terraform-root-and-state.md).

## Composition

`omada.tf` wires together two module calls (see
[ADR-0008](../../../docs/adr/0008-decouple-omada-service-from-vm-provisioning.md)
for why it's split this way):

- `module.omada_service` ([`modules/omada`](../../../modules/omada)) - *what*
  Omada is: the Quadlet unit, firewalld service, storage layout. No
  provider, no resources - just renders Butane YAML and outputs it as
  `butane_snippet`.
- `module.omada` ([`modules/fcos-quadlet-vm`](../../../modules/fcos-quadlet-vm)) -
  *where* it runs: the Proxmox VM (sizing, network, tags, ISO build/upload).
  Takes `module.omada_service.butane_snippet` as one element of
  `extra_butane_snippets`.

If Omada ever needs to run somewhere other than Proxmox, only the second
module call changes - `module.omada_service` and its inputs are unaffected.

## This is a live, stateful production VM

`omada01` holds real controller state on its own disk
(`/var/lib/omada/data`) - device inventory, adopted APs, settings. There is
no snapshot/backup automation here.

Ignition only applies on **first boot** (ADR-0002/ADR-0003). A Butane change
here - whether it's `modules/omada`'s inputs above, or `modules/fcos-quadlet-vm`
itself - does **not** get re-applied to the already-running VM. Watch
`terraform plan`'s `omada_ignition_fingerprint` output: a diff there means
this environment's config has drifted from what the running VM actually has,
and applying it silently does nothing to the VM itself (it only rebuilds and
re-uploads the install ISO for next time). To actually apply it, follow the
manual rebuild+restore runbook in
[`fcos-quadlet-vm`'s README](../../../modules/fcos-quadlet-vm/README.md#ignition-only-runs-once-and-what-that-means-for-edits) -
back up `/var/lib/omada/data` first.

## Applying

Same credential/tooling requirements as every other service root in this
repo - see [`gha-runner`'s README](../gha-runner/README.md) for the full
list (Proxmox API token, SSH public key, MinIO/S3 credentials,
`coreos-installer` installed locally for the ISO build step). This root has
no service-specific variables beyond the shared ones in `variables.tf`.
