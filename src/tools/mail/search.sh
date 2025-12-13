#!/usr/bin/env bash
# shellcheck shell=bash
#
# Search Apple Mail messages in the inbox by subject, sender, or body.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/search.sh}/mail/search.sh"
#
# Environment variables:
#   TOOL_QUERY (string): search term to filter inbox messages.
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
source "${BASH_SOURCE[0]%/mail/search.sh}/registry.sh"
# shellcheck source=../../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail/search.sh}/lib/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/search.sh}/common.sh"

tool_mail_search() {
	local term limit
	term=${TOOL_QUERY:-""}
	limit=$(mail_inbox_limit)

	if ! mail_require_platform; then
		return 0
	fi

	if [[ -z "${term//[[:space:]]/}" ]]; then
		log "ERROR" "Search term is required" "" || true
		return 1
	fi

	log "INFO" "Searching Apple Mail inbox" "${term}" || true
	mail_run_script "${term}" "${limit}" <<'APPLESCRIPT'
on run argv
        set searchTerm to item 1 of argv
        set maxItems to (item 2 of argv) as integer

        tell application "Mail"
                set matchingMessages to messages of inbox whose subject contains searchTerm or sender contains searchTerm or content contains searchTerm
                set output to {}
                set totalMessages to count of matchingMessages
                set upperBound to maxItems
                if totalMessages < maxItems then
                        set upperBound to totalMessages
                end if
                repeat with msg in items 1 thru upperBound of matchingMessages
                        set end of output to (subject of msg & " | From: " & sender of msg & " | Unread: " & unread of msg as string)
                end repeat
                return output
        end tell
end run
APPLESCRIPT
}

register_mail_search() {
        register_tool \
                "mail_search" \
                "Search Apple Mail inbox messages by subject, sender, or content." \
                "mail_search 'term'" \
                "Requires macOS Apple Mail access; returns metadata only." \
                tool_mail_search
}
