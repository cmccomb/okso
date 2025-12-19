#!/usr/bin/env bash
# shellcheck shell=bash
#
# List unread messages from the Apple Mail inbox.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/list_unread.sh}/mail/list_unread.sh"
#
# Environment variables:
#   MAIL_INBOX_LIMIT (int): maximum results to return; defaults to 10.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   MAIL_OSASCRIPT_BIN (string): override path for osascript; defaults to "osascript".
#
# Dependencies:
#   - bash 5+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - mail helpers from mail/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/mail/list_unread.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail/list_unread.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/list_unread.sh}/common.sh"

tool_mail_list_unread() {
	local limit
	limit=$(mail_inbox_limit)

	if ! mail_require_platform; then
		return 0
	fi

	log "INFO" "Listing unread Apple Mail inbox messages" "limit=${limit}" || true
	mail_run_script "${limit}" <<'APPLESCRIPT'
on run argv
        set maxItems to (item 1 of argv) as integer

        tell application "Mail"
                set unreadMessages to messages of inbox whose unread is true
                set output to {}
                set totalMessages to count of unreadMessages
                set upperBound to maxItems
                if totalMessages < maxItems then
                        set upperBound to totalMessages
                end if
                repeat with msg in items 1 thru upperBound of unreadMessages
                        set end of output to (subject of msg & " | From: " & sender of msg & " | Unread: " & unread of msg as string)
                end repeat
                return output
        end tell
end run
APPLESCRIPT
}

register_mail_list_unread() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","properties":{},"additionalProperties":false}
JSON
	)
	register_tool \
		"mail_list_unread" \
		"List unread Apple Mail inbox messages." \
		"mail_list_unread" \
		"Requires macOS Apple Mail access; returns metadata only." \
		tool_mail_list_unread \
		"${args_schema}"
}
