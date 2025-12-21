#!/usr/bin/env bash
# shellcheck shell=bash
#
# Token estimation helpers for llama.cpp integrations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tokens.sh}/tokens.sh"
#
# Dependencies:
#   - bash 3.2+
#
# Exit codes:
#   Functions print derived values and return 0 on success.

estimate_token_count() {
	# Estimates the number of tokens in a string based on character length.
	# Arguments:
	#   $1 - text content (string)
	local text length token_estimate
	text="$1"
	length=${#text}
	token_estimate=$(((length + 3) / 4))
	printf '%s' "${token_estimate}"
}

export -f estimate_token_count
