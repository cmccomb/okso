#!/usr/bin/env bash
# shellcheck shell=bash
#
# JSON-backed state helpers.
#
# Usage:
#   source "${BASH_SOURCE[0]%/state.sh}/state.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 5+
#   - jq
#
# Exit codes:
#   Functions return non-zero on misuse; callers should handle failures.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./json_state.sh disable=SC1091
source "${LIB_DIR}/json_state.sh"

state_namespace_json_var() {
	# Arguments:
	#   $1 - state prefix (string)
	json_state_namespace_var "$@"
}

state_get_json_document() {
	# Arguments:
	#   $1 - state prefix (string)
	json_state_get_document "$@"
}

state_set_json_document() {
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - JSON document (string)
	json_state_set_document "$@"
}

state_set() {
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - key (string)
	#   $3 - value (string)
	json_state_set_key "$@"
}

state_get() {
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - key (string)
	json_state_get_key "$@"
}

state_increment() {
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - key (string)
	#   $3 - increment amount (int, optional; defaults to 1)
	json_state_increment_key "$@"
}

state_append_history() {
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - entry to append (string)
	json_state_append_history "$@"
}
