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
        run bash -lc 'source ./src/tools/notes/index.sh; IS_MACOS=false; VERBOSITY=1; TOOL_ARGS="{\"title\":\"Title\",\"body\":\"Body\"}"; tool_notes_create'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Apple Notes is only available on macOS"* ]]
}

@test "notes_create passes title and body to osascript" {
	run bash -lc '
                export NOTES_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
                export NOTES_STUB_LOG="$(mktemp)"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_ARGS='"'"'{"title":"Quick title","body":"First line\nSecond line"}'"'"'
                source ./src/tools/notes/index.sh
                tool_notes_create
                cat "${NOTES_STUB_LOG}"
        '
	[ "$status" -eq 0 ]
	[[ "$output" == *"ARGS: - Quick\\ title $'First line\\nSecond line'"* ]]
	[[ "$output" == *"Second line"* ]]
}

@test "notes tools validate missing title" {
        run bash -lc '
                export NOTES_OSASCRIPT_BIN="/bin/echo"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_ARGS="{}"
                source ./src/tools/notes/index.sh
                tool_notes_create
        '
        [ "$status" -eq 1 ]
}
