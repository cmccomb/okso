#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for Apple Calendar tool integrations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/calendar/common.sh}/calendar/common.sh"
#
# Environment variables:
#   CALENDAR_NAME (string): target calendar name; defaults to "Calendar".
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   CALENDAR_OSASCRIPT_BIN (string): override path for osascript; defaults to "osascript".
#   DRY_RUN (bool): when true, handlers should log intent without executing AppleScript.
#   VERBOSITY (int): logging verbosity; see logging.sh.
#
# Dependencies:
#   - bash 3.2+
#   - osascript (optional; required on macOS)
#   - logging helpers from logging.sh
#   - osascript helpers from osascript_helpers.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero on misuse.

# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/calendar/common.sh}/lib/core/logging.sh"
# shellcheck source=src/tools/osascript_helpers.sh
source "${BASH_SOURCE[0]%/tools/calendar/common.sh}/tools/osascript_helpers.sh"
# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/calendar/common.sh}/registry.sh"

calendar_name() {
	# Prints the resolved Apple Calendar name.
	local name
	name=${CALENDAR_NAME:-"Calendar"}
	printf '%s' "${name}"
}

calendar_resolve_query() {
	local text_key query
	text_key="$(canonical_text_arg_key)"
	query=$(jq -er --arg key "${text_key}" 'if type == "object" then .[$key] // empty else empty end' <<<"${TOOL_ARGS:-{}}" 2>/dev/null || true)

	if [[ -z "${query}" ]]; then
		query=${TOOL_QUERY:-""}
	fi

	printf '%s' "${query}"
}

calendar_extract_event_fields() {
	# Splits the provided details string into title, start time, and optional location.
	# Emits three NUL-delimited fields: title, start time, location.
	local details title start_time location rest
	details="$1"

	if [[ -z "${details//[[:space:]]/}" ]]; then
		log "ERROR" "Event title and time are required" "" || true
		return 1
	fi

	title=${details%%$'\n'*}
	rest=${details#"${title}"}
	rest=${rest#$'\n'}
	start_time=${rest%%$'\n'*}
	location=${rest#"${start_time}"}
	location=${location#$'\n'}

	if [[ -z "${title//[[:space:]]/}" || -z "${start_time//[[:space:]]/}" ]]; then
		log "ERROR" "Event title and time are required" "${details}" || true
		return 1
	fi

	printf '%s\0%s\0%s\0' "${title}" "${start_time}" "${location}"
}

calendar_run_script() {
	# Runs an AppleScript provided on stdin, passing through all arguments.
	# Arguments:
	#   $@ - parameters forwarded to osascript
	local bin
	bin=${CALENDAR_OSASCRIPT_BIN:-osascript}
	osascript_run_piped "${bin}" "$@"
}

calendar_resolve_calendar_script() {
	# Emits AppleScript lines that resolve the target calendar.
	local cal
	cal=$(calendar_name)
	cal=${cal//"/\\"/}
	printf '        if not (exists calendar "%s") then\n' "${cal}"
	printf '                error "Calendar not found: %s"\n' "${cal}"
	printf '        end if\n'
	printf '        set targetCalendar to calendar "%s"\n' "${cal}"
}
