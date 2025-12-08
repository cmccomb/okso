#!/usr/bin/env bash
# shellcheck shell=bash
#
# Error handling helpers for the okso assistant CLI and tool scripts.
#
# Usage:
#   source "${BASH_SOURCE[0]%/errors.sh}/errors.sh"
#
# Environment variables:
#   ERROR_CONTEXT (string): optional override for the emitting component name.
#   TOOL_NAME (string): optional tool identifier used when ERROR_CONTEXT is unset.
#
# Dependencies:
#   - bash 5+
#   - jq
#
# Exit codes:
#   die exits non-zero with the provided status (default: 1).
#   warn returns a non-zero status (default: 1) so callers can surface failures.
#   log_debug returns 0.

emit_error_envelope() {
	# Emits a JSON error envelope with consistent metadata.
	# Arguments:
	#   $1 - context (string; optional; defaults to ERROR_CONTEXT/TOOL_NAME/runtime)
	#   $2 - category (string; required)
	#   $3 - message (string; required)
	local context category message
	context=${1:-${ERROR_CONTEXT:-${TOOL_NAME:-runtime}}}
	category="$2"
	message="$3"

	jq -cn \
		--arg name "${context}" \
		--arg category "${category}" \
		--arg message "${message}" \
		'{name:$name, category:$category, message:$message}'
}

die() {
	# Emits an error envelope and exits with a non-zero code.
	# Arguments:
	#   $1 - context (string; optional)
	#   $2 - category (string; required)
	#   $3 - message (string; required)
	#   $4 - exit code (int; optional; default: 1)
	local context category message status
	context=${1:-${ERROR_CONTEXT:-${TOOL_NAME:-runtime}}}
	category="$2"
	message="$3"
	status=${4:-1}

	emit_error_envelope "${context}" "${category}" "${message}" >&2
	exit "${status}"
}

warn() {
	# Emits an error envelope and returns a non-zero status for soft failures.
	# Arguments:
	#   $1 - context (string; optional)
	#   $2 - category (string; required)
	#   $3 - message (string; required)
	#   $4 - exit code (int; optional; default: 1)
	local context category message status
	context=${1:-${ERROR_CONTEXT:-${TOOL_NAME:-runtime}}}
	category="$2"
	message="$3"
	status=${4:-1}

	emit_error_envelope "${context}" "${category}" "${message}" >&2
	return "${status}"
}

log_debug() {
	# Emits a debug envelope without altering control flow.
	# Arguments:
	#   $1 - context (string; optional)
	#   $2 - message (string; required)
	local context message
	context=${1:-${ERROR_CONTEXT:-${TOOL_NAME:-runtime}}}
	message="$2"

	emit_error_envelope "${context}" "debug" "${message}" >&2
}
