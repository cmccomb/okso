#!/usr/bin/env bats

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
