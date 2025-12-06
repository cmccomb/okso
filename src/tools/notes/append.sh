#!/usr/bin/env bash
# shellcheck shell=bash
#
# Append text to an existing Apple Note identified by title.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/append.sh}/notes/append.sh"
#
# Environment variables:
#   TOOL_QUERY (string): first line is the note title; remaining lines are appended.
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
source "${BASH_SOURCE[0]%/notes/append.sh}/registry.sh"
# shellcheck source=../../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/append.sh}/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/append.sh}/common.sh"

tool_notes_append() {
	local title body folder_script

	if ! notes_require_platform; then
		return 0
	fi

	if ! { IFS= read -r -d '' title && IFS= read -r -d '' body; } < <(notes_extract_title_and_body); then
		return 0
	fi

	folder_script="$(notes_resolve_folder_script)"

	log "INFO" "Appending to Apple Note" "${title}"
	notes_run_script "${title}" "${body}" <<APPLESCRIPT
on run argv
        set noteTitle to item 1 of argv
        set noteBody to item 2 of argv
        tell application "Notes"
${folder_script}
                set matches to every note of targetFolder whose name is noteTitle
                if (count of matches) is 0 then
                        error "Note not found: " & noteTitle
                end if
                set targetNote to item 1 of matches
                set body of targetNote to (body of targetNote) & "\n\n" & noteBody
                return name of targetNote
        end tell
end run
APPLESCRIPT
}

register_notes_append() {
	register_tool \
		"notes_append" \
		"Append text to an existing Apple Note matched by title." \
		"osascript -e 'set body of note \"<title>\" to body & \"<text>\"'" \
		"Requires macOS Apple Notes access; updates existing note content." \
		tool_notes_append
}
