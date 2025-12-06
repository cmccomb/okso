#!/usr/bin/env bash
# shellcheck shell=bash
#
# Notes tool that appends reminders under the configured notes directory.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/notes.sh}/tools/notes.sh"
#
# Environment variables:
#   TOOL_QUERY (string): text to persist.
#   NOTES_DIR (string): directory for note storage; default set by caller.
#
# Dependencies:
#   - bash 5+
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes.sh}/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/notes.sh}/registry.sh"

tool_notes() {
	local query note_file
	query=${TOOL_QUERY:-""}
	note_file="${NOTES_DIR}/notes.txt"
	log "INFO" "Appending reminder" "${query}"
	printf '%s\t%s\n' "$(date -Iseconds)" "${query}" >>"${note_file}"
	printf 'Saved note to %s\n' "${note_file}"
}

register_notes() {
	register_tool \
		"notes" \
		"Persist reminders or notes under ~/.do for future runs." \
		"printf '<note>' >> ~/.do/notes.txt" \
		"Stores user-provided text locally; confirm contents." \
		tool_notes
}
