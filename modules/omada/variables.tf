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
