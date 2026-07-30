# Bootstrapping the CI self-hosted runner

This provisions the one VM that gives `.github/workflows/terraform-pr.yml`'s
`plan` job (`runs-on: [self-hosted, homelab]`) somewhere to run - see
[ADR-0005](../../../docs/adr/0005-self-hosted-runner-as-managed-service.md)
for why it's built this way. **This is the one thing in this repo that
cannot be applied via CI** - the `plan` job needs this runner to already
exist, so the first apply has to happen locally, by hand, once.

## 1. Create the GitHub PAT

The runner container uses a PAT to mint its own registration token at
startup (so it survives restarts without manual re-registration - see
ADR-0005). Create one scoped as narrowly as GitHub allows for runner
registration:

- **Fine-grained PAT** (preferred): repository access limited to
  `NerdIT-Tech/gitops`, permission **Administration: Read and write**.
- **Classic PAT** (if fine-grained doesn't work for your GitHub plan):
  scope `repo`.

Don't commit this anywhere. You'll pass it as a Terraform variable in step 3
*and* set it as a repo secret (`TF_GITHUB_RUNNER_PAT`) so CI's own `plan`
job for this service - which runs on the very runner this PAT bootstraps -
can also plan changes to it.

## 2. Gather the other required values

Same as every other service here - these come from env vars, never a
committed `.tfvars`:

- `TF_VAR_proxmox_endpoint`, `TF_VAR_proxmox_password`, `TF_VAR_proxmox_node`
- `TF_VAR_ssh_public_key`
- `TF_VAR_github_runner_pat` - the PAT from step 1
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for the MinIO state backend

`github_repo`, `runner_labels`, and `runner_image_tag` all have defaults in
`variables.tf` that should already be correct for this repo - override only
if you're pointing this at something else.

## 3. Apply locally

```
cd environments/homelab/gha-runner
terraform init
terraform apply
```

This is the manual, one-time step ADR-0005 calls out. Everything after
this can go through the normal PR flow, once the runner CI depends on
actually exists to run it.

## 4. Verify registration

Check **Settings → Actions → Runners** on
`github.com/NerdIT-Tech/gitops`. You should see a runner online with
labels `self-hosted` and `homelab`. If it's not showing up:

```
# from the Proxmox host or via SSH to the VM:
podman logs gha-runner
```

A common cause is the PAT lacking the Administration permission (or
`repo` scope for classic PATs) needed to call the runner registration API.

## 5. Confirm CI can actually schedule on it

Open any PR that touches a `.tf` or `.tftpl` file. The `plan` job in
`terraform-pr.yml` should pick up the runner and complete. If it stays
queued, double check the runner's labels match `runs-on: [self-hosted,
homelab]` exactly.

## Rotating the PAT

```
export TF_VAR_github_runner_pat=<new PAT>
terraform apply
```

This updates the Ignition-seeded file, but **not** the live podman secret
the running container is using - that's only re-seeded by
`gha-runner-secret.service` on boot. Reboot the VM (or manually run
`systemctl restart gha-runner-secret.service && systemctl restart
gha-runner.service` on it) after rotating.

## Troubleshooting

- **Runner never comes online**: `podman logs gha-runner` on the VM first.
  Most failures here are PAT scope/permission issues, not infra issues.
- **Runner shows up but jobs never start**: check `LABELS` actually applied
  (`podman inspect gha-runner`) matches what `terraform-pr.yml` expects.
- **VM won't boot / Ignition errors**: same fingerprint-drift caveat as
  every other service here - see the
  [module README](../../../modules/fcos-quadlet-vm/README.md)'s rebuild
  runbook if you're re-applying config changes to an already-provisioned
  runner VM, not just the first bootstrap.
