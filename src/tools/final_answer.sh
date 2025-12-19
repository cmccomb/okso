#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final answer capture tool that records the agent's user-facing reply without side effects.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/final_answer.sh}/tools/final_answer.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args including `input`.
#
# Dependencies:
#   - bash 5+
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns 0 after echoing the supplied TOOL_ARGS.input.

# shellcheck source=../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/final_answer.sh}/lib/core/logging.sh"
# shellcheck source=../lib/cli/output.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/final_answer.sh}/lib/cli/output.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/final_answer.sh}/registry.sh"

tool_final_answer() {
	# Emits the provided final answer text without modification.
	# Arguments: none. Reads TOOL_ARGS.input.
	local args_json message text_key
	args_json="${TOOL_ARGS:-}" || true
	text_key="$(canonical_text_arg_key)"

	if [[ -n "${args_json}" ]]; then
		message=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>/dev/null || true)
	fi

	if [[ -z "${message:-}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.${text_key}" "${args_json}" >&2
		return 1
	fi

	log "INFO" "final_answer tool invoked" "$(printf 'length=%s' "${#message}")" >&2
	user_output "${message}" || true
}

register_final_answer() {
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"final_answer" \
		"Emit the final user-facing answer without performing additional actions." \
		"final_answer <final reply>" \
		"Returns text directly to the user; avoid exposing sensitive data." \
		tool_final_answer \
		"${args_schema}"
}
