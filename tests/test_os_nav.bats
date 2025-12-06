#!/usr/bin/env bats
#
# Focused tests for the os_nav tool's persistent terminal session.
#
# Usage: bats tests/test_os_nav.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "status default exposes allowed commands" {
	run bash -lc 'source ./src/tools/os_nav.sh; VERBOSITY=0; TOOL_QUERY=""; tool_os_nav'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == Session:* ]]
	[[ "${output}" == *"Allowed commands:"* ]]
}

@test "cd updates persistent working directory" {
	run bash -lc 'source ./src/tools/os_nav.sh; VERBOSITY=0; OS_NAV_WORKDIR="$(pwd)"; TOOL_QUERY="cd tests"; tool_os_nav; TOOL_QUERY="pwd"; tool_os_nav'
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == *"/tests" ]]
}

@test "unknown command falls back to status" {
	run bash -lc 'source ./src/tools/os_nav.sh; VERBOSITY=0; TOOL_QUERY="launch rockets"; tool_os_nav'
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Allowed commands:"* ]]
}
