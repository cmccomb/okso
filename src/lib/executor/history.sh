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
# shellcheck source=../core/json_state.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/json_state.sh"
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

	# Initialize the JSON state document
	json_state_set_document "${state_prefix}" "$(jq -c -n \
		--arg user_query "$2" \
		--arg allowed_tools "$3" \
		--arg plan_entries "$4" \
		--arg plan_outline "$5" \
		'{
                        user_query: $user_query,
                        allowed_tools: $allowed_tools,
                        plan_entries: $plan_entries,
                        plan_outline: $plan_outline,
                        history: [],
                        step: 0,
                        plan_index: 0,
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

	# Append to history array in state
	json_state_append_history "$1" "${entry}"
}

state_get_history_lines() {
	# Retrieves history as a newline-delimited string.
	# Arguments:
	#   $1 - state prefix (string)
	# Returns:
	#   Newline-delimited string of history entries.
	local state_prefix history_raw
	state_prefix="$1"

	# Fetch history array from state
	history_raw="$(json_state_get_key "${state_prefix}" "history")"

	# Format history as newline-delimited string
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

	# Normalize args JSON
	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi

	# Ensure args_json is valid JSON
	args_json="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"

	# Attempt to parse observation as JSON
	if observation_json=$(jq -c '.' <<<"${observation}" 2>/dev/null); then
		observation_json_value="${observation_json}"
	else
		observation_json_value="null"
	fi

	# Build history entry
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

	# Append entry to history and log
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

	# Check if replanning is needed due to user feedback
	needs_replanning="$(json_state_get_key "${state_name}" "needs_replanning" 2>/dev/null || echo "")"

	# If replanning is needed, check for user feedback
	if [[ "${needs_replanning}" == "true" ]]; then
		user_feedback="$(json_state_get_document "${state_name}" | jq -r '.user_feedback // empty' 2>/dev/null || echo "")"
		if [[ -n "${user_feedback}" ]]; then
			log "INFO" "Replanning with user feedback" "feedback=${user_feedback}"
			jq -nc --arg feedback "${user_feedback}" '{status: "feedback_received", feedback: $feedback}'
			return 0
		fi
	fi

	# Determine final answer from state
	observation="$(json_state_get_key "${state_name}" "final_answer" 2>/dev/null || echo "")"
	final_answer_action="$(json_state_get_key "${state_name}" "final_answer_action" 2>/dev/null || echo "")"

	# Prioritize observation if valid
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

	# Store final answer back into state
	json_state_set_key "${state_name}" "final_answer" "${final_answer}"

	# Validate final answer if enabled
	if [[ "${ENABLE_ANSWER_VALIDATION:-true}" == "true" ]]; then
		validate_and_optionally_replan "${state_name}" "${final_answer}"
		return $?
	fi

	# Emit final answer and summary
	log_pretty "INFO" "Final answer" "${final_answer}"
	if [[ -z "$(format_tool_history "$(state_get_history_lines "${state_name}")")" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "$(format_tool_history "$(state_get_history_lines "${state_name}")")"
	fi

	# Emit boxed summary
	emit_boxed_summary \
		"$(json_state_get_key "${state_name}" "user_query")" \
		"$(json_state_get_key "${state_name}" "plan_outline")" \
		"$(state_get_history_lines "${state_name}")" \
		"${final_answer}"
}

validate_and_optionally_replan() {
	# Args:
	#   $1 - state prefix
	#   $2 - final answer text
	local state_name final_answer user_query history_text
	local validation_json validator_rc satisfied reasoning
	local history_pretty
	state_name="$1"
	final_answer="$2"

	# Fetch user query and history
	user_query="$(json_state_get_key "${state_name}" "user_query")"
	history_text="$(state_get_history_lines "${state_name}")"

	# Run final answer validation
	log "INFO" "Running final answer validation" || true

	# Always capture output; keep exit code separately.
	validation_json="$(validate_final_answer_against_query "${user_query}" "${final_answer}" "${history_text}")"
	validator_rc=$?

	# Interpret validation result
	if [[ ${validator_rc} -ne 0 ]]; then
		# Validator infra failure: we got *some* output (maybe), but tool failed.
		log "WARN" "Answer validation check encountered an error; outputting answer as-is" "rc=${validator_rc}" || true
		if [[ -n "${validation_json}" ]]; then
			log_pretty "DEBUG" "validation_output" "${validation_json}" || true
		fi
	else
		# Validator ran successfully; interpret result.
		# Accept satisfied as bool or int; default to null.
		satisfied="$(
			jq -r '
        if (.satisfied|type)=="boolean" then (if .satisfied then 1 else 0 end)
        elif (.satisfied|type)=="number" then (if .satisfied!=0 then 1 else 0 end)
        else null end
      ' <<<"${validation_json}" 2>/dev/null
		)"

		# Extract reasoning if present
		reasoning="$(
			jq -r '.reasoning // empty' <<<"${validation_json}" 2>/dev/null
		)"

		log_pretty "INFO" "validation_result" "${validation_json}" || true

		# Handle validation outcome
		if [[ "${satisfied}" == "0" ]]; then
			log "WARN" "Final answer did not satisfy query per validator" || true

			# Persist flags for caller / UI
			json_state_set_key "${state_name}" "answer_validation_failed" "true" || true
			if [[ -n "${reasoning}" ]]; then
				json_state_set_key "${state_name}" "validation_failure_reason" "${reasoning}" || true
				log_pretty "WARN" "validation_failure_reason" "${reasoning}" || true
			else
				json_state_set_key "${state_name}" "validation_failure_reason" "Unknown reason" || true
			fi
		elif [[ "${satisfied}" == "1" ]]; then
			log "INFO" "Final answer passed validation" || true
		else
			# Unexpected schema/content: treat as infra-ish warning.
			log "WARN" "Validator returned unexpected schema; outputting answer as-is" || true
		fi
	fi

	# Emit final answer regardless.
	history_pretty="$(format_tool_history "${history_text}")"
	log_pretty "INFO" "Final answer" "${final_answer}"

	if [[ -z "${history_pretty}" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "${history_pretty}"
	fi

	emit_boxed_summary \
		"${user_query}" \
		"$(json_state_get_key "${state_name}" "plan_outline")" \
		"${history_text}" \
		"${final_answer}"
}

export -f validate_and_optionally_replan
