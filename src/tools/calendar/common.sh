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
#   - bash 5+
#   - osascript (optional; required on macOS)
#   - logging helpers from logging.sh
#   - osascript helpers from osascript_helpers.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero on misuse.

# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/calendar/common.sh}/lib/core/logging.sh"
# shellcheck source=../osascript_helpers.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/calendar/common.sh}/tools/osascript_helpers.sh"

calendar_name() {
	# Prints the resolved Apple Calendar name.
	local name
	name=${CALENDAR_NAME:-"Calendar"}
	printf '%s' "${name}"
}

calendar_require_platform() {
	# Ensures Apple Calendar tools only run on macOS with osascript available.
	if [[ "${IS_MACOS}" != true ]]; then
		log "WARN" "Apple Calendar is only available on macOS" "${TOOL_QUERY:-}" || true
		return 1
	fi

	if ! command -v "${CALENDAR_OSASCRIPT_BIN:-osascript}" >/dev/null 2>&1; then
		log "WARN" "osascript missing; cannot reach Apple Calendar" "${TOOL_QUERY:-}" || true
		return 1
	fi

	return 0
}

calendar_extract_event_fields() {
	# Splits TOOL_QUERY into title, start time, and optional location.
	# Emits three NUL-delimited fields: title, start time, location.
	local query title start_time location rest
	query=${TOOL_QUERY:-""}

	if [[ -z "${query//[[:space:]]/}" ]]; then
		log "ERROR" "Event title and time are required" "" || true
		return 1
	fi

	title=${query%%$'\n'*}
	rest=${query#"${title}"}
	rest=${rest#$'\n'}
	start_time=${rest%%$'\n'*}
	location=${rest#"${start_time}"}
	location=${location#$'\n'}

	if [[ -z "${title//[[:space:]]/}" || -z "${start_time//[[:space:]]/}" ]]; then
		log "ERROR" "Event title and time are required" "${query}" || true
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
