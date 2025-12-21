#!/usr/bin/env bats
#
# Focused tests for Apple Calendar create tool helpers.
#
# Usage: bats tests/tools/test_calendar_create.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "calendar_create fails when details omit start time" {
	run bash -lc '
                export CALENDAR_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_ARGS='"'"'{"input":"Title only"}'"'"'
                source ./src/tools/calendar/create.sh
                tool_calendar_create
        '

	[ "$status" -eq 1 ]
	[[ "$output" == *"Event title and time are required"* ]]
}
