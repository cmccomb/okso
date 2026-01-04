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
