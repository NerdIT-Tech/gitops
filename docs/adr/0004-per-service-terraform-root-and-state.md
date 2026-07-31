# ADR-0004: One Terraform root and state file per service, not one shared environment root

**Status:** Accepted **Date:** 2026-07-30

## Context

`environments/homelab` originally held a single flat set of root files
(`backend.tf`, `providers.tf`, `variables.tf`, plus one `<service>.tf` per
managed service — just `omada.tf` so far). All services in the environment
shared one Terraform root and therefore one state file
(`omada/terraform.tfstate` in the MinIO backend).

This repo manages Proxmox/FCOS VM infrastructure for a single operator, and
is expected to grow to more than one service (Omada today, more later). The
question this ADR answers: should each new service get its own git repo, or
stay in this one? See the discussion that produced this decision for the
full reasoning — in short, splitting repos was rejected (it would turn the
module's free relative-path `source` into a versioned dependency across
repos, and would duplicate the self-hosted-runner CI/secrets setup for no
real isolation gain, since Proxmox/MinIO credentials are shared regardless
of repo boundaries). Staying in one repo, the actual risk that needed
addressing was one shared Terraform state: a bad `apply` touching one
service's resources could jeopardize every other service sharing that same
state and root.

## Decision

Each service gets its own Terraform root directory and backend key under
`environments/homelab/<service>/` (e.g. `environments/homelab/omada/`),
each with its own `backend.tf` (`key = "<service>/terraform.tfstate"`),
`providers.tf`, `variables.tf`, and `<service>.tf` module call. There is no
longer a shared root-level `.tf` file at `environments/homelab/` itself.

## Alternatives considered

- **Split each service into its own git repository** — rejected; see
  Context. The blast-radius problem this ADR addresses is orthogonal to
  repo count and is better solved directly (isolate the state), not by
  paying repo-splitting's costs (module vendoring, duplicated CI/secrets)
  for a benefit it doesn't actually provide here.
- **Keep one shared root, rely on `-target` for surgical applies** —
  rejected as a weak substitute: `-target` is a manual, error-prone escape
  hatch, not a structural guarantee, and every `plan`/`apply` still
  defaults to evaluating every service's resources together.

## Consequences

- Module `source` paths and `templatefile()` calls in each service's `.tf`
  file are now one directory level deeper
  (`../../../modules/fcos-quadlet-vm`, `../../../services/<service>/...`)
  relative to before.
- CI (`.github/workflows/terraform-pr.yml`) and the local
  `.claude/hooks/terraform-check.sh` PostToolUse hook both run
  `fmt`/`validate`/`plan` scoped to the specific service root that changed,
  not the whole environment.
- CI's validate/plan steps became a matrix (`matrix.root` / `matrix.service`
  in `terraform-pr.yml`) once the second service (`gha-runner`) was added -
  each new service needs one line added to those matrix lists. The local
  hook script never had this limitation: it derives the root generically
  from the edited file's path, so it needs no changes as services are
  added, as long as `environments/homelab/<name>/` and `services/<name>/`
  keep using matching names.
- A cross-service change (e.g. a module default that should apply to every
  service) now touches multiple roots/states instead of one — this is the
  accepted tradeoff for isolating each service's blast radius.
