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
#   NOTES_FOLDER (string): target folder within Apple Notes.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 3.2+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - notes helpers from notes/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/notes/search.sh}/registry.sh"
# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/notes/search.sh}/lib/core/logging.sh"
# shellcheck source=src/lib/tools/args.sh
source "${BASH_SOURCE[0]%/tools/notes/search.sh}/lib/tools/args.sh"
# shellcheck source=src/tools/notes/common.sh
source "${BASH_SOURCE[0]%/search.sh}/common.sh"

derive_notes_search_query() {
	# Arguments:
	#   $1 - user query (string)
	printf '%s\n' "$1"
}

tool_notes_search() {
	local query folder_script
	query=""

	query="$(tool_args_parse_strict_single_string "input" "" "notes_search" || true)"

	if [[ -z "${query//[[:space:]]/}" ]]; then
		log "ERROR" "Search term is required" "${TOOL_ARGS:-{}}" || true
		return 1
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
		"notes_search" \
		"Search Apple Notes by title or body." \
		tool_notes_search \
		"${args_schema}"
}
