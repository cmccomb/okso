#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for Apple Notes tool integrations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/common.sh}/notes/common.sh"
#
# Environment variables:
#   NOTES_FOLDER (string): target folder name; defaults to "Notes".
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   NOTES_OSASCRIPT_BIN (string): override path for osascript; defaults to "osascript".
#   VERBOSITY (int): logging verbosity; see logging.sh.
#
# Dependencies:
#   - bash 5+
#   - osascript (optional; required on macOS)
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero on misuse.

# shellcheck source=../../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/common.sh}/logging.sh"
# shellcheck source=../osascript_helpers.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/notes/common.sh}/tools/osascript_helpers.sh"

notes_folder_name() {
	# Prints the resolved Apple Notes folder name.
	local folder
	folder=${NOTES_FOLDER:-"Notes"}
	printf '%s' "${folder}"
}

notes_require_platform() {
	# Ensures Apple Notes tools only run on macOS with osascript available.
	if ! assert_osascript_available \
		"Apple Notes is only available on macOS" \
		"osascript missing; cannot reach Apple Notes" \
		"${NOTES_OSASCRIPT_BIN:-osascript}" \
		"${TOOL_QUERY:-}"; then
		return 1
	fi

	return 0
}

notes_extract_title_and_body() {
	# Splits TOOL_QUERY into a title (first line) and body (remaining lines).
	# Emits two lines to stdout: title then body.
	local query title body
	query=${TOOL_QUERY:-""}

	if [[ -z "${query//[[:space:]]/}" ]]; then
		log "ERROR" "Note content is required" "" || true
		return 1
	fi

	title=${query%%$'\n'*}
	body=${query#"${title}"}
	body=${body#$'\n'}

	if [[ -z "${title//[[:space:]]/}" ]]; then
		title="Untitled note $(date -Iseconds)"
	fi

	printf '%s\0%s\0' "${title}" "${body}"
}

notes_run_script() {
	# Runs an AppleScript provided on stdin, passing through all arguments.
	# Arguments:
	#   $@ - parameters forwarded to osascript
	local bin
	bin=${NOTES_OSASCRIPT_BIN:-osascript}
	osascript_run_piped "${bin}" "$@"
}

notes_resolve_folder_script() {
	# Emits AppleScript lines that resolve the target folder within the default account.
	local folder
	folder=$(notes_folder_name)
	folder=${folder//"/\\"/}
	printf '        set targetAccount to default account\n'
	printf '        if not (exists folder "%s" of targetAccount) then\n' "${folder}"
	printf '                error "Folder not found: %s"\n' "${folder}"
	printf '        end if\n'
	printf '        set targetFolder to folder "%s" of targetAccount\n' "${folder}"
}
