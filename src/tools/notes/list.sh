#!/usr/bin/env bash
# shellcheck shell=bash
#
# List Apple Notes titles within the configured folder.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/list.sh}/notes/list.sh"
#
# Environment variables:
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
source "${BASH_SOURCE[0]%/notes/list.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/list.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/list.sh}/common.sh"

derive_notes_list_query() {
	# Arguments:
	#   $1 - user query (string)
	printf '%s\n' "$1"
}

tool_notes_list() {
	local folder_script
	if ! notes_require_platform; then
		return 0
	fi

	folder_script="$(notes_resolve_folder_script)"

	log "INFO" "Listing Apple Notes" "$(notes_folder_name)"
	notes_run_script <<APPLESCRIPT
on run argv
        tell application "Notes"
${folder_script}
                set titles to {}
                repeat with candidate in every note of targetFolder
                        copy (name of candidate) to end of titles
                end repeat
                set AppleScript's text item delimiters to "\n"
                return titles as string
        end tell
end run
APPLESCRIPT
}

register_notes_list() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","properties":{},"additionalProperties":false}
JSON
	)
	register_tool \
		"notes_list" \
		"List note titles from the configured Apple Notes folder." \
		"notes_list (no arguments; returns one title per line)" \
		"Requires macOS Apple Notes access; read-only." \
		tool_notes_list \
		"${args_schema}"
}
