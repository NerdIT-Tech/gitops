# Remote state so CI (and you, from any machine) share one source of truth.
# Any S3-compatible store works here (MinIO, Backblaze B2 w/ S3 API, etc).
# use_lockfile needs Terraform >= 1.10 and an S3-compatible backend that
# supports conditional writes (If-None-Match) - recent MinIO does; check
# your version if locking errors show up as silently ignored instead of
# enforced.
#
# Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env vars
# (or your CI secret store) - never commit them here.

terraform {
  backend "s3" {
    bucket = "tf-state-homelab"
    # One Terraform root per service, one state key per root (ADR-0004) -
    # each service's key must be unique, both from every other service here
    # AND from unrelated repos/configs that might share this bucket. If
    # you're copy-pasting this file for a new service, change this key
    # first - forgetting to means the new service silently shares state
    # with (and can clobber) whatever this key currently points at.
    key                         = "omada/terraform.tfstate"
    region                      = "us-east-1" # arbitrary for MinIO, but required
    endpoints                   = { s3 = "https://minio.example.lan:9000" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_lockfile                = true
  }
}
