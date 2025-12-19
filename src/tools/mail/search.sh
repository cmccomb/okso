#!/usr/bin/env bash
# shellcheck shell=bash
#
# Search Apple Mail messages in the inbox by subject, sender, or body.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/search.sh}/mail/search.sh"
#
# Environment variables:
#   TOOL_ARGS (json): structured args including `input`.
#   TOOL_QUERY (string): legacy search term fallback when TOOL_ARGS is absent.
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
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail/search.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/search.sh}/common.sh"

tool_mail_search() {
	local term limit args_json text_key
	args_json="${TOOL_ARGS:-}" || true
	text_key="$(canonical_text_arg_key)"
	term=${TOOL_QUERY:-""}
	limit=$(mail_inbox_limit)

	if [[ -n "${args_json}" ]]; then
		term=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>/dev/null || true)
	fi

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
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"mail_search" \
		"Search Apple Mail inbox messages by subject, sender, or content." \
		"mail_search 'term'" \
		"Requires macOS Apple Mail access; returns metadata only." \
		tool_mail_search \
		"${args_schema}"
}
