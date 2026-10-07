# nginx-reverse-proxy

Renders the Butane/Ignition snippet for an nginx TLS-terminating reverse
proxy running as a Podman Quadlet unit: the `[Container]` unit itself
(`docker.io/library/nginx`), a rendered `nginx.conf` server block that
proxies to one upstream `host:port` over plain HTTP, an optional
plaintext-HTTP-to-HTTPS redirect block, a `firewalld` service covering
whichever of `listen_port`/`http_port` are actually in use, the oneshot
systemd unit that registers that firewalld service before the container
starts, and a cert-reload trigger for when the paired certificate renews.

## What this module is (and isn't)

Same shape as [`modules/omada`](../omada) and
[`modules/porkbun-acme-tls`](../porkbun-acme-tls) (see
[ADR-0008](../../docs/adrs/0008-decouple-omada-service-from-vm-provisioning.md)
for the reasoning this mirrors): **no resources, no data sources, no
provider requirements.** It takes service-shaped inputs (a proxy name, the
hostnames it should answer to, where the TLS cert lives, where to proxy
requests) and produces one output, `butane_snippet`. It does not know or
care what boots that config, and it does not know or care what's actually
listening on `upstream_host:upstream_port` - it only proxies HTTP(S)
traffic there.

To actually run it, compose this module's `butane_snippet` output into a
VM-provisioning module's `extra_butane_snippets` list alongside the proxied
service's own snippet and a paired
[`modules/porkbun-acme-tls`](../porkbun-acme-tls) instance's snippet - see
`environments/homelab/omada/omada.tf` for the composition.

## Why this is a separate module, not folded into `modules/omada`

Omada is the first consumer, but nothing about a TLS-terminating reverse
proxy in front of a loopback HTTP port is Omada-specific - the next service
that wants nginx (rather than, or in addition to, its own built-in TLS
support) in front of it should be able to compose this module unchanged,
the same way a second service wanting a Porkbun-issued cert composes
`modules/porkbun-acme-tls` unchanged rather than that capability having
been folded into `modules/omada` in the first place (see
[ADR-0009](../../docs/adrs/0009-porkbun-dns01-acme-module.md)). Keeping this
generic also keeps the proxied service's own module honest about not
owning TLS itself once something else is terminating it in front - see
"Why TLS moved here" below.

## Naming: `<proxy_name>-proxy`, not `<proxy_name>`

Every artifact this module renders is namespaced `${proxy_name}-proxy`
(firewalld service, Quadlet unit, systemd units, config path) rather than
bare `proxy_name`. This is deliberate, not decorative: Ignition's config
merge keys `storage.files` by path and `systemd.units` by name, so if this
module reused the proxied service's own name (e.g. `"omada"`, which
`modules/omada` already uses for its own firewalld service and Quadlet
unit), the two modules' snippets - composed into the same
`extra_butane_snippets` list on the same VM - would silently overwrite each
other's files/units instead of adding to them. Pick `proxy_name` to match
the service it fronts (e.g. `"omada"`) and let this module's own `-proxy`
suffix keep it collision-free.

## TLS: this module is the sole terminator

Point `tls_cert_dir` at a [`modules/porkbun-acme-tls`](../porkbun-acme-tls)
instance's `output_dir` and `acme_service_name` at that same instance's
`acme_service_name` output, the same pairing `modules/omada`'s `enable_tls`
used to do directly. This module's Quadlet unit gets `After=`/`Requires=`
on `acme_service_name`, blocking its own first start until the paired
module's initial ACME issuance succeeds (fails closed by design - nginx has
nothing to bind `listen_port` with otherwise). A `<proxy_name>-proxy-cert-reload.path`
unit watches `tls_cert_dir/tls_cert_filename` and runs
`podman exec <proxy_name>-proxy nginx -s reload` on every subsequent
renewal - a graceful, connection-preserving reload (see the comment in
`butane/nginx-reverse-proxy.bu.tftpl` for why this differs from
`modules/omada`'s cert-reload, which has to fully restart the container).

**The proxied service should not also be terminating TLS on the same
hostname.** Pick one owner. When this module is composed in front of a
service, that service's own TLS support (e.g. `modules/omada`'s
`enable_tls`) should be turned off - two things both trying to own
`server_name`'s certificate is a maintenance trap, not defense in depth,
since a client only ever sees the one this module presents.

## Scope: management/API traffic only

This module proxies exactly one upstream `host:port` over HTTP(S). It has
no opinion on, and should not be used for, protocols that aren't
HTTP-shaped - discovery broadcasts, captive-portal redirects with
protocol-specific expectations, raw TCP/UDP services. For Omada
specifically, that means only the controller's management UI is fronted by
this module; the captive portal and EAP discovery ports stay directly
exposed by `modules/omada`, unchanged - see
`environments/homelab/omada/README.md`.

## Firewalld

`listen_port` is always opened. `http_port` is opened only when
`redirect_http` is true - there's nothing listening on it otherwise, and
opening a port nothing's bound to is just attack surface for no benefit.
Both are de-duplicated via `distinct()` in `main.tf`, the same reasoning
`modules/omada` uses for its own `tcp_ports` local: stable ordering across
plans so `ignition_fingerprint` doesn't flap for no reason.

## Stateless

Unlike `modules/omada`'s controller (which owns real state on
`/var/lib/omada/data`), this module's container has no state of its own -
`nginx.conf` is rendered fresh into the Ignition file on every `terraform
apply`, and the container itself holds nothing across restarts. A Butane
change here still only takes effect on a fresh VM install
([ADR-0002](../../docs/adrs/0002-ignition-fingerprint-not-replace-triggered.md):
Ignition is first-boot-only), but unlike the proxied service, there's no
data to back up first - the environment composing this module is free to
decide auto-recreation is safe for *this* module's own changes, even if
the VM as a whole (because of what else is composed alongside it) still
needs the manual rebuild+restore runbook.
