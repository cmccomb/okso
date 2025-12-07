#!/usr/bin/env bash
# shellcheck shell=bash
#
# Direct-response helpers for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/respond.sh}/respond.sh"
#
# Environment variables:
#   LLAMA_AVAILABLE (bool): whether llama.cpp is available for inference.
#   VERBOSITY (int): log verbosity level.
#
# Dependencies:
#   - bash 5+
#
# Exit codes:
#   Functions print responses and return 0 on success.

# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/respond.sh}/logging.sh"

respond_text() {
	# Arguments:
	#   $1 - user query (string)
	local user_query prompt
	user_query="$1"

	prompt="Provide a short, concise answer (two to three sentences) to the user. Your response will be stopped after the first newline character. USER REQUEST: ${user_query}.\nCONCISE RESPONSE: "
	llama_infer "${prompt}" "\n"
	return 0
}
