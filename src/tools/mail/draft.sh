#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create an Apple Mail draft from TOOL_QUERY.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/draft.sh}/mail/draft.sh"
#
# Environment variables:
#   TOOL_QUERY (string): first line = comma-separated recipients; second line = subject; remainder = body.
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
source "${BASH_SOURCE[0]%/mail/draft.sh}/registry.sh"
# shellcheck source=../../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail/draft.sh}/lib/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/draft.sh}/common.sh"

mail_build_recipient_args() {
	# Emits recipient addresses as separate osascript arguments.
	local recipients_line
	recipients_line=$1
	mail_split_recipients "${recipients_line}"
}

tool_mail_draft() {
	local recipients_line subject body

	if ! mail_require_platform; then
		return 0
	fi

	if ! { IFS= read -r -d '' recipients_line && IFS= read -r -d '' subject && IFS= read -r -d '' body; } < <(mail_extract_envelope); then
		log "ERROR" "Unable to parse mail envelope" "${TOOL_QUERY:-}" || true
		return 1
	fi

	local -a recipients
	while IFS= read -r recipient; do
		recipients+=("${recipient}")
	done < <(mail_build_recipient_args "${recipients_line}")

	log "INFO" "Creating Apple Mail draft" "${subject}" || true
	mail_run_script "${subject}" "${body}" "${recipients[@]}" <<'APPLESCRIPT'
on run argv
        set subjectLine to item 1 of argv
        set bodyText to item 2 of argv
        set recipientAddresses to items 3 thru (count of argv) of argv

        tell application "Mail"
                set newMessage to make new outgoing message with properties {subject:subjectLine, content:bodyText & "\n"}

                repeat with recipientAddress in recipientAddresses
                        set cleanedAddress to recipientAddress as text
                        make new to recipient at end of to recipients of newMessage with properties {address:cleanedAddress}
                end repeat

                return id of newMessage
        end tell
end run
APPLESCRIPT
}

register_mail_draft() {
        register_tool \
                "mail_draft" \
                "Create an Apple Mail draft using the first line for recipients and second for the subject." \
                "mail_draft 'to@example.com\\nSubject\\nBody'" \
                "Requires macOS Apple Mail access; content and recipients are sent to Mail." \
                tool_mail_draft
}
