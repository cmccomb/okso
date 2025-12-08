#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for Apple Mail tool integrations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/common.sh}/mail/common.sh"
#
# Environment variables:
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   MAIL_OSASCRIPT_BIN (string): override path for osascript; defaults to "osascript".
#   MAIL_INBOX_LIMIT (int): maximum messages returned when listing mailboxes; defaults to 10.
#   VERBOSITY (int): logging verbosity; see logging.sh.
#
# Dependencies:
#   - bash 5+
#   - osascript (optional; required on macOS)
#   - logging helpers from logging.sh
#   - osascript helpers from osascript_helpers.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero on misuse.

# shellcheck source=../../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail/common.sh}/logging.sh"
# shellcheck source=../osascript_helpers.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail/common.sh}/tools/osascript_helpers.sh"

mail_require_platform() {
	# Ensures Apple Mail tools only run on macOS with osascript available.
	if [[ "${IS_MACOS}" != true ]]; then
		log "WARN" "Apple Mail is only available on macOS" "${TOOL_QUERY:-}" || true
		return 1
	fi

	if ! command -v "${MAIL_OSASCRIPT_BIN:-osascript}" >/dev/null 2>&1; then
		log "WARN" "osascript missing; cannot reach Apple Mail" "${TOOL_QUERY:-}" || true
		return 1
	fi

	return 0
}

mail_inbox_limit() {
	# Prints a positive integer inbox limit.
	local limit
	limit=${MAIL_INBOX_LIMIT:-10}
	if [[ -z "${limit}" || ${limit} -le 0 ]]; then
		limit=10
	fi
	printf '%s' "${limit}"
}

mail_trim_whitespace() {
	# Trims leading and trailing whitespace from the provided string.
	# Arguments:
	#   $1 - string to trim
	local value
	value=$1
	value=${value#"${value%%[![:space:]]*}"}
	value=${value%"${value##*[![:space:]]}"}
	printf '%s' "${value}"
}

mail_extract_envelope() {
	# Splits TOOL_QUERY into recipients, subject, and body.
	# Emits three NUL-delimited fields: recipients, subject, body.
	local query recipients subject body remainder
	query=${TOOL_QUERY:-""}

	if [[ -z "${query//[[:space:]]/}" ]]; then
		log "ERROR" "Mail content is required" "" || true
		return 1
	fi

	recipients=${query%%$'\n'*}
	remainder=${query#"${recipients}"}
	remainder=${remainder#$'\n'}
	subject=${remainder%%$'\n'*}
	body=${remainder#"${subject}"}
	body=${body#$'\n'}

	recipients=$(mail_trim_whitespace "${recipients}")
	subject=$(mail_trim_whitespace "${subject}")

	if [[ -z "${recipients}" ]]; then
		log "ERROR" "At least one recipient is required (comma-separated)" "" || true
		return 1
	fi

	if [[ -z "${subject}" ]]; then
		subject="(no subject)"
	fi

	printf '%s\0%s\0%s\0' "${recipients}" "${subject}" "${body}"
}

mail_split_recipients() {
	# Emits one trimmed recipient per line from a comma-separated list.
	# Arguments:
	#   $1 - comma-separated recipients
	local recipients raw trimmed
	local -a parts
	recipients=$1

	IFS=',' read -ra parts <<<"${recipients}"
	for raw in "${parts[@]}"; do
		trimmed=$(mail_trim_whitespace "${raw}")
		if [[ -n "${trimmed}" ]]; then
			printf '%s\n' "${trimmed}"
		fi
	done
}

mail_run_script() {
	# Runs an AppleScript provided on stdin, passing through all arguments.
	# Arguments:
	#   $@ - parameters forwarded to osascript
	local bin
	bin=${MAIL_OSASCRIPT_BIN:-osascript}
	osascript_run_piped "${bin}" "$@"
}
