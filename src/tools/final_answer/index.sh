#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final answer capture tool that records the agent's user-facing reply without side effects.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/final_answer/index.sh}/tools/final_answer/index.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args (unused; must be empty object when present).
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
# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/final_answer/index.sh}/registry.sh"

tool_final_answer() {
	# Emits the provided final answer text without modification.
	# Arguments: none. Reads TOOL_ARGS when present.
	local args_json message
	args_json="${TOOL_ARGS:-}" || true
	message=""

	if [[ -n "${args_json}" ]]; then
		if ! jq -e 'type == "object" and length == 0' <<<"${args_json}" >/dev/null 2>&1; then
			log "ERROR" "Invalid TOOL_ARGS for final_answer" "${args_json}" >&2
			return 1
		fi
	fi

	log "INFO" "final_answer tool invoked" "$(printf 'length=%s' "${#message}")" >&2
	user_output "${message}" || true
}

register_final_answer() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{
  "type": "object",
  "additionalProperties": false,
  "properties": {}
}
JSON
	)
	register_tool \
		"final_answer" \
		"Emit the final user-facing answer without performing additional actions. When using final_answer, respond as a calm, courteous 'polite haunting' guide: gently uncanny, never intrusive. Keep the tone soft but decisive, prefer evidence over explanation, and anchor statements to concrete artifacts (filenames/paths/log lines) instead of pronouns. Output should be small, clean, and paste-ready." \
		tool_final_answer \
		"${args_schema}"
}
