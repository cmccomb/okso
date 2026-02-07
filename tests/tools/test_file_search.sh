#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for file_search tool behavior.
#
# Usage:
#   bats tests/tools/test_file_search.sh

setup() {
	export TOOL_ARGS=''
}

@test "file_search rejects globbing inputs" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/files/file_search.sh
TOOL_ARGS='{"query":"needle","paths":["."],"glob":"*.md"}'
file_search_parse_args
SCRIPT

	[ "$status" -ne 0 ]
}

@test "file_search returns structured matches" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/rga" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"--glob"* ]]; then
  exit 2
fi
cat <<'JSON'
{"type":"match","data":{"path":{"text":"sample.txt"},"line_number":3,"lines":{"text":"needle here\n"}}}
JSON
MOCK
chmod +x "${mock_bin}/rga"
export PATH="${mock_bin}:$PATH"
source ./src/tools/files/file_search.sh
TOOL_ARGS='{"query":"needle","paths":["."],"max_results":5,"context_lines":0,"case_sensitive":true}'
output=$(tool_file_search)
match_count=$(jq -r '.matches | length' <<<"${output}")
result_path=$(jq -r '.result_path' <<<"${output}")
[[ "${match_count}" == "1" ]]
[[ -f "${result_path}" ]]
SCRIPT

	[ "$status" -eq 0 ]
}

@test "initialize_tools registers file_search through the file suite" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/tool_runtime/index.sh
init_tool_registry
initialize_tools
tool_names
SCRIPT

	[ "$status" -eq 0 ]
	[[ " ${lines[*]} " == *" file_search "* ]]
	[[ " ${lines[*]} " == *" file_read "* ]]
	[[ " ${lines[*]} " == *" file_write "* ]]
	[[ " ${lines[*]} " == *" file_edit "* ]]
}
