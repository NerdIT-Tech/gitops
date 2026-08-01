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

variable "credentials_file" {
  description = <<-EOT
    Path on the VM (not the file's content - this module never sees or
    renders the Porkbun API key/secret) to the certbot-dns-porkbun
    credentials INI file (dns_porkbun_key=.../dns_porkbun_secret=...). This
    module only creates the containing directory (mode 0700) and reads from
    this path at runtime - the file itself must be written out-of-band
    (e.g. over SSH) before the first issuance can succeed. Defaults to
    /etc/porkbun-credentials/<cert_name>.ini (see main.tf) if left null.
    See this module's README for why the credential is deliberately never
    interpolated into Terraform-rendered content.
  EOT
  type        = string
  default     = null
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
