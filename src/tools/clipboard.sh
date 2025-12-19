#!/usr/bin/env bash
# shellcheck shell=bash
#
# Clipboard utilities for copying and pasting text via macOS pbcopy/pbpaste.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/clipboard.sh}/tools/clipboard.sh"
#
# Environment variables:
#   TOOL_QUERY (string): text to copy (for clipboard_copy) or ignored for paste.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 5+
#   - pbcopy/pbpaste (macOS only)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero when a required dependency is missing on macOS.

# shellcheck source=../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/clipboard.sh}/lib/core/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/clipboard.sh}/registry.sh"

clipboard_require_macos() {
	# Short-circuits when not running on macOS.
	if [[ "${IS_MACOS}" != true ]]; then
		log "WARN" "Clipboard operations require macOS" "${TOOL_QUERY:-}"
		return 1
	fi
	return 0
}

tool_clipboard_copy() {
	local content
	content=${TOOL_QUERY:-""}

	if ! clipboard_require_macos; then
		return 0
	fi

	if ! command -v pbcopy >/dev/null 2>&1; then
		log "ERROR" "pbcopy missing; cannot copy to clipboard" "${content}"
		return 1
	fi

	printf '%s' "${content}" | pbcopy
}

tool_clipboard_paste() {
	if ! clipboard_require_macos; then
		return 0
	fi

	if ! command -v pbpaste >/dev/null 2>&1; then
		log "ERROR" "pbpaste missing; cannot read clipboard" "${TOOL_QUERY:-}"
		return 1
	fi

	pbpaste
}

register_clipboard_copy() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["text"],"properties":{"text":{"type":"string","minLength":1}},"additionalProperties":false}
JSON
	)
	register_tool \
		"clipboard_copy" \
		"Copy the provided text into the macOS clipboard." \
		"clipboard_copy <text_to_be_copied>" \
		"Clipboard contents may expose sensitive data; avoid copying secrets." \
		tool_clipboard_copy \
		"${args_schema}"
}

register_clipboard_paste() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","properties":{},"additionalProperties":false}
JSON
	)
	register_tool \
		"clipboard_paste" \
		"Read the current macOS clipboard contents." \
		"clipboard_paste" \
		"Clipboard may contain sensitive data; review before sharing or logging." \
		tool_clipboard_paste \
		"${args_schema}"
}
