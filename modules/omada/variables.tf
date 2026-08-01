variable "omada_image_tag" {
  description = "Tag of docker.io/mbentley/omada-controller to run. Pin this to the current controller's version when migrating an existing deployment - jumping major versions on first boot of a fresh install can fail the controller's own upgrade migration. See the rebuild runbook in the environment README before bumping this on an already-provisioned VM (ADR-0002/ADR-0008: Ignition is first-boot-only, so this only takes effect on a fresh install)."
  type        = string
}

variable "container_puid" {
  description = "UID that owns /var/lib/omada/{data,logs} on the host and that the container runs as (PUID env var)."
  type        = number
}

variable "container_pgid" {
  description = "GID that owns /var/lib/omada/{data,logs} on the host and that the container runs as (PGID env var)."
  type        = number
}

variable "timezone" {
  description = "IANA zone name (e.g. America/New_York) passed to the container as TZ. Independent of the VM host's own timezone (fcos-quadlet-vm's own `timezone` variable) - set both to the same value if you want the container's logs/scheduling to match host local time."
  type        = string
  default     = "Etc/UTC"
}

# The controller image exposes these four ports via env vars, so they're
# genuinely reconfigurable (e.g. to front the controller with a reverse
# proxy that already owns 8443, or to run more than one instance on
# non-conflicting ports). The EAP discovery ports (UDP 29810-29813, TCP
# 29814) are NOT exposed as env vars by the image - they're fixed by the
# discovery protocol itself - so they're not parameterized here; they're
# hardcoded in butane/omada.bu.tftpl.
variable "manage_http_port" {
  description = "Controller management UI HTTP port (MANAGE_HTTP_PORT)."
  type        = number
  default     = 8088
}

variable "manage_https_port" {
  description = "Controller management UI HTTPS port (MANAGE_HTTPS_PORT). Also used for the container's own HealthCmd."
  type        = number
  default     = 8043
}

variable "portal_http_port" {
  description = "Captive-portal HTTP port (PORTAL_HTTP_PORT)."
  type        = number
  default     = 8088
}

variable "portal_https_port" {
  description = "Captive-portal HTTPS port (PORTAL_HTTPS_PORT)."
  type        = number
  default     = 8843
}

variable "enable_tls" {
  description = "Mount a TLS cert/key pair into the controller at /cert and block the controller's first start on a successful ACME issuance (After=/Requires= on acme_service_name). Pair with modules/porkbun-acme-tls, composed into the same extra_butane_snippets list - see this module's README for the controller-UI-cert conflict warning before enabling this on a VM that has ever had a certificate installed through Omada's own web UI."
  type        = bool
  default     = false
}

variable "tls_cert_dir" {
  description = "Host directory bind-mounted read-only into the controller as /cert, containing tls.crt/tls.key (mbentley/omada-controller's default expected filenames). Must match the paired porkbun-acme-tls module instance's output_dir. Required when enable_tls is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_tls || var.tls_cert_dir != null
    error_message = "tls_cert_dir is required when enable_tls is true."
  }
}

variable "acme_service_name" {
  description = "systemd unit name of the ACME issuance/renewal service (the paired porkbun-acme-tls module instance's acme_service_name output) to order the controller's first start after. Required when enable_tls is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_tls || var.acme_service_name != null
    error_message = "acme_service_name is required when enable_tls is true."
  }
}
