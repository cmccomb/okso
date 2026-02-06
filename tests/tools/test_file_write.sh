#!/usr/bin/env bats
#
# Tests for file_write tool behavior.
#
# Usage:
#   bats tests/tools/test_file_write.sh

setup() {
	export TOOL_ARGS=''
}

@test "file_write creates files with parent directory creation enabled" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_write.sh
tmpdir="$(mktemp -d)"
target="${tmpdir}/nested/output.txt"
TOOL_ARGS=$(jq -nc --arg path "${target}" --arg content "hello" '{path:$path, content:$content, mode:"create", create_parents:true}')
output=$(tool_file_write)
jq -e '.created == true and .mode == "create" and .bytes_written == 5' <<<"${output}" >/dev/null
[[ "$(cat "${target}")" == "hello" ]]
SCRIPT

	[ "$status" -eq 0 ]
}

@test "file_write append mode appends text to existing files" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_write.sh
target="$(mktemp -t file_write.XXXXXX)"
printf 'alpha\n' >"${target}"
TOOL_ARGS=$(jq -nc --arg path "${target}" --arg content $'beta\n' '{path:$path, content:$content, mode:"append"}')
output=$(tool_file_write)
jq -e '.created == false and .mode == "append"' <<<"${output}" >/dev/null
expected="$(mktemp -t file_write_expected.XXXXXX)"
printf 'alpha\nbeta\n' >"${expected}"
cmp -s "${expected}" "${target}"
SCRIPT

	[ "$status" -eq 0 ]
}

@test "file_write create mode rejects existing files" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_write.sh
target="$(mktemp -t file_write.XXXXXX)"
printf 'exists' >"${target}"
TOOL_ARGS=$(jq -nc --arg path "${target}" --arg content "new" '{path:$path, content:$content, mode:"create"}')
tool_file_write
SCRIPT

	[ "$status" -ne 0 ]
}
