terraform {
  required_version = ">= 1.10.0" # for the S3 native-locking backend used at the env layer

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    ct = {
      source  = "poseidon/ct"
      version = "~> 0.13"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    # terraform_data is built into Terraform core (>= 1.4) - no provider needed.
  }
}
