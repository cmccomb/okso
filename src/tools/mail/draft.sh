#!/usr/bin/env bash
# shellcheck shell=bash
#
# Create an Apple Mail draft from structured TOOL_ARGS input.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/draft.sh}/mail/draft.sh"
#
# Environment variables:
#   TOOL_ARGS (json): structured args including `input` with recipients, subject, and body lines.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   MAIL_OSASCRIPT_BIN (string): override path for osascript; defaults to "osascript".
#
# Dependencies:
#   - bash 3.2+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - mail helpers from mail/common.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/mail/draft.sh}/registry.sh"
# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/mail/draft.sh}/lib/core/logging.sh"
# shellcheck source=src/lib/tool_runtime/args.sh
source "${BASH_SOURCE[0]%/tools/mail/draft.sh}/lib/tool_runtime/args.sh"
# shellcheck source=src/tools/mail/common.sh
source "${BASH_SOURCE[0]%/draft.sh}/common.sh"

mail_build_recipient_args() {
	# Emits recipient addresses as separate osascript arguments.
	local recipients_line
	recipients_line=$1
	mail_split_recipients "${recipients_line}"
}

tool_mail_draft() {
	local recipients_line subject body envelope
	envelope="$(tool_args_parse_strict_single_string "input" "" "mail_draft" || true)"

	if [[ -z "${envelope}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.input" "${TOOL_ARGS:-{}}" || true
		return 1
	fi

	if ! { IFS= read -r -d '' recipients_line && IFS= read -r -d '' subject && IFS= read -r -d '' body; } < <(mail_extract_envelope "${envelope}"); then
		log "ERROR" "Unable to parse mail envelope" "${envelope}" || true
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
	local args_schema

	args_schema=$(
		cat <<'JSON'
{
  "type": "object",
  "required": ["input"],
  "properties": {
    "input": {
      "type": "string",
      "minLength": 1
    }
  }
}
JSON
	)
	register_tool \
		"mail_draft" \
		"Create an Apple Mail draft using the first line for recipients and second for the subject." \
		tool_mail_draft \
		"${args_schema}"
}
