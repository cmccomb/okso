#!/usr/bin/env bats
#
# Focused tests for Apple Notes tool helpers.
#
# Usage: bats tests/tools/test_notes.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "notes tools warn when run off macOS" {
	run bash -lc 'source ./src/tools/notes/index.sh; IS_MACOS=false; VERBOSITY=1; TOOL_QUERY=$'"'"'Title
Body'"'"'; tool_notes_create'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Apple Notes is only available on macOS"* ]]
}

@test "notes_create passes title and body to osascript" {
	run bash -lc '
                export NOTES_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
                export NOTES_STUB_LOG="$(mktemp)"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_QUERY=$'"'"'Quick title
First line
Second line'"'"'
                source ./src/tools/notes/index.sh
                tool_notes_create
                cat "${NOTES_STUB_LOG}"
        '
	[ "$status" -eq 0 ]
	[[ "$output" == *"ARGS: - Quick\\ title $'First line\\nSecond line'"* ]]
	[[ "$output" == *"Second line"* ]]
}
