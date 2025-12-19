#!/usr/bin/env bash
# shellcheck shell=bash
#
# Search Apple Calendar events by title or location.
#
# Usage:
#   source "${BASH_SOURCE[0]%/calendar/search.sh}/calendar/search.sh"
#
# Environment variables:
#   TOOL_ARGS (json): structured args including `input`.
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
source "${BASH_SOURCE[0]%/calendar/search.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/calendar/search.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/search.sh}/common.sh"

calendar_search_dry_run_guard() {
	local query
	query="$1"
	if [[ "${DRY_RUN}" == true ]]; then
		log "INFO" "Dry run: skipping Apple Calendar search" "${query}" || true
		return 0
	fi

	return 1
}

tool_calendar_search() {
	local query calendar_script args_json text_key
	args_json="${TOOL_ARGS:-}" || true
	text_key="$(canonical_text_arg_key)"
	query=""

	query=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>/dev/null || true)

	if calendar_search_dry_run_guard "${query}"; then
		return 0
	fi

	if ! calendar_require_platform "${query}"; then
		return 0
	fi

	if [[ -z "${query//[[:space:]]/}" ]]; then
		log "ERROR" "Search term is required" "${args_json}" || true
		return 1
	fi

	calendar_script="$(calendar_resolve_calendar_script)"

	log "INFO" "Searching Apple Calendar" "${query}"
	calendar_run_script "${query}" <<APPLESCRIPT
on run argv
        set searchTerm to item 1 of argv
        tell application "Calendar"
${calendar_script}
                set matches to {}
                repeat with candidate in every event of targetCalendar
                        if (summary of candidate contains searchTerm) or (location of candidate contains searchTerm) then
                                set end of matches to (summary of candidate)
                        end if
                end repeat
                set AppleScript's text item delimiters to "\n"
                return matches as string
        end tell
end run
APPLESCRIPT
}

register_calendar_search() {
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"calendar_search" \
		"Search Apple Calendar events by title or location." \
		"calendar_search '<query>'" \
		"Requires macOS Calendar access; read-only." \
		tool_calendar_search \
		"${args_schema}"
}
