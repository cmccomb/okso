#!/usr/bin/env bash
# shellcheck shell=bash
#
# Step execution helpers for the deterministic executor loop.
#
# Usage:
#   source "${BASH_SOURCE[0]%/step_runner.sh}/step_runner.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on execution failures.

EXECUTOR_STEP_RUNNER_DIR=${EXECUTOR_STEP_RUNNER_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=src/lib/core/logging.sh
source "${EXECUTOR_STEP_RUNNER_DIR}/../core/logging.sh"
# shellcheck source=src/lib/core/json_state.sh
source "${EXECUTOR_STEP_RUNNER_DIR}/../core/json_state.sh"
# shellcheck source=src/lib/executor/history.sh
source "${EXECUTOR_STEP_RUNNER_DIR}/history.sh"
# shellcheck source=src/lib/executor/dispatch.sh
source "${EXECUTOR_STEP_RUNNER_DIR}/dispatch.sh"
# shellcheck source=src/lib/executor/context_policies.sh
source "${EXECUTOR_STEP_RUNNER_DIR}/context_policies.sh"
# shellcheck source=src/lib/executor/arg_controls.sh
source "${EXECUTOR_STEP_RUNNER_DIR}/arg_controls.sh"

execute_planned_action() {
	# Executes a validated action with retries for arg infill failures.
	# Arguments:
	#   $1 - state prefix
	#   $2 - step index
	#   $3 - validated action JSON
	local state_prefix step_index action_json tool args_json thought args_after_controls
	local observation history_text web_fetch_snippets execution_status user_query plan_outline
	local observation_exit_code observation_error
	state_prefix="$1"
	step_index="$2"
	action_json="$3"

	tool="$(jq -r '.tool' <<<"${action_json}")"
	args_json="$(jq -c '.args' <<<"${action_json}")"
	thought="$(jq -r '.thought' <<<"${action_json}")"
	history_text="$(state_get_history_lines "${state_prefix}")"
	user_query="$(json_state_get_key "${state_prefix}" "user_query")"
	plan_outline="$(json_state_get_key "${state_prefix}" "plan_outline")"
	web_fetch_snippets="{}"

	prepare_tool_context_for_action \
		"${tool}" \
		"${history_text}" \
		"${user_query}" \
		"${plan_outline}" \
		"${thought}" \
		web_fetch_snippets
	if [[ -z "${web_fetch_snippets}" ]]; then
		web_fetch_snippets='{}'
	fi

	if ! args_after_controls="$(resolve_action_args "${tool}" "${args_json}" "${action_json}" "${user_query}" "${history_text}" "${plan_outline}" "${thought}")"; then
		log "ERROR" "Argument resolution failed" "${tool}" || true
		json_state_set_key "${state_prefix}" "needs_replanning" "true" || true
		json_state_set_key "${state_prefix}" "user_feedback" "Unable to validate arguments for ${tool}" || true
		return 1
	fi

	json_state_set_key "${state_prefix}" "step_started_at" "$(date +%s)" || true
	if [[ "${tool}" == "web_fetch" ]]; then
		observation="$(WEB_FETCH_SEARCH_SNIPPETS="${web_fetch_snippets}" execute_tool_with_args "${tool}" "${args_after_controls}")"
	else
		observation="$(execute_tool_with_args "${tool}" "${args_after_controls}")"
	fi
	execution_status=$?

	if ((execution_status != 0)); then
		return "${execution_status}"
	fi

	observation_exit_code="$(jq -r '.exit_code // 0' <<<"${observation}" 2>/dev/null || printf '1')"
	if [[ ! "${observation_exit_code}" =~ ^-?[0-9]+$ ]]; then
		observation_exit_code=1
	fi
	if ((observation_exit_code != 0)); then
		record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${args_after_controls}" "${observation}" "${step_index}"
		observation_error="$(jq -r '.error // empty' <<<"${observation}" 2>/dev/null || printf '')"
		json_state_set_key "${state_prefix}" "needs_replanning" "true" || true
		if [[ -n "${observation_error}" ]]; then
			json_state_set_key "${state_prefix}" "user_feedback" "Tool ${tool} failed: ${observation_error}" || true
		else
			json_state_set_key "${state_prefix}" "user_feedback" "Tool ${tool} failed with exit code ${observation_exit_code}" || true
		fi
		return "${observation_exit_code}"
	fi

	record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${args_after_controls}" "${observation}" "${step_index}"

	if [[ "${tool}" == "final_answer" ]]; then
		local final_answer_text
		json_state_set_key "${state_prefix}" "final_answer_action" "${observation}"
		if jq -e '.output != null and .exit_code != null' <<<"${observation}" >/dev/null 2>&1; then
			final_answer_text="$(jq -r '.output' <<<"${observation}")"
		else
			final_answer_text="${observation}"
		fi
		json_state_set_key "${state_prefix}" "final_answer" "${final_answer_text}"

		if [[ "${ENABLE_ANSWER_VALIDATION:-true}" == "true" ]]; then
			evaluate_and_optionally_replan "${state_prefix}" "${final_answer_text}" "false"
		else
			json_state_set_key "${state_prefix}" "validation_status" "Skipped" || true
			json_state_set_key "${state_prefix}" "validation_reason" "Answer evaluation disabled" || true
			render_step_box "Final Answer" "$(format_duration_seconds 0)" "$(format_final_answer_summary "${final_answer_text}")"
			render_step_box "Evaluation" "$(format_duration_seconds 0)" "$(format_validation_summary "Skipped" "Answer evaluation disabled")"
			json_state_set_key "${state_prefix}" "final_answer_emitted" "true"
		fi
	fi
}

export -f execute_planned_action
