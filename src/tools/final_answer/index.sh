#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final answer capture tool that records the agent's user-facing reply without side effects.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/final_answer/index.sh}/tools/final_answer/index.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `input` answer text.
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns 0 after emitting the final answer text.

# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/final_answer/index.sh}/lib/core/logging.sh"
# shellcheck source=src/lib/cli/output.sh
source "${BASH_SOURCE[0]%/tools/final_answer/index.sh}/lib/cli/output.sh"
# shellcheck source=src/lib/tools/args.sh
source "${BASH_SOURCE[0]%/tools/final_answer/index.sh}/lib/tools/args.sh"
# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/final_answer/index.sh}/registry.sh"

tool_final_answer() {
	# Emits TOOL_ARGS.input as the final user-facing answer.
	# Arguments: none.
	local message
	message="$(tool_args_parse_strict_single_string "input" "" "final_answer")" || return 1

	log "INFO" "final_answer tool invoked" "$(printf 'length=%s' "${#message}")" >&2
	user_output "${message}" || true
}

register_final_answer() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{
  "type": "object",
  "required": ["input"],
  "additionalProperties": false,
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
		"final_answer" \
		"Emit the final user-facing answer text from args.input without side effects." \
		tool_final_answer \
		"${args_schema}"
}
