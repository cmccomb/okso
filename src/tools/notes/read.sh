#!/usr/bin/env bash
# shellcheck shell=bash
#
# Read the contents of an Apple Note by title.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/read.sh}/notes/read.sh"
#
# Environment variables:
#   TOOL_ARGS (json): {"input": string} using the canonical text key for the note title.
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
source "${BASH_SOURCE[0]%/notes/read.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/read.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/read.sh}/common.sh"

derive_notes_read_query() {
	# Arguments:
	#   $1 - user query (string)
	printf '%s\n' "$1"
}

tool_notes_read() {
	local title folder_script text_key
	text_key="$(canonical_text_arg_key)"
	title=$(jq -er --arg key "${text_key}" 'if type == "object" then .[$key] // .title // empty else empty end' <<<"${TOOL_ARGS:-{}}" 2>/dev/null || true)

	if ! notes_require_platform; then
		return 0
	fi

	if [[ -z "${title//[[:space:]]/}" ]]; then
		log "ERROR" "Note title is required to read a note" "" || true
		return 1
	fi

	folder_script="$(notes_resolve_folder_script)"

	log "INFO" "Reading Apple Note" "${title}"
	notes_run_script "${title}" <<APPLESCRIPT
on run argv
        set noteTitle to item 1 of argv
        tell application "Notes"
${folder_script}
                set matches to every note of targetFolder whose name is noteTitle
                if (count of matches) is 0 then
                        error "Note not found: " & noteTitle
                end if
                set targetNote to item 1 of matches
                set noteBody to body of targetNote
                return noteTitle & "\n" & noteBody
        end tell
end run
APPLESCRIPT
}

register_notes_read() {
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"notes_read" \
		"Read an Apple Note's content by title." \
		"notes_read 'Title' (returns the title and body separated by a newline)" \
		"Requires macOS Apple Notes access; read-only." \
		tool_notes_read \
		"${args_schema}"
}
