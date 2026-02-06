#!/usr/bin/env bash
# shellcheck shell=bash
#
# Deterministic execution loop for planner-driven tool invocations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/loop.sh}/loop.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation or execution failures.

EXECUTOR_LIB_DIR=${EXECUTOR_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=/src/lib/core/logging.sh
source "${EXECUTOR_LIB_DIR}/../core/logging.sh"
# shellcheck source=/src/lib/core/json_state.sh
source "${EXECUTOR_LIB_DIR}/../core/json_state.sh"
# shellcheck source=src/lib/executor/history.sh
source "${EXECUTOR_LIB_DIR}/history.sh"
# shellcheck source=src/lib/executor/step_runner.sh
source "${EXECUTOR_LIB_DIR}/step_runner.sh"

executor_loop() {
	# Executes planner actions deterministically.
	# Arguments:
	#   $1 - user query
	#   $2 - allowed tools (newline delimited)
	#   $3 - planner plan entries as JSON array
	#   $4 - plan outline text
	local user_query allowed_tools plan_entries plan_outline state_prefix plan_entry step_index
	user_query="$1"
	allowed_tools="$2"
	plan_entries="$3"
	plan_outline="$4"
	state_prefix="executor_state"

	initialize_executor_state "${state_prefix}" "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"

	if [[ -z "${plan_entries}" ]]; then
		log "ERROR" "No planner actions provided" "${user_query}" >&2
		json_state_set_key "${state_prefix}" "final_answer" "Planner did not provide any executable steps."
		finalize_executor_result "${state_prefix}"
		return 1
	fi

	step_index=0

	if ! jq -e 'type == "array" and (length > 0)' <<<"${plan_entries}" >/dev/null 2>&1; then
		log "ERROR" "Planner returned no actionable steps" "${plan_entries}" >&2
		json_state_set_key "${state_prefix}" "final_answer" "Planner did not provide any executable steps."
		finalize_executor_result "${state_prefix}"
		return 1
	fi

	while IFS= read -r plan_entry || [[ -n "$plan_entry" ]]; do
		((++step_index))

		execute_planned_action "${state_prefix}" "${step_index}" "${plan_entry}"

		if [[ "$(json_state_get_key "${state_prefix}" "needs_replanning")" == "true" ]]; then
			executor_replan_with_feedback "${state_prefix}" "$(json_state_get_key "${state_prefix}" "user_feedback")"
			return $?
		fi

		if [[ -n "$(json_state_get_key "${state_prefix}" "final_answer")" ]]; then
			break
		fi
	done < <(jq -c '.[]' <<<"${plan_entries}")

	finalize_executor_result "${state_prefix}"
}

export -f executor_loop
# Backward-compatible exports for test harnesses that source loop.sh.
export -f apply_plan_arg_controls
export -f fill_missing_args_with_llm
export -f resolve_action_args
export -f execute_planned_action
