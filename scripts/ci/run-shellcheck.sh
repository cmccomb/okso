#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "${ROOT_DIR}"

failures=0
while IFS= read -r file; do
	[[ -z "${file}" ]] && continue
	if ! shellcheck -x "${file}"; then
		failures=1
	fi
done < <(find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) | sort)

exit "${failures}"
