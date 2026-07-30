# ADR-0005: Run the CI self-hosted runner as a service managed by this same repo

**Status:** Accepted **Date:** 2026-07-30

## Context

`.github/workflows/terraform-pr.yml`'s `plan` job runs on
`runs-on: [self-hosted, homelab]` because Proxmox and the MinIO state
backend only exist on the homelab's private `.lan` network — a
GitHub-hosted runner can't reach either. Something has to provide that
`self-hosted, homelab`-labeled runner.

## Decision

The runner is itself a service in this repo: `environments/homelab/gha-runner/`
(its own Terraform root + state, per ADR-0004) provisions an FCOS VM via the
`fcos-quadlet-vm` module, running a containerized GitHub Actions runner
(`myoung34/github-runner`) as a Podman Quadlet unit
(`services/gha-runner/butane/gha-runner.bu.tftpl`) — the same pattern as
every other service here, not a hand-built VM or an external machine
outside this repo's IaC.

Three sub-decisions worth calling out:

**Registration via PAT (`ACCESS_TOKEN`), not a manual registration token.**
GitHub's manual registration tokens (from the "Add runner" UI) expire in
about an hour - useless for a declarative config that might not boot
immediately, and useless after any restart. `ACCESS_TOKEN` (a GitHub PAT)
lets the container mint a fresh registration token itself on every start,
so `Restart=always` and VM reboots don't require any manual
re-registration step.

**The PAT goes through a podman secret, not a plain `Environment=`.**
`gha-runner-secret.service` seeds a podman secret from an Ignition-written
file (`/etc/gha-runner/pat`, mode 0600) before the runner container starts;
the Quadlet unit references it via `Secret=gha_runner_pat,type=env,...`
rather than putting the PAT directly in `Environment=`. This keeps it out
of `podman inspect`'s plain environment listing. It does **not** remove the
PAT from the rendered Ignition config uploaded to the Proxmox snippet
datastore, or from Terraform state - both still hold it in cleartext, same
exposure level as everything else in this repo, which already treats
Proxmox root access as the trust boundary (ADR-0001). This is the first
place in the repo a real credential (not just an SSH public key) is baked
into Ignition content; flagging that explicitly rather than leaving it
implicit.

**The image tag floats, it isn't pinned.** Unlike Omada
(`docker.io/mbentley/omada-controller:5.15`, a real semver release),
`myoung34/github-runner` doesn't publish immutable version tags - only
nightly-rebuilt OS-flavor channels (`ubuntu-noble`, `ubuntu-jammy`, etc.),
each one baking in whatever `actions/runner` release was current at build
time. `runner_image_tag` defaults to `ubuntu-noble` (a channel choice, not
a version pin) and `AutoUpdate=registry` + `podman-auto-update.timer` are
enabled so the container actually picks up new nightly builds - this is
the same "let it float, something else keeps it current" shape as
ADR-0003's FCOS stream tracking, not a contradiction of the
pin-what-you-can convention Omada follows. `DISABLE_AUTO_UPDATE=true` is
set on the runner itself so the image's own in-place self-update doesn't
fight with container-level auto-update as the update mechanism.

## Alternatives considered

- **A runner outside this repo's IaC** (a manually-configured machine, or
  one from `infra-terraform`'s domain) — rejected: every other piece of
  homelab infrastructure in this repo is provisioned the same way: FCOS VM
  + Ignition/Butane + Podman Quadlet. Standing up the runner by hand would
  be the one asset in the homelab Proxmox environment not managed as code,
  and would still need this repo's own module to provision on Proxmox
  anyway.
- **Manual registration token instead of `ACCESS_TOKEN`** — rejected; see
  Decision. Incompatible with `Restart=always` and reboot survival.
- **Ephemeral runner mode** (`EPHEMERAL=true`, one job then deregister) —
  not used. This is a single always-on runner for a low-volume homelab CI
  workflow; ephemeral mode is aimed at autoscaling fleets, which doesn't
  apply here and would add re-registration churn for no benefit.

## Consequences

- **Bootstrapping this runner is a chicken-and-egg problem and can't go
  through CI.** `terraform-pr.yml`'s `plan` job needs the runner to already
  exist to run at all. The very first `terraform apply` for
  `environments/homelab/gha-runner/` must be run locally, by hand - see
  `environments/homelab/gha-runner/README.md` for the runbook. Every
  *subsequent* change to this service's config can go through the normal
  PR flow once the runner is up.
- Rotating `github_runner_pat` requires a new `terraform apply` (updates
  the Ignition-seeded file) **and** a reboot or restart of
  `gha-runner-secret.service` on the VM to re-seed the podman secret - a
  live `apply` alone does not rotate the credential the running container
  is using. Not automated; a known gap, not a design goal here.
- If the runner VM goes down, every PR touching `.tf`/`.tftpl` files is
  blocked on the `plan` job (which can't schedule anywhere) until it's back
  - this repo now has exactly the kind of infrastructure-depends-on-itself
  loop that self-hosted CI always creates. Acceptable at homelab scale; a
  second runner would remove the single point of failure if this ever
  becomes a real problem.
