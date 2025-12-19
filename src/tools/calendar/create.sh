#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create a new Apple Calendar event using TOOL_QUERY lines for details.
#
# Usage:
#   source "${BASH_SOURCE[0]%/calendar/create.sh}/calendar/create.sh"
#
# Environment variables:
#   TOOL_QUERY (string): event details; first line = title, second = start time, optional third = location.
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
source "${BASH_SOURCE[0]%/calendar/create.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/calendar/create.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/create.sh}/common.sh"

calendar_dry_run_guard() {
	if [[ "${DRY_RUN}" == true ]]; then
		log "INFO" "Dry run: skipping Apple Calendar event creation" "${TOOL_QUERY:-}" || true
		return 0
	fi

	return 1
}

tool_calendar_create() {
	local title start_time location calendar_script

	if calendar_dry_run_guard; then
		return 0
	fi

	if ! calendar_require_platform; then
		return 0
	fi

	if ! { IFS= read -r -d '' title && IFS= read -r -d '' start_time && IFS= read -r -d '' location; } < <(calendar_extract_event_fields); then
		return 0
	fi

	calendar_script="$(calendar_resolve_calendar_script)"

	log "INFO" "Creating Apple Calendar event" "${title}"
	calendar_run_script "${title}" "${start_time}" "${location}" <<APPLESCRIPT
on run argv
        set eventTitle to item 1 of argv
        set eventStart to item 2 of argv
        set eventLocation to item 3 of argv
        tell application "Calendar"
${calendar_script}
                set startDate to date eventStart
                set newEvent to make new event at end of events of targetCalendar with properties {summary:eventTitle, start date:startDate}
                if eventLocation is not "" then
                        set location of newEvent to eventLocation
                end if
                return summary of newEvent
        end tell
end run
APPLESCRIPT
}

register_calendar_create() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["details"],"properties":{"details":{"type":"string","minLength":1}},"additionalProperties":false}
JSON
	)
	register_tool \
		"calendar_create" \
		"Create a new Apple Calendar event (line 1: title; line 2: start time)." \
		"calendar_create 'Title\\nStart time'" \
		"Requires macOS Calendar access; event details are sent to Calendar." \
		tool_calendar_create \
		"${args_schema}"
}
