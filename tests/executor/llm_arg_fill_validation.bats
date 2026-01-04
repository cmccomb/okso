#!/usr/bin/env bats

setup() {
        cd "$(git rev-parse --show-toplevel)" || exit 1
}

@test "executor retries and aborts on non-object LLM replies" {
run env -i HOME="$HOME" PATH="$PATH" BATS_TMPDIR="${BATS_TMPDIR}" LLAMA_AVAILABLE=true VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source ./src/lib/executor/loop.sh
source ./src/lib/executor/history.sh
source ./src/tools/registry.sh

LLAMA_AVAILABLE=true

init_tool_registry
register_tool "schema_tool" "desc" "" "noop_handler" "$(jq -nc '{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}},"additionalProperties":false}')"

noop_handler() { echo "should not run"; }
export -f noop_handler

call_log="${BATS_TMPDIR}/llama_calls.txt"
: >"${call_log}"
llama_infer() { echo '"not an object"' >>"${call_log}"; echo '"not an object"'; }
export -f llama_infer

execute_tool_with_query() { echo '{"output":"executed","error":"","exit_code":0}'; }

initialize_executor_state "executor_state" "user query" "schema_tool" "[{\"tool\":\"schema_tool\",\"args\":{\"input\":\"\"},\"thought\":\"fill\"}]" "outline"
action_entry='{"tool":"schema_tool","args":{"input":""},"thought":"fill"}'

set +e
execute_planned_action "executor_state" 1 "${action_entry}"
status=$?
set -e

printf 'status=%s\n' "${status}"
printf 'llama_calls=%s\n' "$(wc -l <"${call_log}")"
printf 'needs_replanning=%s\n' "$(json_state_get_key "executor_state" "needs_replanning")"
exit "${status}"
SCRIPT

[ "$status" -ne 0 ]
[[ "${output}" == *"llama_calls=2"* ]]
[[ "${output}" == *"needs_replanning=true"* ]]
        [[ "${output}" != *"executed"* ]]
}
