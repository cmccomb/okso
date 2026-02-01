#!/usr/bin/env bash
# shellcheck shell=bash
# Simple documentation/placeholder checks for CI.

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "${ROOT_DIR}"

errors=0

echo "Checking for unresolved workflow placeholders ({{...}}) in workflows/"
if rg -n "\{\{[^}]+\}\}" workflows; then
  echo "Found unresolved placeholders in workflows/ (see above)."
  errors=$((errors+1))
fi

echo "Checking for TODO/TBD/__MISSING__ tokens in src/ and docs/"
if rg -n "\b(TODO|TBD|__MISSING__)\b" src docs workflows; then
  echo "Found TODO/TBD markers (see above)."
  errors=$((errors+1))
fi

echo "Checking for shebang and shellcheck header in shell scripts under src/"
missing_header=$(find src -name "*.sh" -print0 | xargs -0 -n1 sh -c 'head -n6 "$0" | rg -q "^#!.*bash" && head -n6 "$0" | rg -q "shellcheck shell=bash" || echo "$0"' 2>/dev/null || true)
if [[ -n "${missing_header}" ]]; then
  echo "Scripts missing standard header:" >&2
  echo "${missing_header}"
  errors=$((errors+1))
fi

if [[ ${errors} -ne 0 ]]; then
  echo "Documentation checks failed: ${errors} issues found." >&2
  exit 2
fi

echo "Documentation checks passed."
