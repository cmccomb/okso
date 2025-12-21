#!/usr/bin/env bats
#
# Tests for mapping structured JSON tool arguments to CLI flags.
#
# Usage:
#   bats tests/tools/test_tool_args_structured.sh
#
# Regression tests ensuring TOOL_ARGS drive tool handlers.

@test "final_answer requires structured TOOL_ARGS" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

chpwd_functions=()
unset -f chpwd _mise_hook 2>/dev/null || true

source ./src/tools/final_answer/index.sh

output=$(TOOL_ARGS='{"input":"structured value"}' tool_final_answer)

if [[ "${output}" != "structured value" ]]; then
        echo "final_answer did not prefer structured args"
        exit 1
fi

if TOOL_ARGS="" tool_final_answer >/dev/null 2>&1; then
        echo "final_answer unexpectedly accepted missing TOOL_ARGS"
        exit 1
fi
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "${status}" -eq 0 ]
}

@test "ReAct loop forwards structured args to custom tool" {
        script=$(
                cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

chpwd_functions=()
unset -f chpwd _mise_hook 2>/dev/null || true

source ./src/lib/planning/planner.sh
source ./src/lib/tools.sh

init_tool_registry
register_final_answer

tool_structured_echo() {
        jq -r '.input' <<<"${TOOL_ARGS}" || true
}

register_tool \
        "structured_echo" \
        "Echo back structured input for testing." \
        "structured_echo '<input>'" \
        "Test helper tool." \
        tool_structured_echo \
        '{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}},"additionalProperties":false}'

llama_queue=$(mktemp)
printf '%s\n' '{"thought":"run it","tool":"structured_echo","args":{"input":"beep"}}' '{"thought":"wrap up","tool":"final_answer","args":{"input":"done"}}' >"${llama_queue}"
llama_infer() {
        local next remaining
        next=$(head -n 1 "${llama_queue}" || printf '{}')
        remaining=$(tail -n +2 "${llama_queue}" 2>/dev/null || true)
        printf '%s' "${remaining}" >"${llama_queue}"
        printf '%s' "${next}"
}

allowed_tools=$'structured_echo\nfinal_answer'
plan_entries=""
plan_outline=$'1. run structured_echo\n2. wrap up'
state_prefix=react_state

initialize_react_state "${state_prefix}" "demo" "${allowed_tools}" "${plan_entries}" "${plan_outline}"

USE_REACT_LLAMA=true
LLAMA_AVAILABLE=true
VERBOSITY=0
MAX_STEPS=3
APPROVE_ALL=true
PLAN_ONLY=false
DRY_RUN=false
FORCE_CONFIRM=false

select_next_action "${state_prefix}" first_action
tool_one=$(jq -r '.tool' <<<"${first_action}")
args_one=$(jq -c '.args' <<<"${first_action}")
observation_one=$(execute_tool_action "${tool_one}" "beep" "ctx" "${args_one}")

select_next_action "${state_prefix}" second_action
tool_two=$(jq -r '.tool' <<<"${second_action}")
args_two=$(jq -c '.args' <<<"${second_action}")
observation_two=$(execute_tool_action "${tool_two}" "legacy" "ctx" "${args_two}")

if [[ "$(jq -r '.output' <<<"${observation_one}")" != "beep" ]]; then
        echo "unexpected first observation: ${observation_one}"
        exit 1
fi

if [[ "$(jq -r '.output' <<<"${observation_two}")" != "done" ]]; then
        echo "unexpected second observation: ${observation_two}"
        exit 1
fi
rm -f "${llama_queue}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "${status}" -eq 0 ]
}
