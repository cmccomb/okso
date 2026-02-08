#!/usr/bin/env bats
# shellcheck shell=bash
#
# Regression tests for file_read format handling.
#
# Usage:
#   bats tests/tools/test_file_read_xlsx.sh

@test "file_read rejects xlsx inputs with a clear error" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_read.sh
xlsx_file="$(mktemp -t file_read.XXXXXX).xlsx"
printf "fake" >"${xlsx_file}"
TOOL_ARGS=$(jq -nc --arg path "${xlsx_file}" '{path:$path}')

set +e
output=$(tool_file_read 2>&1)
status=$?
set -e

rm -f "${xlsx_file}"

if [[ ${status} -eq 0 ]]; then
	echo "expected file_read to fail for xlsx inputs"
	exit 1
fi

echo "${output}" | jq -e 'select(.message == "XLSX files are not supported")' >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
