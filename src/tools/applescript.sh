#!/usr/bin/env bash
# shellcheck shell=bash
#
# AppleScript tool that executes snippets on macOS when available.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/applescript.sh}/tools/applescript.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args including `input`.
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

# shellcheck source=../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/applescript.sh}/lib/core/logging.sh"
# shellcheck source=./osascript_helpers.sh disable=SC1091
source "${BASH_SOURCE[0]%/applescript.sh}/osascript_helpers.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/applescript.sh}/registry.sh"

tool_applescript() {
	local query args_json text_key
	args_json="${TOOL_ARGS:-}" || true
	query=""
	text_key="$(canonical_text_arg_key)"

	if [[ -n "${args_json}" ]]; then
		query=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>/dev/null || true)
	fi

	if [[ -z "${query:-}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.${text_key}" "${args_json}" >&2
		return 1
	fi

	if ! assert_osascript_available \
		"AppleScript not available on this platform" \
		"osascript missing; cannot execute AppleScript" \
		"osascript" \
		"${query}"; then
		return 0
	fi

	log "INFO" "Executing AppleScript" "${query}"
	if ! osascript_run_evaluated "osascript" "${query}"; then
		return 1
	fi
}

register_applescript() {
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"applescript" \
		"Execute AppleScript snippets on macOS." \
		"applescript '<script>'" \
		"Only available on macOS; disabled elsewhere." \
		tool_applescript \
		"${args_schema}"
}
