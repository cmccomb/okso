#!/usr/bin/env bash
# shellcheck shell=bash
#
# Search Apple Notes by title or body for a query string.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/search.sh}/notes/search.sh"
#
# Environment variables:
#   TOOL_ARGS (json): structured args including `input`.
#   TOOL_QUERY (string): legacy search phrase fallback when TOOL_ARGS is absent.
#   NOTES_FOLDER (string): target folder within Apple Notes.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 5+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - notes helpers from notes/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/notes/search.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/search.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/search.sh}/common.sh"

derive_notes_search_query() {
	# Arguments:
	#   $1 - user query (string)
	printf '%s\n' "$1"
}

tool_notes_search() {
	local query folder_script args_json text_key
	args_json="${TOOL_ARGS:-}" || true
	text_key="$(canonical_text_arg_key)"
	query="${TOOL_QUERY:-}" || true

	if [[ -n "${args_json}" ]]; then
		query=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>/dev/null || true)
	fi

	if ! notes_require_platform; then
		return 0
	fi

	if [[ -z "${query//[[:space:]]/}" ]]; then
		log "ERROR" "Search term is required" "" || true
		return 0
	fi

	folder_script="$(notes_resolve_folder_script)"

	log "INFO" "Searching Apple Notes" "${query}"
	notes_run_script "${query}" <<APPLESCRIPT
on run argv
        set searchTerm to item 1 of argv
        tell application "Notes"
${folder_script}
                set matches to {}
                repeat with candidate in every note of targetFolder
                        if (name of candidate contains searchTerm) or (body of candidate contains searchTerm) then
                                copy (name of candidate) to end of matches
                        end if
                end repeat
                set AppleScript's text item delimiters to "\n"
                return matches as string
        end tell
end run
APPLESCRIPT
}

register_notes_search() {
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"notes_search" \
		"Search Apple Notes by title or body." \
		"notes_search '<query>'" \
		"Requires macOS Notes access; read-only." \
		tool_notes_search \
		"${args_schema}"
}
