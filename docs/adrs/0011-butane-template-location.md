---
id: R-TF-011
applies_to: ["services/**", "modules/**/butane/**", "environments/**"]
status: accepted
---

# Butane templates live at services/ or modules/, graduated by reuse

MUST: put a service's Butane template at `services/<service>/butane/`, rendered directly by the environment root via `templatefile()`.
MUST: promote the template into `modules/<name>/butane/` only when the service definition needs portability (composable against a different VM provisioner) or reuse across roots — then it becomes a snippet module per R-TF-008.
MUST NOT: keep both copies, or reach into another layer's template path from a module.

## Why

Omada graduated to `modules/omada` because it must run against any VM provisioner; gha-runner stays at `services/gha-runner/butane/` because nothing but the gha-runner root consumes it. A forced single home either over-modularizes one-off services or under-modularizes portable ones.

## Verify

    find . -path ./.terraform -prune -o -name '*.bu.tftpl' -print | grep -vE '^\./(services|modules)/' && echo FAIL || echo OK
