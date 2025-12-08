#!/usr/bin/env bats
#
# Tests for the shared tool registry utilities.
#
# Usage:
#   bats tests/test_tools_registry.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert registry behavior.

@test "register_tool enforces required arguments" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/tools/registry.sh; register_tool alpha "describe" "cmd" "safe"'
	[ "$status" -eq 1 ]
}

@test "init_tool_registry resets shared arrays" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/tools/registry.sh; register_tool alpha "describe" "cmd" "safe" handler_alpha; register_tool beta "describe" "cmd" "safe" handler_beta; init_tool_registry; [[ ${#TOOLS[@]} -eq 0 ]]; [[ -z "${TOOL_HANDLER[alpha]:-}" ]]'
	[ "$status" -eq 0 ]
}

@test "register_tool captures handler and descriptors" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/tools/registry.sh; init_tool_registry; register_tool alpha "describe" "cmd" "safe" handler_alpha; [[ "${TOOL_DESCRIPTION[alpha]}" == "describe" ]]; [[ "${TOOL_COMMAND[alpha]}" == "cmd" ]]; [[ "${TOOL_SAFETY[alpha]}" == "safe" ]]; [[ "${TOOL_HANDLER[alpha]}" == "handler_alpha" ]]'
	[ "$status" -eq 0 ]
}
