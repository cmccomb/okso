#!/usr/bin/env bash
# shellcheck shell=bash
# Simple documentation/placeholder checks for CI.

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "${ROOT_DIR}"

errors=0

echo "Checking for unresolved placeholders outside approved examples"
if rg -n "\{\{[^}]+\}\}" src docs \
	--glob '!src/prompts/executor.md' \
	--glob '!docs/reference/tools.md' \
	--glob '!docs/documentation-guidelines.md'; then
	echo "Found unresolved placeholders outside approved examples (see above)."
	errors=$((errors + 1))
fi

echo "Checking for TODO/TBD/__MISSING__ tokens in src/ and docs/"
if rg -n "\b(TODO|TBD|__MISSING__)\b" src docs workflows \
	--glob '!src/prompts/executor.md' \
	--glob '!src/tools/terminal/index.sh' \
	--glob '!docs/documentation-guidelines.md'; then
	echo "Found TODO/TBD markers (see above)."
	errors=$((errors + 1))
fi

echo "Checking for shebang and shellcheck header in shell scripts under src/"
missing_header=""
while IFS= read -r -d '' file; do
	if ! head -n6 "${file}" | rg -q "^#!.*bash" || ! head -n6 "${file}" | rg -q "shellcheck shell=bash"; then
		missing_header+="${file}"$'\n'
	fi
done < <(find src -name "*.sh" -print0)
if [[ -n "${missing_header}" ]]; then
	echo "Scripts missing standard header:" >&2
	printf '%s' "${missing_header}"
	errors=$((errors + 1))
fi

if [[ ${errors} -ne 0 ]]; then
	echo "Documentation checks failed: ${errors} issues found." >&2
	exit 2
fi

echo "Documentation checks passed."
