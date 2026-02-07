#!/usr/bin/env bats
# shellcheck shell=bash

@test "evaluate_final_answer_against_query fails cleanly on invalid evaluator json" {
	run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/validation/validation.sh

LLAMA_AVAILABLE=true

render_prompt_template() { echo "prompt"; }
load_schema_text() { echo '{"type":"object"}'; }
llama_infer() { echo '"unterminated'; }

result=0
evaluate_final_answer_against_query "query" "trace" >/tmp/okso_eval.out || result=$?
echo "result=${result}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" == *"result=2"* ]]
	[[ "$output" != *"jq: parse error"* ]]
}

@test "evaluate_final_answer_against_query uses context-budgeted trace in prompt" {
	run env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/validation/validation.sh

LLAMA_AVAILABLE=true
prompt_capture="$(mktemp)"
export PROMPT_CAPTURE="${prompt_capture}"

render_prompt_template() {
	local prompt_name trace
	prompt_name="$1"
	shift
	while (($# > 0)); do
		if [[ "$1" == "trace" ]]; then
			trace="$2"
		fi
		shift 2
	done
	printf 'Prompt:%s Trace:%s' "${prompt_name}" "${trace}"
}

apply_prompt_context_budget() { printf 'SAFE_TRACE'; }
load_schema_text() { echo '{"type":"object"}'; }
llama_infer() {
	printf '%s' "$1" >"${PROMPT_CAPTURE}"
	echo '{"evaluation_type":"FINAL","reasoning":"good output","output":"done answer"}'
}

result_json="$(evaluate_final_answer_against_query "query" "RAW_TRACE")"
cat "${PROMPT_CAPTURE}"
echo
echo "${result_json}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" == *"Trace:SAFE_TRACE"* ]]
	[[ "$output" == *'"evaluation_type":"FINAL"'* ]]
}
