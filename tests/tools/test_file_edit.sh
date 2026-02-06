#!/usr/bin/env bats
#
# Tests for file_edit tool behavior.
#
# Usage:
#   bats tests/tools/test_file_edit.sh

setup() {
	export TOOL_ARGS=''
}

@test "file_edit replaces a single unambiguous match" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_edit.sh
target="$(mktemp -t file_edit.XXXXXX)"
printf 'hello world\n' >"${target}"
TOOL_ARGS=$(jq -nc --arg path "${target}" --arg old "world" --arg new "there" '{path:$path, old_text:$old, new_text:$new}')
output=$(tool_file_edit)
jq -e '.replacements == 1 and .total_matches == 1' <<<"${output}" >/dev/null
[[ "$(cat "${target}")" == "hello there" ]]
SCRIPT

	[ "$status" -eq 0 ]
}

@test "file_edit rejects ambiguous replacements without controls" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_edit.sh
target="$(mktemp -t file_edit.XXXXXX)"
printf 'alpha beta alpha' >"${target}"
TOOL_ARGS=$(jq -nc --arg path "${target}" --arg old "alpha" --arg new "zeta" '{path:$path, old_text:$old, new_text:$new}')
tool_file_edit
SCRIPT

	[ "$status" -ne 0 ]
}

@test "file_edit replace_all updates every match" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_edit.sh
target="$(mktemp -t file_edit.XXXXXX)"
printf 'red blue red' >"${target}"
TOOL_ARGS=$(jq -nc --arg path "${target}" --arg old "red" --arg new "green" '{path:$path, old_text:$old, new_text:$new, replace_all:true}')
output=$(tool_file_edit)
jq -e '.replacements == 2 and .total_matches == 2' <<<"${output}" >/dev/null
[[ "$(cat "${target}")" == "green blue green" ]]
SCRIPT

	[ "$status" -eq 0 ]
}
