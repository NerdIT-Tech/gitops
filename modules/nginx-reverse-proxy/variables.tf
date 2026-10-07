variable "proxy_name" {
  description = "Namespaces everything this module renders: the Quadlet unit (<proxy_name>-proxy.container, generating <proxy_name>-proxy.service), the container name, the firewalld service (<proxy_name>-proxy), the firewall-enabling oneshot unit, the cert-reload path/service pair, and the rendered nginx.conf's host path (/etc/<proxy_name>-proxy/nginx.conf). Deliberately suffixed -proxy rather than reusing the proxied service's bare name - modules/omada already owns a firewalld service literally named \"omada\" on the same VM, and Ignition's config merge keys storage.files/systemd.units by path/name, so an identically-named file or unit from this module would silently overwrite (not add to) the proxied service's own. Must be unique per VM if more than one instance of this module is ever composed into the same extra_butane_snippets list."
  type        = string
}

variable "server_names" {
  description = "Hostnames for nginx's server_name directive (space-joined in main.tf before rendering). Should be a subset of the paired porkbun-acme-tls instance's domain_names/SANs - nginx will present that certificate for whichever of these names a client requests, and a name outside the cert's SANs will just get a browser TLS warning, not a hard failure. This module has no visibility into the paired porkbun-acme-tls instance's domain_names to validate that relationship itself; keeping them in sync is the composing environment's job (see environments/homelab/omada/omada.tf)."
  type        = list(string)

  validation {
    condition     = length(var.server_names) > 0
    error_message = "server_names must contain at least one hostname."
  }
}

variable "listen_port" {
  description = "TCP port nginx terminates TLS on (the https server block's listen directive). 443 is the sane default for anything meant to be reachable as a normal https:// URL without a client typing a port number; override only if something else on the VM already owns 443."
  type        = number
  default     = 443
}

variable "redirect_http" {
  description = "Render a second nginx server block on http_port that 301-redirects every request to https://<host><request_uri> on listen_port, so a client that types the bare hostname (defaulting to port 80) doesn't just get a connection refused or an unencrypted proxy pass-through. Disable only if nothing should be listening on http_port at all (e.g. it's already owned by something else on the VM, or the caller wants plaintext HTTP to silently go nowhere rather than redirect)."
  type        = bool
  default     = true
}

variable "http_port" {
  description = "Plaintext HTTP port nginx listens on for the redirect-to-HTTPS server block. Only opened in firewalld, and only rendered into nginx.conf at all, when redirect_http is true - see that variable's validation for why it can't collide with listen_port."
  type        = number
  default     = 80

  validation {
    condition     = !var.redirect_http || var.http_port != var.listen_port
    error_message = "http_port must differ from listen_port when redirect_http is true - nginx can't bind both a plaintext redirect block and the TLS-terminating block to the same port."
  }
}

variable "upstream_host" {
  description = "Host nginx proxies to via proxy_pass. Defaults to 127.0.0.1 on the assumption the proxied container runs Network=host on the same VM (the way modules/omada's controller does) - point this elsewhere only if the upstream genuinely lives off-VM, which changes the trust story (proxy_pass traffic to a non-loopback host leaves this VM in plaintext HTTP unless the upstream itself terminates TLS again)."
  type        = string
  default     = "127.0.0.1"
}

variable "upstream_port" {
  description = "Port nginx proxies to on upstream_host - e.g. the proxied service's plain-HTTP management port (see modules/omada's manage_http_port). No default: unlike upstream_host, there's no sane guess for this, it depends entirely on what's being fronted. The composing environment is responsible for keeping this in sync with whatever port the proxied service is actually listening on - this module has no visibility into that module's variables to check for itself."
  type        = number
}

variable "tls_cert_dir" {
  description = "Host directory bind-mounted read-only into the nginx container as /cert, containing tls_cert_filename/tls_key_filename. Must match the paired porkbun-acme-tls module instance's output_dir - same convention modules/omada's tls_cert_dir used before TLS termination moved here."
  type        = string
}

variable "tls_cert_filename" {
  description = "Filename (fullchain: leaf cert + intermediates) under tls_cert_dir, passed to nginx's ssl_certificate directive. Must match the paired porkbun-acme-tls instance's output_cert_filename."
  type        = string
  default     = "tls.crt"
}

variable "tls_key_filename" {
  description = "Filename (private key) under tls_cert_dir, passed to nginx's ssl_certificate_key directive. Must match the paired porkbun-acme-tls instance's output_key_filename."
  type        = string
  default     = "tls.key"
}

variable "acme_service_name" {
  description = "systemd unit name of the ACME issuance/renewal service (the paired porkbun-acme-tls module instance's acme_service_name output) to order this proxy's first start after. Fails closed by design, same as modules/omada's enable_tls did before TLS moved here: nginx has nothing to serve on listen_port without a cert, so blocking its first start on a successful initial issuance is preferable to it starting and failing to bind, or starting with a self-signed placeholder a caller forgot to swap out."
  type        = string
}

variable "nginx_image_tag" {
  description = "Tag of docker.io/library/nginx to run. Pin this to a specific minor version (e.g. \"1.27-alpine\"), never \"latest\" or \"mainline\" - same reasoning as modules/omada's omada_image_tag and modules/porkbun-acme-tls's certbot_image_tag: AutoUpdate=registry already handles picking up new builds of whatever tag you pin, so floating the tag itself only removes your ability to control *when* a config-breaking nginx upgrade lands on a VM that's otherwise stateless but still fronting a live service."
  type        = string
  default     = "1.27-alpine"
}
