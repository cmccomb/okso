#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create a new Apple Notes entry using the first query line as the title.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/create.sh}/notes/create.sh"
#
# Environment variables:
#   TOOL_QUERY (string): note content; first line becomes the title.
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
source "${BASH_SOURCE[0]%/notes/create.sh}/registry.sh"
# shellcheck source=../../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/create.sh}/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/create.sh}/common.sh"

tool_notes_create() {
	local title body folder_script

	if ! notes_require_platform; then
		return 0
	fi

	if ! { IFS= read -r -d '' title && IFS= read -r -d '' body; } < <(notes_extract_title_and_body); then
		return 0
	fi

	folder_script="$(notes_resolve_folder_script)"

	log "INFO" "Creating Apple Note" "${title}"
	notes_run_script "${title}" "${body}" <<APPLESCRIPT
on run argv
        set noteTitle to item 1 of argv
        set noteBody to item 2 of argv
        tell application "Notes"
${folder_script}
                set newNote to make new note at targetFolder with properties {name:noteTitle, body:noteBody}
                return name of newNote
        end tell
end run
APPLESCRIPT
}

register_notes_create() {
	register_tool \
		"notes_create" \
		"Create a new Apple Note using the first line as the title." \
		"osascript -e 'make new note with {name:<title>, body:<body>}'" \
		"Requires macOS Apple Notes access; content is sent to Notes." \
		tool_notes_create
}
