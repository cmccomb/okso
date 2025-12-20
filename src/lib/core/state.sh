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
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on misuse; callers should handle failures.

CORE_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./json_state.sh disable=SC1091
source "${CORE_LIB_DIR}/json_state.sh"

state_namespace_json_var() {
	# Proxies to json_state_namespace_var.
	# Arguments:
	#   $1 - state prefix (string)
	# Returns:
	#   The variable name (string).
	json_state_namespace_var "$@"
}

state_get_json_document() {
	# Proxies to json_state_get_document.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - fallback JSON document (string, optional)
	# Returns:
	#   The JSON document (string).
	json_state_get_document "$@"
}

state_set_json_document() {
	# Proxies to json_state_set_document.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - JSON document (string)
	json_state_set_document "$@"
}

state_set() {
	# Proxies to json_state_set_key.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - key (string)
	#   $3 - value (string)
	json_state_set_key "$@"
}

state_get() {
	# Proxies to json_state_get_key.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - key (string)
	# Returns:
	#   The value for the key (string).
	json_state_get_key "$@"
}

state_increment() {
	# Proxies to json_state_increment_key.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - key (string)
	#   $3 - increment amount (int, optional)
	json_state_increment_key "$@"
}

state_append_history() {
	# Proxies to json_state_append_history.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - entry to append (string)
	json_state_append_history "$@"
}
