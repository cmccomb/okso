#!/usr/bin/env bats
#
# Focused tests for Apple Calendar tool helpers.
#
# Usage: bats tests/test_calendar.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "calendar tools warn when run off macOS" {
        run bash -lc 'source ./src/tools/calendar/index.sh; IS_MACOS=false; VERBOSITY=1; TOOL_QUERY=$'"'"'Title\nTomorrow'"'"'; tool_calendar_create'
        [ "$status" -eq 0 ]
        [[ "$output" == *"Apple Calendar is only available on macOS"* ]]
}

@test "calendar_create passes fields to osascript" {
        run bash -lc '
                export CALENDAR_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
                export CALENDAR_STUB_LOG="$(mktemp)"
                export IS_MACOS=true
                export VERBOSITY=0
                TOOL_QUERY=$'"'"'Team Sync\n2024-06-02 10:00\nHQ'"'"'
                source ./src/tools/calendar/index.sh
                tool_calendar_create
                cat "${CALENDAR_STUB_LOG}"
        '
        [ "$status" -eq 0 ]
        [[ "$output" == *"ARGS: - Team\ Sync 2024-06-02\ 10:00 HQ"* ]]
        [[ "$output" == *"make new event"* ]]
}

@test "calendar_list warns when osascript is unavailable" {
        run bash -lc '
                export CALENDAR_OSASCRIPT_BIN="missing-binary"
                export IS_MACOS=true
                export VERBOSITY=1
                source ./src/tools/calendar/index.sh
                tool_calendar_list
        '
        [ "$status" -eq 0 ]
        [[ "$output" == *"osascript missing; cannot reach Apple Calendar"* ]]
}

@test "calendar_search skips execution during dry run" {
        run bash -lc '
                export CALENDAR_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
                export CALENDAR_STUB_LOG="$(mktemp)"
                export IS_MACOS=true
                export DRY_RUN=true
                export VERBOSITY=1
                TOOL_QUERY="Planning"
                source ./src/tools/calendar/index.sh
                tool_calendar_search
                if [[ -f "${CALENDAR_STUB_LOG}" ]]; then
                        cat "${CALENDAR_STUB_LOG}"
                fi
        '
        [ "$status" -eq 0 ]
        [[ "$output" == *"Dry run: skipping Apple Calendar search"* ]]
}
