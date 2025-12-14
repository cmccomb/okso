#!/usr/bin/env bats
#
# Focused tests for Apple Reminders tool helpers.
#
# Usage: bats tests/tools/test_reminders.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "reminders tools warn when run off macOS" {
        run bash -lc 'source ./src/tools/reminders/index.sh; IS_MACOS=false; VERBOSITY=1; TOOL_ARGS="{\"title\":\"Title\",\"notes\":\"Body\"}"; tool_reminders_create'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Apple Reminders is only available on macOS"* ]]
}

@test "reminders_create passes title and body to osascript" {
	run bash -lc '
                export REMINDERS_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
                export REMINDERS_STUB_LOG="$(mktemp)"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_ARGS='"'"'{"title":"Quick reminder","notes":"Body text","time":""}'"'"'
                source ./src/tools/reminders/index.sh
                tool_reminders_create
                cat "${REMINDERS_STUB_LOG}"
        '
	[ "$status" -eq 0 ]
	[[ "$output" == *"ARGS: - Quick\ reminder Body\ text"* ]]
	[[ "$output" == *"make new reminder"* ]]
}

@test "reminders_complete sends completion AppleScript" {
	run bash -lc '
                export REMINDERS_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
                export REMINDERS_STUB_LOG="$(mktemp)"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_ARGS='"'"'{"title":"Finish errands"}'"'"'
                source ./src/tools/reminders/index.sh
                tool_reminders_complete
                cat "${REMINDERS_STUB_LOG}"
        '
	[ "$status" -eq 0 ]
	[[ "$output" == *"ARGS: - Finish\ errands"* ]]
	[[ "$output" == *"set completed of r to true"* ]]
}

@test "reminders tools validate missing title" {
        run bash -lc '
                export REMINDERS_OSASCRIPT_BIN="/bin/echo"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_ARGS="{}"
                source ./src/tools/reminders/index.sh
                tool_reminders_create
        '
        [ "$status" -eq 1 ]
}
