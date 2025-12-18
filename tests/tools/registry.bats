#!/usr/bin/env bats

@test "register_tool enforces required arguments" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/registry.sh
register_tool alpha "describe" "cmd" "safe"
SCRIPT

	[ "$status" -eq 1 ]
}

@test "register_tool captures descriptors and handlers" {
run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/registry.sh
init_tool_registry
register_tool alpha "describe" "cmd" "safe" handler_alpha '{"type":"object"}'
first_name=$(tool_names | head -n 1)
printf "%s\n" "${first_name}" "$(tool_description alpha)" "$(tool_command alpha)" "$(tool_safety alpha)" "$(tool_handler alpha)" "$(tool_args_schema alpha)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "alpha" ]
	[ "${lines[1]}" = "describe" ]
	[ "${lines[2]}" = "cmd" ]
	[ "${lines[3]}" = "safe" ]
	[ "${lines[4]}" = "handler_alpha" ]
	[ "${lines[5]}" = '{"type":"object"}' ]
}
