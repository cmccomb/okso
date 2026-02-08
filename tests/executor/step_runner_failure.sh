#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for step_runner_failure.sh.

@test "execute_planned_action marks replanning when tool observation exit_code is non-zero" {
	run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/executor/loop.sh
source ./src/tools/registry.sh

init_tool_registry

failing_tool() {
	echo "simulated failure" >&2
	return 1
}
register_tool "failing_tool" "fails intentionally" failing_tool '{"type":"object","additionalProperties":false}'

state_prefix="executor_state"
plan_entries='[{"tool":"failing_tool","args":{},"thought":"trigger failure"}]'
allowed_tools=$'failing_tool\nfinal_answer'
initialize_executor_state "${state_prefix}" "query" "${allowed_tools}" "${plan_entries}" "1. trigger failure"

action='{"tool":"failing_tool","args":{},"thought":"trigger failure"}'
result=0
execute_planned_action "${state_prefix}" "1" "${action}" || result=$?

echo "result=${result}"
echo "needs_replanning=$(json_state_get_key "${state_prefix}" "needs_replanning")"
echo "user_feedback=$(json_state_get_key "${state_prefix}" "user_feedback")"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" == *"result=1"* ]]
	[[ "$output" == *"needs_replanning=true"* ]]
	[[ "$output" == *"Tool failing_tool failed"* ]]
}

@test "evaluate_and_optionally_replan falls back when evaluator output is non-conforming" {
	run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/executor/loop.sh

state_prefix="executor_state"
allowed_tools='final_answer'
plan_entries='[{"tool":"final_answer","args":{"input":"seed"},"thought":"done"}]'
initialize_executor_state "${state_prefix}" "query" "${allowed_tools}" "${plan_entries}" "1. done"

evaluate_final_answer_against_query() { printf '"unterminated'; return 0; }
export -f evaluate_final_answer_against_query

result=0
evaluate_and_optionally_replan "${state_prefix}" "tool output" "false" || result=$?

echo "result=${result}"
echo "final_answer=$(json_state_get_key "${state_prefix}" "final_answer")"
echo "validation_status=$(json_state_get_key "${state_prefix}" "validation_status")"
echo "validation_reason=$(json_state_get_key "${state_prefix}" "validation_reason")"
echo "final_answer_emitted=$(json_state_get_key "${state_prefix}" "final_answer_emitted")"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" == *"result=0"* ]]
	[[ "$output" == *"final_answer=tool output"* ]]
	[[ "$output" == *"validation_status=Accepted"* ]]
	[[ "$output" == *"non-conforming output"* ]]
	[[ "$output" == *"final_answer_emitted=false"* ]]
}
