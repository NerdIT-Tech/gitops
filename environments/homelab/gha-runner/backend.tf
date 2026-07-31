# Remote state so CI (and you, from any machine) share one source of truth.
# Real AWS S3 (not MinIO) - use_lockfile's native conditional-write locking
# needs Terraform >= 1.10, which real S3 supports unconditionally.
#
# Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars
# (or your CI secret store) - never commit them here.

terraform {
  backend "s3" {
    bucket = "nerdit-tech-terraform-state"
    # One Terraform root per service, one state key per root (ADR-0004) -
    # each service's key must be unique, both from every other service here
    # AND from unrelated repos/configs that might share this bucket -
    # including infra-terraform, which uses this same bucket. If you're
    # copy-pasting this file for a new service, change this key first -
    # forgetting to means the new service silently shares state with (and
    # can clobber) whatever this key currently points at.
    key          = "gitops/gha-runner/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
