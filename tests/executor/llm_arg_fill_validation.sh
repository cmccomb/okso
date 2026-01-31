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
plan_entry='{"tool":"demo","args":{"count":"$Q","note":"keep"}}'
output="$(apply_plan_arg_controls "demo" '{}' "${plan_entry}" "" "")"
echo "${output}"
SCRIPT

	[ "$status" -eq 0 ]
	json_output="$(printf '%s\n' "$output" | tail -n 1)"
	echo "$json_output" | jq -e 'has("__context_controlled")' >/dev/null
	echo "$json_output" | jq -e '."__context_controlled"==["count"]' >/dev/null
	echo "$json_output" | jq -e '.count == "$Q"' >/dev/null
	echo "$json_output" | jq -e '.note == "keep"' >/dev/null
}

@test "fill_missing_args_with_llm summarizes web_fetch history before prompt" {
	run env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/loop.sh
LLAMA_AVAILABLE=true
tool_args_schema() { echo '{"type":"object","properties":{"input":{"type":"string"}},"required":["input"]}'; }
render_prompt_template() {
	local prompt_name history_text
	prompt_name="$1"
	shift
	while (($# > 0)); do
		if [[ "$1" == "history_text" ]]; then
			history_text="$2"
		fi
		shift 2
	done
	printf 'History:\n%s' "${history_text}"
}
llama_infer() {
	printf '%s' "$1" >"${TMPDIR}/executor_prompt.txt"
	printf '{}'
}
large_body="LONG_BODY_TOKEN_$(printf 'A%.0s' {1..200})"
history_entry=$(jq -nc --arg large "${large_body}" '{
	step: 1,
	thought: "fetching",
	action: {tool: "web_fetch", args: {url: "https://example.com"}},
	observation: {
		url: "https://example.com",
		final_url: "https://example.com",
		status: 200,
		content_type: "text/html",
		headers: "X-Test: 1",
		body_snippet: "short snippet",
		body_markdown: $large,
		anchor_query: "short",
		anchor_match: true
	}
}')
history_safe="$(build_prompt_safe_history "${history_entry}")"
fill_missing_args_with_llm "final_answer" "{}" "query" "outline" "thought" "${history_safe}" '["input"]' >/dev/null
cat "${TMPDIR}/executor_prompt.txt"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" != *"X-Test"* ]]
	[[ "$output" != *"LONG_BODY_TOKEN"* ]]
	[[ "$output" == *"short snippet"* ]]
}
