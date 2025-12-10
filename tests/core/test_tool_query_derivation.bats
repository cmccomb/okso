#!/usr/bin/env bats
#
# Tests for tool-specific query derivation dispatch.
#
# Usage:
#   bats tests/core/test_tool_query_derivation.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "terminal derivation maps to helper function" {
	run bash -lc 'source ./src/lib/planner.sh; VERBOSITY=0; derive_tool_query "terminal" "please list files"'
	[ "$status" -eq 0 ]
	[[ "$output" == "ls -la" ]]
}

@test "reminders derivation trims leading phrase" {
	run bash -lc 'source ./src/lib/planner.sh; VERBOSITY=0; derive_tool_query "reminders_create" "Remind me to call mom"'
	[ "$status" -eq 0 ]
	[[ "$output" == "call mom" ]]
}

@test "default derivation echoes unknown tool queries" {
	run bash -lc 'source ./src/lib/planner.sh; VERBOSITY=0; derive_tool_query "unregistered_tool" "raw query"'
	[ "$status" -eq 0 ]
	[[ "$output" == "raw query" ]]
}

@test "notes derivation strips leading keyword" {
	run bash -lc 'source ./src/lib/planner.sh; VERBOSITY=0; derive_tool_query "notes_create" "note meeting notes"'
	[ "$status" -eq 0 ]
	[[ "$output" == "meeting notes" ]]
}
