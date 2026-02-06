#!/usr/bin/env bats
#
# Tests for the file_read tool.
#
# Usage:
#   bats tests/tools/test_file_read.sh

@test "file_read renders text files as fenced markdown" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/index.sh
text_file=$(mktemp -t file_read.XXXXXX)
printf "Hello world" >"${text_file}"
TOOL_ARGS=$(jq -nc --arg path "${text_file}" '{"input":$path}')
output=$(tool_file_read)
jq -e '.pages[0] | startswith("```text\n") and contains("Hello world")' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "file_read wraps each page for text inputs" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/index.sh
text_file=$(mktemp -t file_read.XXXXXX)
printf "abcdefghij" >"${text_file}"
FILE_READ_PAGE_SIZE=4
TOOL_ARGS=$(jq -nc --arg path "${text_file}" '{"input":$path}')
output=$(tool_file_read)
jq -e '.pages | length == 3' <<<"${output}" >/dev/null
jq -e '.pages[0] | contains("abcd")' <<<"${output}" >/dev/null
jq -e '.pages[1] | contains("efgh")' <<<"${output}" >/dev/null
jq -e '.pages[2] | contains("ij")' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
