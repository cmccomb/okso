#!/usr/bin/env bash
# shellcheck shell=bash
#
# List upcoming Apple Calendar events for the configured calendar.
#
# Usage:
#   source "${BASH_SOURCE[0]%/calendar/list.sh}/calendar/list.sh"
#
# Environment variables:
#   CALENDAR_NAME (string): target calendar name.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   DRY_RUN (bool): when true, logs intent without executing AppleScript.
#
# Dependencies:
#   - bash 5+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - calendar helpers from calendar/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/calendar/list.sh}/registry.sh"
# shellcheck source=../../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/calendar/list.sh}/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/list.sh}/common.sh"

calendar_list_dry_run_guard() {
        if [[ "${DRY_RUN}" == true ]]; then
                log "INFO" "Dry run: skipping Apple Calendar listing" "${TOOL_QUERY:-}" || true
                return 0
        fi

        return 1
}

tool_calendar_list() {
        local calendar_script

        if calendar_list_dry_run_guard; then
                return 0
        fi

        if ! calendar_require_platform; then
                return 0
        fi

        calendar_script="$(calendar_resolve_calendar_script)"

        log "INFO" "Listing upcoming Apple Calendar events" "$(calendar_name)"
        calendar_run_script <<APPLESCRIPT
on run
        tell application "Calendar"
${calendar_script}
                set nowDate to current date
                set upcoming to every event of targetCalendar whose start date >= nowDate
                set formattedEvents to {}
                repeat with ev in upcoming
                        set startDate to start date of ev
                        set endDate to end date of ev
                        set summaryText to summary of ev
                        set locationText to location of ev
                        set end of formattedEvents to (summaryText & " | " & (startDate as string) & " -> " & (endDate as string) & " @ " & locationText)
                end repeat
                set AppleScript's text item delimiters to "\n"
                return formattedEvents as string
        end tell
end run
APPLESCRIPT
}

register_calendar_list() {
        register_tool \
                "calendar_list" \
                "List upcoming Apple Calendar events from the configured calendar." \
                "osascript -e 'events of calendar <name> starting today'" \
                "Requires macOS Calendar access; read-only." \
                tool_calendar_list
}
