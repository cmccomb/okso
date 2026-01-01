#!/usr/bin/env bats
#
# Regression tests for executor action validation and selection.
#
# Usage:
#   bats tests/planner/test_executor_action.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "fill_missing_args_with_llm renders executor template" {
        script=$(
                cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

prompt_log="$(mktemp)"
prompt_capture="${prompt_log}.prompt"
trap 'rm -f "${prompt_log}" "${prompt_capture}"' EXIT

source ./src/lib/executor/loop.sh

render_prompt_template() {
        printf 'executor:%s' "$*" >"${prompt_log}"
        printf 'stubbed executor prompt'
}
export -f render_prompt_template

tool_args_schema() { printf '{"type":"object"}'; }
export -f tool_args_schema

llama_infer() {
        cat >"${prompt_capture}" <<<"$1"
        printf '{"args":{"filled":true}}'
}
export -f llama_infer

LLAMA_AVAILABLE=true

output="$(fill_missing_args_with_llm "demo_tool" '{"input":"provided"}' "user wants" "a plan" "planner note" "" '["input"]')"

grep -F 'stubbed executor prompt' "${prompt_capture}"
grep -F 'executor:executor tool demo_tool user_query user wants plan_outline a plan planner_thought planner note args_json {"input":"provided"} args_schema {"type":"object"} context_fields ["input"]' "${prompt_log}"
[[ "${output}" == '{"args":{"filled":true}}' ]]
INNERSCRIPT
	)

        run bash -lc "${script}"
        [ "$status" -eq 0 ]
}

@test "resolve_action_args trusts schema contract for required args" {
        script=$(
                cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/executor/loop.sh

tool_args_schema() { printf '{"type":"object","required":["input"]}'; }
export -f tool_args_schema

output="$(resolve_action_args "demo_tool" '{}' '{}' 'user query' '' '' '')"

[[ "${output}" == '{}' ]]
INNERSCRIPT
        )

        run bash -lc "${script}"
        [ "$status" -eq 0 ]
}
