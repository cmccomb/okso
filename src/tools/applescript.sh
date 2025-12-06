#!/usr/bin/env bash
# shellcheck shell=bash
#
# AppleScript tool that executes snippets on macOS when available.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/applescript.sh}/tools/applescript.sh"
#
# Environment variables:
#   TOOL_QUERY (string): AppleScript snippet to run.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 5+
#   - osascript (optional on macOS)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/applescript.sh}/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/applescript.sh}/registry.sh"

tool_applescript() {
	local query
	query=${TOOL_QUERY:-""}

	if [[ "${IS_MACOS}" != true ]]; then
		log "WARN" "AppleScript not available on this platform" "${query}"
		return 0
	fi

	if ! command -v osascript >/dev/null 2>&1; then
		log "WARN" "osascript missing; cannot execute AppleScript" "${query}"
		return 0
	fi

	log "INFO" "Executing AppleScript" "${query}"
	osascript -e "${query}"
}

register_applescript() {
	register_tool \
		"applescript" \
		"Execute AppleScript snippets on macOS." \
		"osascript -e '<script>'" \
		"Only available on macOS; disabled elsewhere." \
		tool_applescript
}
