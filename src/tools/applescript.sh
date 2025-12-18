#!/usr/bin/env bash
# shellcheck shell=bash
#
# AppleScript tool that executes snippets on macOS when available.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/applescript.sh}/tools/applescript.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args including `script`.
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

# shellcheck source=../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/applescript.sh}/lib/logging.sh"
# shellcheck source=./osascript_helpers.sh disable=SC1091
source "${BASH_SOURCE[0]%/applescript.sh}/osascript_helpers.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/applescript.sh}/registry.sh"

tool_applescript() {
	local query args_json
	args_json="${TOOL_ARGS:-}" || true
	query=""

	if [[ -n "${args_json}" ]]; then
		query=$(jq -er '
if type != "object" then error("args must be object") end
| if .script? == null then error("missing script") end
| if (.script | type) != "string" then error("script must be string") end
| if (.script | length) == 0 then error("script cannot be empty") end
| if ((del(.script) | length) != 0) then error("unexpected properties") end
| .script
' <<<"${args_json}" 2>/dev/null || true)
	fi

	if [[ -z "${query:-}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.script" "${args_json}" >&2
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

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["script"],"properties":{"script":{"type":"string","minLength":1}},"additionalProperties":false}
JSON
	)
	register_tool \
		"applescript" \
		"Execute AppleScript snippets on macOS." \
		"applescript '<script>'" \
		"Only available on macOS; disabled elsewhere." \
		tool_applescript \
		"${args_schema}"
}
