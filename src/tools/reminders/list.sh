#!/usr/bin/env bash
# shellcheck shell=bash
#
# List open reminders within the configured Apple Reminders list.
#
# Usage:
#   source "${BASH_SOURCE[0]%/reminders/list.sh}/reminders/list.sh"
#
# Environment variables:
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
source "${BASH_SOURCE[0]%/reminders/list.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/reminders/list.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/list.sh}/common.sh"

derive_reminders_list_query() {
	# Arguments:
	#   $1 - user query (string)
	printf 'list\n'
}

tool_reminders_list() {
	local list_script

	if ! reminders_require_platform; then
		return 0
	fi

	list_script="$(reminders_resolve_list_script)"

	log "INFO" "Listing Apple Reminders" "$(reminders_list_name)"
	reminders_run_script <<APPLESCRIPT
on run argv
        tell application "Reminders"
${list_script}
                return name of (reminders of targetList whose completed is false)
        end tell
end run
APPLESCRIPT
}

register_reminders_list() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","properties":{},"additionalProperties":false}
JSON
	)
	register_tool \
		"reminders_list" \
		"List incomplete Apple Reminders in the configured list." \
		"reminders_list" \
		"Requires macOS Apple Reminders access; reminder titles are read." \
		tool_reminders_list \
		"${args_schema}"
}
