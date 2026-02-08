#!/usr/bin/env bash
# shellcheck shell=bash
# Run shellcheck across source, scripts, and tests.
# Usage: bash ./scripts/ci/run-shellcheck.sh

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "${ROOT_DIR}"

failures=0
while IFS= read -r file; do
	[[ -z "${file}" ]] && continue
	if [[ "${file}" == "src/bin/okso" ]]; then
		# Source-following can become pathologically slow on the entrypoint's deep
		# source graph; lint the entrypoint directly and ignore SC1091 for it.
		if ! shellcheck -e SC1091 "${file}"; then
			failures=1
		fi
		continue
	fi
	if ! shellcheck -x "${file}"; then
		failures=1
	fi
done < <(find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) | sort)

exit "${failures}"
