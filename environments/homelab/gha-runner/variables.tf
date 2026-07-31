variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token, format user@realm!token-id=secret. Needs enough role permissions for VM lifecycle + image/ISO upload + datastore operations - see ADR-0007."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  type    = bool
  default = false
}

variable "proxmox_node" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "github_repo" {
  description = "owner/repo this runner registers against (RUNNER_SCOPE=repo)."
  type        = string
  default     = "NerdIT-Tech/gitops"
}

variable "github_app_id" {
  description = "GitHub App ID used to mint the runner's registration token at container start (App auth, not a PAT - see ADR-0005). Not sensitive on its own; shown on the App's public settings page."
  type        = string
}

variable "github_app_private_key" {
  description = "GitHub App private key (full PEM contents, real newlines - not the \\n-escaped form). See environments/homelab/gha-runner/README.md for setup."
  type        = string
  sensitive   = true
}

variable "runner_labels" {
  description = "Comma-separated labels this runner registers with - must include whatever terraform-pr.yml's `runs-on: [self-hosted, ...]` expects."
  type        = string
  default     = "self-hosted,homelab"
}

variable "runner_image_tag" {
  description = "myoung34/github-runner tag. No immutable semver tags are published upstream - these are nightly-rebuilt OS-flavor channels (ubuntu-noble, ubuntu-jammy, etc). See ADR-0005 for why this floats instead of pinning."
  type        = string
  default     = "ubuntu-noble"
}
