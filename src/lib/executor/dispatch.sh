#!/usr/bin/env bash
# shellcheck shell=bash
#
# Execution and confirmation helpers for planner actions.
#
# Usage:
#   source "${BASH_SOURCE[0]%/execution.sh}/execution.sh"
#
# Environment variables:
#   None today.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on invalid configuration or handler failures.

EXEC_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${EXEC_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/core/errors.sh
source "${EXEC_LIB_DIR}/../core/errors.sh"
# shellcheck source=src/lib/settings/config.sh
source "${EXEC_LIB_DIR}/../settings/config.sh"
# shellcheck source=src/lib/tools/index.sh
source "${EXEC_LIB_DIR}/../tools/index.sh"

execute_tool_with_query() {
	# Arguments:
	#   $1 - tool name
	#   $2 - tool query (legacy string)
	#   $3 - human-readable context
	#   $4 - structured args JSON
	# Returns:
	#   JSON object with keys: output (string), error (string), exit_code (int)

	local tool_name tool_query context handler output status tool_args_json
	tool_name="$1"
	tool_query="$2"
	context="$3"
	tool_args_json="$4"

	# Lookup the tool handler
	handler="$(tool_handler "${tool_name}")"

	# Validate handler existence
	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}" >&2
		return 1
	fi

	# Execute the tool handler with captured stdout and stderr
	local stdout_file stderr_file stderr_output
	stdout_file="$(mktemp)"
	stderr_file="$(mktemp)"

	# Execute the tool handler
	TOOL_QUERY="${tool_query}" TOOL_ARGS="${tool_args_json}" ${handler} >"${stdout_file}" 2>"${stderr_file}"

	# Capture outputs and status
	status=$?
	output="$(cat "${stdout_file}")"
	stderr_output="$(cat "${stderr_file}")"

	# Clean up temporary files
	rm -f "${stdout_file}" "${stderr_file}"

	# Log stderr and non-zero exit codes
	if [[ -n "${stderr_output}" ]]; then
		log "INFO" "Tool emitted stderr" "$(printf 'tool=%s stderr=%s' "${tool_name}" "${stderr_output}")" >&2
	fi
	if ((status != 0)); then
		log "WARN" "Tool reported non-zero exit" "${tool_name}" >&2
	fi

	# Emit the result as a JSON object
	jq -nc \
		--arg output "${output}" \
		--arg error "${stderr_output}" \
		--argjson exit_code "${status}" \
		'{output: $output, error: $error, exit_code: $exit_code}'

	# If we reach here, execution was successful
	return 0
}

export -f execute_tool_with_query
