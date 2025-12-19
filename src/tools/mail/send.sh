#!/usr/bin/env bash
# shellcheck shell=bash
#
# Send an email via Apple Mail based on structured TOOL_ARGS input.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/send.sh}/mail/send.sh"
#
# Environment variables:
#   TOOL_ARGS (json): structured args including `input` with recipients, subject, and body lines.
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
source "${BASH_SOURCE[0]%/mail/send.sh}/registry.sh"
# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail/send.sh}/lib/core/logging.sh"
# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/send.sh}/common.sh"

tool_mail_send() {
	local recipients_line subject body args_json envelope text_key
	args_json="${TOOL_ARGS:-}" || true
	text_key="$(canonical_text_arg_key)"
	envelope=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>/dev/null || true)

	if [[ -z "${envelope}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.${text_key}" "${args_json}" || true
		return 1
	fi

	if ! mail_require_platform "${envelope}"; then
		return 0
	fi

	if ! { IFS= read -r -d '' recipients_line && IFS= read -r -d '' subject && IFS= read -r -d '' body; } < <(mail_extract_envelope "${envelope}"); then
		log "ERROR" "Unable to parse mail envelope" "${envelope}" || true
		return 1
	fi

	local -a recipients
	while IFS= read -r recipient; do
		recipients+=("${recipient}")
	done < <(mail_split_recipients "${recipients_line}")
	if ((${#recipients[@]} == 0)); then
		log "ERROR" "At least one recipient is required to send" "${envelope}" || true
		return 1
	fi

	log "INFO" "Sending Apple Mail message" "${subject}" || true
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
                send newMessage
                return id of newMessage
        end tell
end run
APPLESCRIPT
}

register_mail_send() {
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"mail_send" \
		"Send an email via Apple Mail; recipients on line one, subject on line two." \
		"mail_send 'to@example.com\\nSubject\\nBody'" \
		"Requires macOS Apple Mail access; sends immediately to listed recipients." \
		tool_mail_send \
		"${args_schema}"
}
