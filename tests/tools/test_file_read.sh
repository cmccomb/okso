#!/usr/bin/env bats
# shellcheck shell=bash
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
jq -e '.content_markdown | startswith("# ") and contains("_Page 1 of 1_") and contains("```text\nHello world\n```")' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "file_read wraps each page for text inputs" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/index.sh
text_file=$(mktemp -t file_read.XXXXXX)
cat >"${text_file}" <<'TEXT'
abcd
efgh
ij
TEXT

TOOL_ARGS=$(jq -nc --arg path "${text_file}" '{"input":$path,"page":1,"page_size":1}')
output_page_1=$(tool_file_read)
jq -e '.page == 1 and .total_pages == 3 and (.content_markdown | contains("_Page 1 of 3_") and contains("```text\nabcd\n```"))' <<<"${output_page_1}" >/dev/null

TOOL_ARGS=$(jq -nc --arg path "${text_file}" '{"input":$path,"page":2,"page_size":1}')
output_page_2=$(tool_file_read)
jq -e '.page == 2 and .total_pages == 3 and (.content_markdown | contains("_Page 2 of 3_") and contains("```text\nefgh\n```"))' <<<"${output_page_2}" >/dev/null

TOOL_ARGS=$(jq -nc --arg path "${text_file}" '{"input":$path,"page":3,"page_size":1}')
output_page_3=$(tool_file_read)
jq -e '.page == 3 and .total_pages == 3 and (.content_markdown | contains("_Page 3 of 3_") and contains("```text\nij\n```"))' <<<"${output_page_3}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
