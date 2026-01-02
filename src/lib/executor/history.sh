#!/usr/bin/env bash
# shellcheck shell=bash
#
# State and history helpers for the executor loop.
#
# Usage:
#   source "${BASH_SOURCE[0]%/history.sh}/history.sh"
#
# Environment variables:
#   MAX_STEPS (int): maximum number of executor turns; default: 6.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on state failures.

EXECUTOR_LIB_DIR=${EXECUTOR_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=../core/logging.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/logging.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/state.sh"
# shellcheck source=../formatting.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../formatting.sh"
# shellcheck source=../validation/validation.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../validation/validation.sh"

initialize_executor_state() {
	# Initializes the executor state document with user query, tools, and plan.
	# Arguments:
	#   $1 - state prefix to populate (string)
	#   $2 - user query (string)
	#   $3 - allowed tools (string, newline delimited)
	#   $4 - ranked plan entries (string)
	#   $5 - plan outline text (string)
	local state_prefix
	state_prefix="$1"

	state_set_json_document "${state_prefix}" "$(jq -c -n \
		--arg user_query "$2" \
		--arg allowed_tools "$3" \
		--arg plan_entries "$4" \
		--arg plan_outline "$5" \
		--argjson max_steps "${MAX_STEPS:-6}" \
		'{
                        user_query: $user_query,
                        allowed_tools: $allowed_tools,
                        plan_entries: $plan_entries,
                        plan_outline: $plan_outline,
                        history: [],
                        step: 0,
                        plan_index: 0,
                        max_steps: $max_steps,
                        final_answer: "",
                        final_answer_action: "",
                        last_action: null
                }')"
}

record_history() {
	# Appends a formatted history entry to the executor state.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - formatted history entry (string)
	local entry
	entry="$2"
	state_append_history "$1" "${entry}"
}

state_get_history_lines() {
	# Retrieves history as a newline-delimited string.
	# Arguments:
	#   $1 - state prefix (string)
	# Returns:
	#   Newline-delimited string of history entries.
	local state_prefix history_raw
	state_prefix="$1"
	history_raw="$(state_get "${state_prefix}" "history")"

	if jq -e 'type == "array"' <<<"${history_raw}" >/dev/null 2>&1; then
		jq -r '.[]' <<<"${history_raw}"
		return 0
	fi

	printf '%s' "${history_raw}"
}

record_tool_execution() {
	# Records a tool execution into history.
	# Arguments:
	#   $1 - state prefix
	#   $2 - tool name
	#   $3 - thought text
	#   $4 - args JSON
	#   $5 - observation text
	#   $6 - step index
	local state_name
	local tool thought args_json observation step_index entry observation_json
	state_name="$1"
	tool="$2"
	thought="$3"
	args_json="$4"
	observation="$5"
	step_index="$6"

	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi

	args_json="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"

	if observation_json=$(jq -c '.' <<<"${observation}" 2>/dev/null); then
		observation_json_value="${observation_json}"
	else
		observation_json_value="null"
	fi

	entry=$(
		jq -c -n \
			--arg step "${step_index}" \
			--arg thought "${thought}" \
			--arg tool "${tool}" \
			--argjson args "${args_json}" \
			--arg observation_raw "${observation}" \
			--argjson observation_json "${observation_json_value}" \
			'{
                  step: ($step | tonumber // 0),
                  thought: $thought,
                  action: {tool: $tool, args: $args},
                  observation: (if ($observation_json | type) == "null" then $observation_raw else $observation_json end)
                }'
	) || return 1

	record_history "${state_name}" "${entry}"
	log "INFO" "Recorded tool execution" "$(printf 'step=%s tool=%s' "${step_index}" "${tool}")"
}

