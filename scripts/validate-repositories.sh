#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
repos=(platform-bootstrap platform-modules platform-live platform-config helm-charts sample-api docs)
failed=0
for repo in "${repos[@]}"; do
  if [[ ! -d "$ROOT/$repo" ]]; then echo "MISSING: $ROOT/$repo"; failed=1; fi
done
command -v terraform >/dev/null && {
  terraform -chdir="$ROOT/platform-bootstrap" fmt -check -recursive
  terraform -chdir="$ROOT/platform-modules" fmt -check -recursive
  terraform -chdir="$ROOT/platform-live" fmt -check -recursive
} || echo "SKIP: terraform not installed"
command -v helm >/dev/null && {
  helm lint "$ROOT/helm-charts/charts/sample-api"
  helm template sample-api "$ROOT/helm-charts/charts/sample-api" >/tmp/sample-api-rendered.yaml
} || echo "SKIP: helm not installed"
command -v kubectl >/dev/null && [[ -f /tmp/sample-api-rendered.yaml ]] &&   kubectl apply --dry-run=client -f /tmp/sample-api-rendered.yaml >/dev/null || true
if grep -RIn 'targetRevision: "\*"' "$ROOT/platform-config"; then
  echo "FAIL: unpinned Argo CD chart versions found"; failed=1
fi
if grep -RIn 'REPLACE_' "$ROOT" --exclude-dir=.git; then
  echo "WARN: unresolved placeholders found"
fi
exit "$failed"
