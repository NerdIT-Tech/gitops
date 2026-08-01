#!/usr/bin/env bash
# PostToolUse hook (Write|Edit): runs the same checks as .github/workflows/terraform-pr.yml
# (fmt, validate, tflint, trivy) locally, scoped to whichever Terraform root the
# edited file belongs to, right after Claude edits it.
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')"
[ -z "$file" ] && exit 0

case "$file" in
  *.tf|*.tftpl|*.tflint.hcl) ;;
  *) exit 0 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 0

rel="${file#"$repo_root"/}"

# environments/homelab/<service>/ is its own Terraform root with its own
# state (ADR-0004) - not one shared root for the whole environment. Derive
# the root from the path instead of hardcoding a service name, so this stays
# correct as services are added.
case "$rel" in
  modules/*/*)
    mod="${rel#modules/}"
    mod="${mod%%/*}"
    root="modules/$mod"
    ;;
  environments/homelab/*/*)
    svc="${rel#environments/homelab/}"
    svc="${svc%%/*}"
    root="environments/homelab/$svc"
    ;;
  # services/<name>/*.tftpl aren't a root themselves - they're templatefile()'d
  # from environments/homelab/<name>/, so that's the root that renders them.
  # Assumes the environments/homelab/<name> <-> services/<name> naming match.
  services/*)
    svc="${rel#services/}"
    svc="${svc%%/*}"
    root="environments/homelab/$svc"
    ;;
  *) root="" ;;
esac

status=0

echo "== terraform fmt =="
if [ -n "$root" ]; then
  terraform fmt "$root" || status=1
else
  terraform fmt -recursive . || status=1
fi

if [ -n "$root" ]; then
  echo "== terraform validate ($root) =="
  if [ ! -d "$root/.terraform" ]; then
    terraform -chdir="$root" init -backend=false -input=false >/dev/null 2>&1
  fi
  terraform -chdir="$root" validate || status=1
fi

echo "== tflint =="
tflint --init >/dev/null 2>&1
tflint --recursive || status=1

if command -v trivy >/dev/null 2>&1; then
  echo "== trivy config scan (${root:-.}) =="
  trivy config --quiet --severity CRITICAL,HIGH --exit-code 1 "${root:-.}" || status=1
else
  echo "trivy not found locally - skipping IaC scan (CI still runs it)"
fi

exit $status
