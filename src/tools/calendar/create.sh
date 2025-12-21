#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create a new Apple Calendar event using structured TOOL_ARGS details.
#
# Usage:
#   source "${BASH_SOURCE[0]%/calendar/create.sh}/calendar/create.sh"
#
# Environment variables:
#   TOOL_ARGS (json): structured args including `input` with event details (title, start time, optional location lines).
#   CALENDAR_NAME (string): target calendar name.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   DRY_RUN (bool): when true, logs intent without executing AppleScript.
#
# Dependencies:
#   - bash 3.2+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - calendar helpers from calendar/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero when input validation fails or registration is misused.

# shellcheck source=../registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/calendar/create.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/calendar/create.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/create.sh}/common.sh"

calendar_dry_run_guard() {
	local details
	details="$1"
	if [[ "${DRY_RUN}" == true ]]; then
		log "INFO" "Dry run: skipping Apple Calendar event creation" "${details}" || true
		return 0
	fi

	return 1
}

tool_calendar_create() {
	local title start_time location calendar_script args_json text_key details
	args_json="${TOOL_ARGS:-}" || true
	text_key="$(canonical_text_arg_key)"
	details=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>/dev/null || true)

	if [[ -z "${details}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.${text_key}" "${args_json}" || true
		return 1
	fi

	if calendar_dry_run_guard "${details}"; then
		return 0
	fi

	if ! calendar_require_platform "${details}"; then
		return 0
	fi

	if ! { IFS= read -r -d '' title && IFS= read -r -d '' start_time && IFS= read -r -d '' location; } < <(calendar_extract_event_fields "${details}"); then
		return 1
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

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"calendar_create" \
		"Create a new Apple Calendar event (line 1: title; line 2: start time)." \
		"calendar_create 'Title\\nStart time'" \
		"Requires macOS Calendar access; event details are sent to Calendar." \
		tool_calendar_create \
		"${args_schema}"
}
