# Operations standards

Homelab scale: one Proxmox node, FCOS VMs, stateless-ish services. These are the expectations; automation comes when a second service needs it.

## Health

- Each service container has a Quadlet-level restart policy (`Restart=on-failure`).
- After apply, the apply workflow nudges the affected systemd units (`*.service` nudge) — check `journalctl -u <unit>` on the VM if a service misbehaves post-deploy.
- Verify externally: service endpoint answers (e.g. Omada UI reachable through nginx-reverse-proxy).

## Backup

- Terraform state: S3 backend (`nerdit-tech-terraform-state`), versioned bucket; state is recoverable from S3 + rerunning `terraform import` as fallback.
- VM disks: currently no snapshot/backup automation (see environments/homelab/omada/README.md). Recommended: weekly Proxmox snapshot of stateful VMs, copied off-node when a second datastore exists.
- BUT: services are cattle — everything rebuildable from repo + Porkbun DNS + GitHub config. Treat VM loss as rebuild, not restore.

## Restore / rebuild

1. `terraform init` in the service root, `terraform apply` to recreate the VM.
2. Re-seed Porkbun credentials per R-DNS-010 (apply workflow does this automatically post-apply).
3. Confirm service health checks above.
