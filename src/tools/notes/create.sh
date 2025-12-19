#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create a new Apple Notes entry using structured title and body fields.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/create.sh}/notes/create.sh"
#
# Environment variables:
#   TOOL_ARGS (json): {"title": string, "body": string}
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
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/create.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/create.sh}/common.sh"

derive_notes_create_query() {
	# Arguments:
	#   $1 - user query (string)
	local user_query nocasematch_enabled
	user_query="$1"
	nocasematch_enabled=false

	if shopt -q nocasematch; then
		nocasematch_enabled=true
	fi
	shopt -s nocasematch

	if [[ "${user_query}" =~ note[[:space:]]+(.+) ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
		if [[ "${nocasematch_enabled}" == false ]]; then
			shopt -u nocasematch
		fi
		return
	fi

	if [[ "${nocasematch_enabled}" == false ]]; then
		shopt -u nocasematch
	fi

	printf '%s\n' "${user_query}"
}

tool_notes_create() {
	local title body folder_script

	if ! notes_require_platform; then
		return 0
	fi

	if ! { IFS= read -r -d '' title && IFS= read -r -d '' body; } < <(notes_extract_title_and_body); then
		return 1
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
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["title"],"properties":{"title":{"type":"string","minLength":1},"body":{"type":"string"}},"additionalProperties":false}
JSON
	)
	register_tool \
		"notes_create" \
		"Create a new Apple Note using structured fields." \
		"notes_create {\"title\":\"Title\",\"body\":\"Body text\"}" \
		"Requires macOS Apple Notes access; content is sent to Notes." \
		tool_notes_create \
		"${args_schema}"
}
