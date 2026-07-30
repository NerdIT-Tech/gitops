variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_ssh_username" {
  type    = string
  default = "root"
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

variable "github_runner_pat" {
  description = "GitHub PAT (classic: repo scope, or fine-grained: Administration read/write) used to mint the runner's registration token at container start. See environments/homelab/gha-runner/README.md."
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
