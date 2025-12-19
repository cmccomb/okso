#!/usr/bin/env bash
# shellcheck shell=bash
#
# Complete a reminder by title within the configured Apple Reminders list.
#
# Usage:
#   source "${BASH_SOURCE[0]%/reminders/complete.sh}/reminders/complete.sh"
#
# Environment variables:
#   TOOL_ARGS (json): {"title": string}
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
source "${BASH_SOURCE[0]%/reminders/complete.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/reminders/complete.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/complete.sh}/common.sh"

tool_reminders_complete() {
	local title list_script

	if ! reminders_require_platform; then
		return 0
	fi

	if ! IFS= read -r -d '' title < <(reminders_extract_title_and_body); then
		return 1
	fi

	list_script="$(reminders_resolve_list_script)"

	log "INFO" "Completing Apple Reminder" "${title}"
	reminders_run_script "${title}" <<APPLESCRIPT
on run argv
        set reminderTitle to item 1 of argv
        tell application "Reminders"
${list_script}
                set matchingReminders to every reminder in targetList whose name is reminderTitle
                if (count of matchingReminders) is 0 then
                        error "Reminder not found: " & reminderTitle
                end if
                repeat with r in matchingReminders
                        set completed of r to true
                end repeat
                return name of item 1 of matchingReminders
        end tell
end run
APPLESCRIPT
}

register_reminders_complete() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["title"],"properties":{"title":{"type":"string","minLength":1}},"additionalProperties":false}
JSON
	)
	register_tool \
		"reminders_complete" \
		"Mark a reminder complete by title in the configured list." \
		"reminders_complete '<title_of_reminder_to_complete>'" \
		"Requires macOS Apple Reminders access; titles are sent to Reminders." \
		tool_reminders_complete \
		"${args_schema}"
}
