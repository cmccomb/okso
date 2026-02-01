#!/usr/bin/env bats
#
# Tests for tool registration and metadata discovery.
#
# Usage:
#   bats tests/tools/test_registry.sh

@test "register_tool enforces required arguments" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/registry.sh
register_tool alpha "describe"
SCRIPT

	[ "$status" -eq 1 ]
}

@test "register_tool captures descriptors and handlers" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/registry.sh
init_tool_registry
register_tool alpha "describe" handler_alpha '{"type":"object"}'
names=()
while IFS= read -r line; do
        names+=("$line")
done < <(tool_names)
printf "%s\n" "${names[0]}" "$(tool_description alpha)" "$(tool_handler alpha)" "$(tool_args_schema alpha)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "alpha" ]
	[ "${lines[1]}" = "describe" ]
	[ "${lines[2]}" = "handler_alpha" ]
	[ "${lines[3]}" = '{"type":"object"}' ]
}

@test "register_tool rejects legacy single-string keys" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/registry.sh
init_tool_registry
register_tool alpha "describe" handler_alpha '{"type":"object","required":["message"],"properties":{"message":{"type":"string"}},"additionalProperties":false}'
SCRIPT

	[ "$status" -eq 1 ]
}
