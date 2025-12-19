#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create a new Apple Reminder using structured input fields.
#
# Usage:
#   source "${BASH_SOURCE[0]%/reminders/create.sh}/reminders/create.sh"
#
# Environment variables:
#   TOOL_ARGS (json): {"title": string, "time": string, "notes": string}
#   REMINDERS_LIST (string): target list within Apple Reminders.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 5+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - reminders helpers from reminders/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/reminders/create.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/reminders/create.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/create.sh}/common.sh"

derive_reminders_create_query() {
	# Arguments:
	#   $1 - user query (string)
	local user_query nocasematch_enabled
	user_query="$1"
	nocasematch_enabled=false

	if shopt -q nocasematch; then
		nocasematch_enabled=true
	fi
	shopt -s nocasematch

	if [[ "${user_query}" =~ remind[[:space:]]+me[[:space:]]+to[[:space:]]+(.+) ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
		if [[ "${nocasematch_enabled}" == false ]]; then
			shopt -u nocasematch
		fi
		return
	fi

	if [[ "${user_query}" =~ remind[[:space:]]+me[[:space:]]+(.+) ]]; then
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

tool_reminders_create() {
	local title body list_script

	if ! reminders_require_platform; then
		return 0
	fi

	if ! { IFS= read -r -d '' title && IFS= read -r -d '' body; } < <(reminders_extract_title_and_body); then
		return 1
	fi

	list_script="$(reminders_resolve_list_script)"

	log "INFO" "Creating Apple Reminder" "${title}"
	reminders_run_script "${title}" "${body}" <<APPLESCRIPT
on run argv
        set reminderTitle to item 1 of argv
        set reminderBody to item 2 of argv
        tell application "Reminders"
${list_script}
                set newReminder to make new reminder at end of reminders of targetList with properties {name:reminderTitle, body:reminderBody}
                return name of newReminder
        end tell
end run
APPLESCRIPT
}

register_reminders_create() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["title"],"properties":{"title":{"type":"string","minLength":1},"time":{"type":"string"},"notes":{"type":"string"}},"additionalProperties":false}
JSON
	)
	register_tool \
		"reminders_create" \
		"Create a new Apple Reminder using structured details." \
		"reminders_create {\"title\":\"Take out trash\",\"time\":\"tonight\",\"notes\":\"before 9pm\"}" \
		"Requires macOS Apple Reminders access; content is sent to Reminders." \
		tool_reminders_create \
		"${args_schema}"
}
