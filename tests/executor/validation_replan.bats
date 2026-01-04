#!/usr/bin/env bats
#
# Tests for validation-driven replanning in the executor.
#
# Usage:
#   bats tests/executor/validation_replan.bats
#
# Dependencies:
#   - bats
#   - bash 3.2+

setup() {
	cd "$(git rev-parse --show-toplevel)" || exit 1
	unset VALIDATION_REPLAN_ATTEMPTED
}

@test "validator approval does not trigger replanning" {
	source ./src/lib/executor/history.sh
	initialize_executor_state "executor_state" "query" "" "[]" "outline"

	called_replan=false
	validate_final_answer_against_query() {
		echo '{"satisfied":true,"reasoning":"looks good"}'
		return 0
	}
	generate_planner_response() {
		called_replan=true
		echo '{}'
	}
	derive_allowed_tools_from_plan() { echo "terminal"; }
	plan_json_to_entries() { echo '[]'; }
	plan_json_to_outline() { echo "outline"; }
	executor_loop() { return 0; }

	validate_and_optionally_replan "executor_state" "final answer"

	[ "${called_replan}" = false ]
	[ "$(json_state_get_key "executor_state" "answer_validation_failed")" = "" ]
}

@test "validator rejection triggers planner rerun with feedback" {
	source ./src/lib/executor/history.sh
	initialize_executor_state "executor_state" "query" "old_tool" "[]" "old outline"

	feedback_capture_path="${BATS_TMPDIR}/replan_feedback.txt"
	captured_plan_outline=""
	captured_allowed_tools=""
	captured_plan_entries=""

	validate_final_answer_against_query() {
		echo '{"satisfied":0,"reasoning":"Need more citations."}'
		return 0
	}
	generate_planner_response() {
		printf '%s' "${PLANNER_FEEDBACK_CONTEXT}" >"${feedback_capture_path}"
		echo '{"plan":[{"tool":"final_answer","args":{"input":""},"thought":"respond"}]}'
	}
	derive_allowed_tools_from_plan() { echo "python_repl"; }
	plan_json_to_entries() { echo '[{"tool":"final_answer","args":{"input":""},"thought":"respond"}]'; }
	plan_json_to_outline() { echo "New outline"; }
	executor_loop() {
		captured_plan_outline="$4"
		captured_allowed_tools="$2"
		captured_plan_entries="$3"
		initialize_executor_state "executor_state" "$1" "$2" "$3" "$4"
		json_state_set_key "executor_state" "final_answer" "replanned answer"
	}

	validate_and_optionally_replan "executor_state" "initial answer"
	status=$?
	[ "$status" -eq 0 ]
	captured_feedback="$(cat "${feedback_capture_path}")"
	[ "${captured_feedback}" = "Need more citations." ]
	[ "${captured_plan_outline}" = "New outline" ]
	[ "${captured_allowed_tools}" = "python_repl" ]
	[ "${captured_plan_entries}" = '[{"tool":"final_answer","args":{"input":""},"thought":"respond"}]' ]
	[ "$(json_state_get_key "executor_state" "plan_outline")" = "New outline" ]
	[ "$(json_state_get_key "executor_state" "history")" = "[]" ]
}

@test "validator infra failure falls back to current behavior" {
	source ./src/lib/executor/history.sh
	initialize_executor_state "executor_state" "query" "" "[]" "outline"

	validate_final_answer_against_query() {
		echo '{"satisfied":0,"reasoning":"unreachable"}'
		return 42
	}
	generate_planner_response() { echo '{}'; }
	derive_allowed_tools_from_plan() { echo ""; }
	plan_json_to_entries() { echo '[]'; }
	plan_json_to_outline() { echo ""; }
	executor_loop() { return 0; }

	validate_and_optionally_replan "executor_state" "final answer"
	status=$?
	[ "$status" -eq 0 ]
	[ "$(json_state_get_key "executor_state" "answer_validation_failed")" = "" ]
}
