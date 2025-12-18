#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final answer capture tool that records the agent's user-facing reply without side effects.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/final_answer.sh}/tools/final_answer.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args including `message`.
#
# Dependencies:
#   - bash 5+
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns 0 after echoing the supplied TOOL_ARGS.message.

# shellcheck source=../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/final_answer.sh}/lib/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/final_answer.sh}/registry.sh"

tool_final_answer() {
	# Emits the provided final answer text without modification.
	# Arguments: none. Reads TOOL_ARGS.message.
	local args_json message
	args_json="${TOOL_ARGS:-}" || true

	if [[ -n "${args_json}" ]]; then
		message=$(jq -er '
if type != "object" then error("args must be object") end
| if .message? == null then error("missing message") end
| if (.message | type) != "string" then error("message must be string") end
| if (.message | length) == 0 then error("message cannot be empty") end
| if ((del(.message) | length) != 0) then error("unexpected properties") end
| .message
' <<<"${args_json}" 2>/dev/null || true)
	fi

	if [[ -z "${message:-}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.message" "${args_json}" >&2
		return 1
	fi

	log "INFO" "final_answer tool invoked" "$(printf 'length=%s' "${#message}")" >&2
	printf '%s' "${message}" || true
}

register_final_answer() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["message"],"properties":{"message":{"type":"string","minLength":1}},"additionalProperties":false}
JSON
	)
	register_tool \
		"final_answer" \
		"Emit the final user-facing answer without performing additional actions." \
		"final_answer <final reply>" \
		"Returns text directly to the user; avoid exposing sensitive data." \
		tool_final_answer \
		"${args_schema}"
}
