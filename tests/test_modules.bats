#!/usr/bin/env bats
#
# Focused unit tests for shared Bash modules.
#
# Usage: bats tests/test_modules.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "parse_model_spec falls back to default file" {
	run bash -lc 'source ./src/config.sh; parts=(); mapfile -t parts < <(parse_model_spec "example/repo" "fallback.gguf"); echo "${parts[0]}"; echo "${parts[1]}"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "example/repo" ]
	[ "${lines[1]}" = "fallback.gguf" ]
}

@test "init_tool_registry clears previous tools" {
	run bash -lc 'source ./src/tools.sh; TOOLS=(stub); TOOL_DESCRIPTION=( [stub]="desc"); init_tool_registry; echo "${#TOOLS[@]}"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 0 ]
}

@test "initialize_tools registers each module" {
	run bash -lc 'source ./src/tools.sh; init_tool_registry; initialize_tools; printf "%s\n" "${TOOLS[@]}"'
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 5 ]
	[ "${lines[0]}" = "os_nav" ]
	[ "${lines[1]}" = "file_search" ]
	[ "${lines[2]}" = "notes" ]
	[ "${lines[3]}" = "mail_stub" ]
	[ "${lines[4]}" = "applescript" ]
}

@test "json_escape preserves newlines and quotes" {
	run bash -lc "source ./src/logging.sh; json_escape $'quote\nline'"
	[ "$status" -eq 0 ]
	[ "${output}" = "quote\\nline" ]
}
