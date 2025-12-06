#!/usr/bin/env bash
# shellcheck shell=bash
#
# Read the contents of an Apple Note by title.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/read.sh}/notes/read.sh"
#
# Environment variables:
#   TOOL_QUERY (string): title of the note to read.
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
# shellcheck source=../../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/read.sh}/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/read.sh}/common.sh"

tool_notes_read() {
	local title folder_script
	title=${TOOL_QUERY:-""}

	if ! notes_require_platform; then
		return 0
	fi

	if [[ -z "${title//[[:space:]]/}" ]]; then
		log "ERROR" "Note title is required to read a note" "" || true
		return 0
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
	register_tool \
		"notes_read" \
		"Read an Apple Note's content by title." \
		"osascript -e 'get body of note \"<title>\"'" \
		"Requires macOS Apple Notes access; read-only." \
		tool_notes_read
}
