#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for file_read tool behavior.
#
# Usage:
#   bats tests/tools/test_file_read.sh

setup() {
	export TOOL_ARGS=''
}

@test "file_read rejects render argument" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_read.sh
TOOL_ARGS='{"path":"README.md","render":"text"}'
file_read_parse_args
SCRIPT

	[ "$status" -ne 0 ]
}

@test "file_read renders text files as fenced markdown" {
	run bash <<'SCRIPT'
set -euo pipefail
sample_path="$(mktemp --suffix=.txt)"
cat >"${sample_path}" <<'TEXT'
line one
line two
TEXT
source ./src/tools/files/file_read.sh
TOOL_ARGS=$(jq -nc --arg path "${sample_path}" '{path:$path,page:1,page_size:10}')
output=$(tool_file_read)
content=$(jq -r '.content_markdown' <<<"${output}")
[[ "${content}" == *'```text'* ]]
[[ "${content}" == *"line one"* ]]
SCRIPT

	[ "$status" -eq 0 ]
}

@test "file_read rejects unsupported file types" {
	run bash <<'SCRIPT'
set -euo pipefail
sample_path="$(mktemp --suffix=.unknown)"
printf 'data' >"${sample_path}"
source ./src/tools/files/file_read.sh
TOOL_ARGS=$(jq -nc --arg path "${sample_path}" '{path:$path}')
tool_file_read
SCRIPT

	[ "$status" -ne 0 ]
}