finalize_executor_result() {
	# Finalizes and emits the executor run result.
	# Arguments:
	#   $1 - state prefix
	local state_name observation final_answer_action needs_replanning user_feedback
	local final_answer
	state_name="$1"

	needs_replanning="$(state_get "${state_name}" "needs_replanning" 2>/dev/null || echo "")"
	if [[ "${needs_replanning}" == "true" ]]; then
		user_feedback="$(state_get_json_document "${state_name}" | jq -r '.user_feedback // empty' 2>/dev/null || echo "")"
		if [[ -n "${user_feedback}" ]]; then
			log "INFO" "Replanning with user feedback" "feedback=${user_feedback}"
			jq -nc --arg feedback "${user_feedback}" '{status: "feedback_received", feedback: $feedback}'
			return 0
		fi
	fi

	observation="$(state_get "${state_name}" "final_answer" 2>/dev/null || echo "")"
	final_answer_action="$(state_get "${state_name}" "final_answer_action" 2>/dev/null || echo "")"

	if [[ -n "${observation}" ]]; then
		if jq -e '.output != null and .exit_code != null' <<<"${observation}" >/dev/null 2>&1; then
			final_answer="$(jq -r '.output' <<<"${observation}")"
		else
			final_answer="${observation}"
		fi
	elif [[ -n "${final_answer_action}" ]]; then
		final_answer="${final_answer_action}"
	else
		final_answer=""
	fi

	state_set "${state_name}" "final_answer" "${final_answer}"

	if [[ "${ENABLE_ANSWER_VALIDATION:-true}" == "true" ]]; then
		validate_and_optionally_replan "${state_name}" "${final_answer}"
		return $?
	fi

	log_pretty "INFO" "Final answer" "${final_answer}"
	if [[ -z "$(format_tool_history "$(state_get_history_lines "${state_name}")")" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "$(format_tool_history "$(state_get_history_lines "${state_name}")")"
	fi

	emit_boxed_summary \
		"$(state_get "${state_name}" "user_query")" \
		"$(state_get "${state_name}" "plan_outline")" \
		"$(state_get_history_lines "${state_name}")" \
		"${final_answer}"
}

validate_and_optionally_replan() {
	# Validates a final answer against the original query and optionally triggers replanning.
	# Uses the 8B validator model to check if the answer satisfies the user's request.
	# If validation fails, logs the reason and optionally signals for replanning.
	#
	# Arguments:
	#   $1 - state prefix
	#   $2 - final answer text
	#
	# Returns:
	#   0 if validation passes, 1 if fails but continues, 2 on validation error
	local state_name final_answer user_query history_text validation_result validation_status
	state_name="$1"
	final_answer="$2"
	user_query="$(state_get "${state_name}" "user_query")"
	history_text="$(state_get_history_lines "${state_name}")"

	log "INFO" "Running final answer validation" || true

	# Call the validation function with output to a variable
	if ! validation_result="$(validate_final_answer_against_query "${user_query}" "${final_answer}" "${history_text}")"; then

		log "INFO" "Validation results" "${validation_result}"

		validation_status=$?

		if [[ ${validation_status} -eq 1 ]]; then
			# Validation indicates answer does NOT satisfy query
			log "WARN" "Final answer validation failed; answer may not satisfy query" || true

			# Extract reasoning if available
			local reasoning
			reasoning="$(jq -r '.reasoning // "Unknown reason"' <<<"${validation_result}" 2>/dev/null || echo "Validation failed to provide reasoning")"

			log "INFO" "Validation reasoning" "${reasoning}" || true
			log_pretty "WARN" "validation_failure_reason" "${reasoning}" || true

			# Log the failed validation result for debugging
			log_pretty "DEBUG" "validation_result" "${validation_result}" || true

			# Set a flag to indicate replanning may be beneficial
			state_set "${state_name}" "answer_validation_failed" "true" || true
			state_set "${state_name}" "validation_failure_reason" "${reasoning}" || true

			# Continue with outputting the answer, but mark that it didn't pass validation
			log "INFO" "Continuing with unvalidated answer; consider iterative replanning" || true
		else
			# Validation infrastructure error (not a validation failure)
			log "WARN" "Answer validation check encountered an error; outputting answer as-is" || true
		fi
	else
		# Validation passed
		log "INFO" "Final answer passed validation" || true
		log_pretty "INFO" "validation_result" "${validation_result}" || true
	fi

	# Output the final answer regardless of validation status
	log_pretty "INFO" "Final answer" "${final_answer}"
	if [[ -z "$(format_tool_history "${history_text}")" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "$(format_tool_history "${history_text}")"
	fi

	emit_boxed_summary \
		"${user_query}" \
		"$(state_get "${state_name}" "plan_outline")" \
		"${history_text}" \
		"${final_answer}"
}

export -f validate_and_optionally_replan
