#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create a new Apple Reminder using the first query line as the title.
#
# Usage:
#   source "${BASH_SOURCE[0]%/reminders/create.sh}/reminders/create.sh"
#
# Environment variables:
#   TOOL_QUERY (string): reminder content; first line becomes the title.
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
# shellcheck source=../../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/reminders/create.sh}/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/create.sh}/common.sh"

tool_reminders_create() {
	local title body list_script

	if ! reminders_require_platform; then
		return 0
	fi

	if ! { IFS= read -r -d '' title && IFS= read -r -d '' body; } < <(reminders_extract_title_and_body); then
		return 0
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
	register_tool \
		"reminders_create" \
		"Create a new Apple Reminder using the first line as the title." \
		"osascript -e 'make new reminder with {name:<title>, body:<body>}'" \
		"Requires macOS Apple Reminders access; content is sent to Reminders." \
		tool_reminders_create
}
