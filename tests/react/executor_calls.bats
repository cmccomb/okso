#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "apply_plan_arg_controls fills context args and locks planner values" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

tool_args_schema() {
        printf '{"properties":{"title":{"type":"string"},"body":{"type":"string"}}}'
}

plan_entry='{"tool":"notes_create","args":{"title":"Planner Title","body":"Original body"},"args_control":{"title":"locked","body":"context"}}'
executor_args='{"title":"User Title","body":"__MISSING__"}'
user_query='Provide meeting summary'
resolved=$(apply_plan_arg_controls "notes_create" "${executor_args}" "${plan_entry}" "${user_query}" "__MISSING__")
jq -r '.title,.body' <<<"${resolved}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Planner Title" ]
	[ "${lines[1]}" = "Provide meeting summary" ]
}

@test "validate_planner_action rejects disallowed tools" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh
allowed_tools=$'notes_create\nfinal_answer'
if validate_planner_action '{"tool":"unknown","args":{}}' "${allowed_tools}" 2>/tmp/validation_err; then
        exit 1
fi
cat /tmp/validation_err
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"not permitted"* ]]
}

@test "fill_missing_args_with_llm uses llama output for missing args" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh
LLAMA_AVAILABLE=true
llama_infer() {
        printf '{"title":"Filled title","body":"Filled body"}'
}
tool_args_schema() {
        printf '{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"}}}'
}
filled=$(fill_missing_args_with_llm "notes_create" '{"title":"__MISSING__","body":"__MISSING__"}' "User question" "Outline" "Planner thought")
jq -r '.title,.body' <<<"${filled}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "Filled title" ]
	[ "${lines[1]}" = "Filled body" ]
}
