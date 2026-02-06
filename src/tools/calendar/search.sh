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
#   - bash 3.2+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - calendar helpers from calendar/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/calendar/search.sh}/registry.sh"
# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/calendar/search.sh}/lib/core/logging.sh"
# shellcheck source=src/lib/tools/args.sh
source "${BASH_SOURCE[0]%/tools/calendar/search.sh}/lib/tools/args.sh"
# shellcheck source=src/tools/calendar/common.sh
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
	local query calendar_script
	query=""

	query="$(tool_args_parse_strict_single_string "input" "" "calendar_search" || true)"

	if calendar_search_dry_run_guard "${query}"; then
		return 0
	fi

	if [[ -z "${query//[[:space:]]/}" ]]; then
		log "ERROR" "Search term is required" "${TOOL_ARGS:-{}}" || true
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

	args_schema=$(
		cat <<'JSON'
{
  "type": "object",
  "required": ["input"],
  "properties": {
    "input": {
      "type": "string",
      "minLength": 1
    }
  }
}
JSON
	)
	register_tool \
		"calendar_search" \
		"Search Apple Calendar events by title or location." \
		tool_calendar_search \
		"${args_schema}"
}
