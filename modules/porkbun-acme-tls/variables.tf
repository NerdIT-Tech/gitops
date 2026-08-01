variable "cert_name" {
  description = "certbot --cert-name, and the /etc/letsencrypt/live/<cert_name> lineage directory. Also namespaces this cert's systemd units, credentials file, and state directories on the VM - must be unique per VM if more than one porkbun-acme-tls instance is ever composed into the same extra_butane_snippets list."
  type        = string
}

variable "domain_names" {
  description = "SANs for the certificate, e.g. [\"omada01.canady.cloud\", \"omada.canady.cloud\"]. All are requested on one certificate via one certbot invocation - see this module's README for why one multi-SAN cert was chosen over one cert per name."
  type        = list(string)

  validation {
    condition     = length(var.domain_names) > 0
    error_message = "domain_names must contain at least one domain."
  }
}

variable "acme_email" {
  description = "Contact email passed to certbot --email, for Let's Encrypt expiry/revocation notices."
  type        = string
}

variable "porkbun_api_key" {
  description = "Porkbun API key (rendered as dns_porkbun_key in the on-VM credentials file). Porkbun API keys are account-wide, not scoped to a single domain - treat this with the same sensitivity as a full-registrar-account credential, not a per-service secret. It is embedded in the rendered Ignition config, which means it ends up in plaintext in Terraform state, the CI runner's rendered .ign file, and the uploaded install ISO - not just on the one VM that needs it. Restrict this key to known egress IPs in Porkbun's account dashboard if possible."
  type        = string
  sensitive   = true
}

variable "porkbun_api_secret" {
  description = "Porkbun API secret paired with porkbun_api_key (rendered as dns_porkbun_secret). Same exposure caveat as porkbun_api_key applies here."
  type        = string
  sensitive   = true
}

variable "output_dir" {
  description = "Directory the renewed fullchain/privkey PEM pair is copied into on every issuance/renewal, owned by output_owner_uid/output_owner_gid. The consuming service must read from (or mount) this same path - this module has no knowledge of what consumes the cert."
  type        = string
}

variable "output_cert_filename" {
  description = "Filename (fullchain: leaf cert + intermediates) written under output_dir."
  type        = string
  default     = "tls.crt"
}

variable "output_key_filename" {
  description = "Filename (private key) written under output_dir."
  type        = string
  default     = "tls.key"
}

variable "output_owner_uid" {
  description = "UID that owns output_dir and the files written into it - set to match whatever process needs to read the cert (e.g. the consuming container's PUID)."
  type        = number
}

variable "output_owner_gid" {
  description = "GID that owns output_dir and the files written into it - set to match whatever process needs to read the cert (e.g. the consuming container's PGID)."
  type        = number
}

variable "certbot_image_tag" {
  description = "Tag of docker.io/infinityofspace/certbot_dns_porkbun to run. Pin to a specific version, never \"latest\" - this is a much smaller/less-scrutinized image than e.g. mbentley/omada-controller, worth being deliberate about which exact build runs with an account-wide API credential mounted into it."
  type        = string
  default     = "v0.11.0"
}
