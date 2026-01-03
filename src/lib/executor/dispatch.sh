#!/usr/bin/env bash
# shellcheck shell=bash
#
# Execution and confirmation helpers for planner actions.
#
# Usage:
#   source "${BASH_SOURCE[0]%/execution.sh}/execution.sh"
#
# Environment variables:
#   FORCE_CONFIRM (bool): force confirmations even when approvals granted.
#   APPROVE_ALL (bool): bypass confirmations when true.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on invalid configuration or handler failures.

EXEC_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Initialize default values for optional environment variables
FORCE_CONFIRM="${FORCE_CONFIRM:-false}"
APPROVE_ALL="${APPROVE_ALL:-false}"

# shellcheck source=src/lib/core/logging.sh
source "${EXEC_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/core/errors.sh
source "${EXEC_LIB_DIR}/../core/errors.sh"
# shellcheck source=src/lib/config.sh
source "${EXEC_LIB_DIR}/../config.sh"
# shellcheck source=src/lib/tools.sh
source "${EXEC_LIB_DIR}/../tools.sh"

should_prompt_for_tool() {
	# Default behavior is to prompt unless APPROVE_ALL is explicitly set to true.
	# Arguments: none
	# Environment:
	#   APPROVE_ALL (bool): if true, skip prompts; otherwise prompt
	if [[ "${APPROVE_ALL}" == true ]]; then
		return 1
	fi

	return 0
}

confirm_tool() {
	# Arguments:
	#   $1 - tool name
	#   $2 - human-readable context (string; optional)
	# Returns:
	#  0 if confirmed, 1 if declined, 2 if feedback provided

	local tool_name context
	tool_name="$1"
	context="$2"

	# Skip confirmation if FORCE_CONFIRM is not set and APPROVE_ALL is true
	if ! should_prompt_for_tool; then
		return 0
	fi

	# Build the prompt message
	local prompt
	prompt="Execute tool \"${tool_name}\"?"
	if [[ -n "${context}" ]]; then
		prompt+=$'\n'"${context}"
	fi
	if command -v gum >/dev/null 2>&1; then
		if ! gum confirm --affirmative "Run" --negative "Skip" "${prompt}"; then
			log "WARN" "Tool execution declined" "${tool_name}"
			printf '[%s skipped]\n' "${tool_name}"
			return 1
		fi
		return 0
	fi

	# Prompt the user for confirmation
	printf '%s [y/N/feedback]: ' "${prompt}" >&2
	read -r reply

	# Check if reply is feedback (not empty and not y/Y/n/N)
	if [[ -n "${reply}" && "${reply}" != "y" && "${reply}" != "Y" && "${reply}" != "n" && "${reply}" != "N" ]]; then
		# User provided feedback instead of a simple y/N response
		log "INFO" "User provided feedback during tool confirmation" "tool=${tool_name}"
		# Store feedback for planner to consume
		printf '{"type":"feedback","tool":"%s","feedback":"%s"}' "${tool_name}" "$(printf '%s' "${reply}" | jq -Rs .)"
		return 2
	fi

	# Check for affirmative response
	if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
		log "WARN" "Tool execution declined" "${tool_name}"
		printf '[%s skipped]\n' "${tool_name}"
		return 1
	fi

	# If we reach here, the tool is confirmed
	return 0
}

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

	# Determine if confirmation is required
	local requires_confirmation
	requires_confirmation=false
	if [[ "${tool_name}" != "final_answer" ]] && should_prompt_for_tool; then
		requires_confirmation=true
	fi

	# Validate handler existence
	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}" >&2
		return 1
	fi

	# Request confirmation if needed
	if [[ "${tool_name}" != "final_answer" ]]; then

		# Only request confirmation if not final_answer
		if [[ "${requires_confirmation}" == true ]]; then
			log "INFO" "Requesting tool confirmation" "$(printf 'tool=%s query=%s' "${tool_name}" "${tool_query}")" >&2
		fi

		# Prompt for confirmation
		if ! confirm_tool_output=$(confirm_tool "${tool_name}" "${context}"); then
			confirm_status=$?

			# Check if user provided feedback (exit code 2)
			if [[ ${confirm_status} -eq 2 ]]; then
				# Output the feedback JSON and return 2 to signal replanning needed
				printf '%s' "${confirm_tool_output}"
				return 2
			fi

			# Indicate the tool was declined
			printf 'Declined %s\n' "${tool_name}"
			return 0
		fi
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

export -f should_prompt_for_tool
export -f confirm_tool
export -f execute_tool_with_query
