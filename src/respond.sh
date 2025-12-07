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
	#   $2 - prior observations (string, optional)
	local user_query observations prompt
	user_query="$1"
	observations="${2:-}"

        if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
                prompt="Provide a concise answer to the user without suggesting tools. User request: ${user_query}. Context: ${observations}"
                llama_infer "${prompt}"
                return 0
        fi

	printf 'Responding directly to: %s\n' "${user_query}"
}

respond() {
	local user_query observations answer
	user_query="$1"
	observations="${2:-}"
	answer="$(respond_text "${user_query}" "${observations}")"
	printf '%s\n' "${answer}"
}
