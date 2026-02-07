#!/usr/bin/env bash
# shellcheck shell=bash
#
# List open reminders within the configured Apple Reminders list.
#
# Returns newline-delimited reminder titles to preserve commas in titles.
#
# Usage:
#   source "${BASH_SOURCE[0]%/reminders/list.sh}/reminders/list.sh"
#
# Environment variables:
#   REMINDERS_LIST (string): target list within Apple Reminders.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 3.2+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - reminders helpers from reminders/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/reminders/list.sh}/registry.sh"
# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/reminders/list.sh}/lib/core/logging.sh"
# shellcheck source=src/tools/reminders/common.sh
source "${BASH_SOURCE[0]%/list.sh}/common.sh"

tool_reminders_list() {
	local list_script

	list_script="$(reminders_resolve_list_script)"

	log "INFO" "Listing Apple Reminders" "$(reminders_list_name)"
	reminders_run_script "$@" <<APPLESCRIPT
on run argv
        tell application "Reminders"
${list_script}
                set reminderNames to name of (reminders of targetList whose completed is false)
                set AppleScript's text item delimiters to "\n"
                return reminderNames as string
        end tell
end run
APPLESCRIPT
}

register_reminders_list() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{
  "type": "object",
  "properties": {}
}
JSON
	)
	register_tool \
		"reminders_list" \
		"List incomplete Apple Reminders in the configured list." \
		tool_reminders_list \
		"${args_schema}"
}
