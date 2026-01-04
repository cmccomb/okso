#!/usr/bin/env bats

@test "fill_missing_args_with_llm fails cleanly on invalid llama json" {
        run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/loop.sh
LLAMA_AVAILABLE=true
render_prompt_template() { echo "prompt"; }
tool_args_schema() { echo '{"type":"object","properties":{"input":{"type":"string"}},"required":["input"]}'; }
llama_infer() { echo '"unterminated'; }
result=0
fill_missing_args_with_llm "final_answer" "{}" "query" "outline" "thought" "" '["input"]' || result=$?
echo "result=${result}"
SCRIPT

	[ "$status" -eq 0 ]
        [[ "$output" == *"result=1"* ]]
        [[ "$output" != *"jq: parse error"* ]]
}

@test "apply_plan_arg_controls treats fill marker as context controlled" {
        run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/loop.sh
tool_args_schema() { echo '{"type":"object","properties":{"count":{"type":"number","minimum":1}},"required":["count"]}'; }
plan_entry='{"tool":"demo","args":{"count":"<<FILL_DURING_EXECUTION>>","note":"keep"}}'
output="$(apply_plan_arg_controls "demo" '{}' "${plan_entry}" "" "")"
echo "${output}"
SCRIPT

        [ "$status" -eq 0 ]
        json_output="$(printf '%s\n' "$output" | tail -n 1)"
        echo "$json_output" | jq -e 'has("__context_controlled")' >/dev/null
        echo "$json_output" | jq -e '."__context_controlled"==["count"]' >/dev/null
        echo "$json_output" | jq -e '.count == "<<FILL_DURING_EXECUTION>>"' >/dev/null
        echo "$json_output" | jq -e '.note == "keep"' >/dev/null
}
