#!/usr/bin/env bash
# shellcheck shell=bash
#
# Execution and confirmation helpers for planner actions.
#
# Usage:
#   source "${BASH_SOURCE[0]%/execution.sh}/execution.sh"
#
# Environment variables:
#   PLAN_ONLY (bool): skip executions and confirmations when true.
#   DRY_RUN (bool): skip executions when true.
#   FORCE_CONFIRM (bool): force confirmations even when approvals granted.
#   APPROVE_ALL (bool): bypass confirmations when true.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on invalid configuration or handler failures.

PLANNING_EXECUTION_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_EXECUTION_DIR}/../core/logging.sh"
# shellcheck source=../core/errors.sh disable=SC1091
source "${PLANNING_EXECUTION_DIR}/../core/errors.sh"
# shellcheck source=../config.sh disable=SC1091
source "${PLANNING_EXECUTION_DIR}/../config.sh"
# shellcheck source=../tools.sh disable=SC1091
source "${PLANNING_EXECUTION_DIR}/../tools.sh"

should_prompt_for_tool() {
	if [[ "${PLAN_ONLY}" == true || "${DRY_RUN}" == true ]]; then
		return 1
	fi
	if [[ "${FORCE_CONFIRM}" == true ]]; then
		return 0
	fi
	if [[ "${APPROVE_ALL}" == true ]]; then
		return 1
	fi

	return 0
}

confirm_tool() {
	local tool_name context
	tool_name="$1"
	context="$2"
	if ! should_prompt_for_tool; then
		return 0
	fi

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

	printf '%s [y/N]: ' "${prompt}" >&2
	read -r reply
	if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
		log "WARN" "Tool execution declined" "${tool_name}"
		printf '[%s skipped]\n' "${tool_name}"
		return 1
	fi
	return 0
}

execute_tool_with_query() {
	# Arguments:
	#   $1 - tool name
	#   $2 - tool query (legacy string)
	#   $3 - human-readable context
	#   $4 - structured args JSON
	local tool_name tool_query context handler output status tool_args_json
	tool_name="$1"
	tool_query="$2"
	context="$3"
	tool_args_json="$4"
	handler="$(tool_handler "${tool_name}")"

	local requires_confirmation
	requires_confirmation=false
	if [[ "${tool_name}" != "final_answer" ]] && should_prompt_for_tool; then
		requires_confirmation=true
	fi

	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}" >&2
		return 1
	fi

	if [[ "${tool_name}" != "final_answer" ]]; then
		if [[ "${requires_confirmation}" == true ]]; then
			log "INFO" "Requesting tool confirmation" "$(printf 'tool=%s query=%s' "${tool_name}" "${tool_query}")" >&2
		fi

		if ! confirm_tool "${tool_name}" "${context}"; then
			printf 'Declined %s\n' "${tool_name}"
			return 0
		fi
	fi

	if [[ "${DRY_RUN}" == true || "${PLAN_ONLY}" == true ]]; then
		log "INFO" "Skipping execution in preview mode" "${tool_name}" >&2
		return 0
	fi

	local stdout_file stderr_file stderr_output
	stdout_file="$(mktemp)"
	stderr_file="$(mktemp)"

	TOOL_QUERY="${tool_query}" TOOL_ARGS="${tool_args_json}" ${handler} >"${stdout_file}" 2>"${stderr_file}"
	status=$?
	output="$(cat "${stdout_file}")"
	stderr_output="$(cat "${stderr_file}")"

	rm -f "${stdout_file}" "${stderr_file}"

	if [[ -n "${stderr_output}" ]]; then
		log "INFO" "Tool emitted stderr" "$(printf 'tool=%s stderr=%s' "${tool_name}" "${stderr_output}")" >&2
	fi
	if ((status != 0)); then
		log "WARN" "Tool reported non-zero exit" "${tool_name}" >&2
	fi

	jq -nc \
		--arg output "${output}" \
		--arg error "${stderr_output}" \
		--argjson exit_code "${status}" \
		'{output: $output, error: $error, exit_code: $exit_code}'
	return 0
}

export -f should_prompt_for_tool
export -f confirm_tool
export -f execute_tool_with_query
