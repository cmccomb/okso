#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for Apple Reminders tool integrations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/reminders/common.sh}/reminders/common.sh"
#
# Environment variables:
#   REMINDERS_LIST (string): target list name; defaults to "Reminders".
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   REMINDERS_OSASCRIPT_BIN (string): override path for osascript; defaults to "osascript".
#   VERBOSITY (int): logging verbosity; see logging.sh.
#
# Dependencies:
#   - bash 3.2+
#   - osascript (optional; required on macOS)
#   - logging helpers from logging.sh
#   - osascript helpers from osascript_helpers.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero on misuse.

# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/reminders/common.sh}/lib/core/logging.sh"
# shellcheck source=src/tools/apple_app.sh
source "${BASH_SOURCE[0]%/tools/reminders/common.sh}/tools/apple_app.sh"

reminders_list_name() {
	# Prints the resolved Apple Reminders list name.
	local list
	list=${REMINDERS_LIST:-"Reminders"}
	printf '%s' "${list}"
}

reminders_extract_title_and_body() {
	# Splits TOOL_ARGS into a title (first line) and body (remaining lines).
	# Emits two NUL-delimited fields: title then body.
	local title notes text_key

	text_key="input"
	title=$(jq -er --arg key "${text_key}" 'if type == "object" then .[$key] // .title // empty else empty end' <<<"${TOOL_ARGS:-{}}" 2>/dev/null || true)
	notes=$(jq -er '.notes // ""' <<<"${TOOL_ARGS:-{}}" 2>/dev/null || true)

	if [[ -z "${title//[[:space:]]/}" && -z "${notes//[[:space:]]/}" ]]; then
		log "ERROR" "Reminder content is required" "" || true
		return 1
	fi

	if [[ -z "${title//[[:space:]]/}" ]]; then
		title="Untitled reminder $(date -Iseconds)"
	fi

	printf '%s\0%s\0' "${title}" "${notes}"
}

reminders_run_script() {
	# Runs an AppleScript provided on stdin, passing through all arguments.
	# Arguments:
	#   $@ - parameters forwarded to osascript
	local bin
	bin=${REMINDERS_OSASCRIPT_BIN:-osascript}
	apple_app_run_script "${bin}" "$@"
}

reminders_resolve_list_script() {
	# Emits AppleScript lines that resolve the target list within the default account.
	local list
	list=$(reminders_list_name)
	apple_script_resolve_in_default_account "list" "${list}" "targetList" "List"
}
