#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final answer capture tool that records the agent's user-facing reply without side effects.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/final_answer.sh}/tools/final_answer.sh"
#
# Environment variables:
#   TOOL_QUERY (string): final user-facing reply to emit.
#
# Dependencies:
#   - bash 5+
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns 0 after echoing the supplied TOOL_QUERY.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/final_answer.sh}/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/final_answer.sh}/registry.sh"

tool_final_answer() {
	# Emits the provided final answer text without modification.
	# Arguments: none. Reads TOOL_QUERY for the final reply content.
	log "INFO" "final_answer tool invoked" "$(printf 'length=%s' "${#TOOL_QUERY}")" >&2
	printf '%s' "${TOOL_QUERY:-}" || true
}

register_final_answer() {
	register_tool \
		"final_answer" \
		"Emit the final user-facing answer without performing additional actions." \
		"final_answer <final reply>" \
		"Returns text directly to the user; avoid exposing sensitive data." \
		tool_final_answer
}
