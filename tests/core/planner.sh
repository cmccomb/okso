#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "normalize_planner_plan retains structured planner output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
raw_plan='[{"tool":"terminal","args":{"command":"ls"},"thought":"list"}]'
normalize_planner_plan <<<"${raw_plan}" | jq -r '.[0].tool,.[0].args.command,.[0].thought'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "ls" ]
	[ "${lines[2]}" = "list" ]
}

@test "normalize_planner_plan rejects unstructured outline text" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
normalize_planner_plan <<<"1) first step\n- second step"
SCRIPT

	[ "$status" -ne 0 ]
	[[ "${output}" == *"unable to parse planner output"* ]]
}

@test "normalize_planner_plan handles structured plan with missing optional fields" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
raw_plan='[{"tool":"notes_create","thought":"capture notes"}]'
normalize_planner_plan <<<"${raw_plan}"
SCRIPT

	[ "$status" -eq 0 ]
	plan_tool=$(printf '%s' "${output}" | jq -r '.[0].tool')
	plan_thought=$(printf '%s' "${output}" | jq -r '.[0].thought // ""')
	args_type=$(printf '%s' "${output}" | jq -r '.[0].args | type')

	[ "${plan_tool}" = "notes_create" ]
	[ "${plan_thought}" = "capture notes" ]
	[ "${args_type}" = "object" ]
}

@test "normalize_planner_plan rejects steps with non-object args" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
raw_plan='[{"tool":"notes_create","args":"title"}]'
normalize_planner_plan <<<"${raw_plan}"
SCRIPT

	[ "$status" -ne 0 ]
	[[ "${output}" == *"unable to parse planner output"* ]]
}

@test "normalize_planner_plan rejects steps missing rationale" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
raw_plan='[{"tool":"notes_create","args":{}}]'
normalize_planner_plan <<<"${raw_plan}"
SCRIPT

	[ "$status" -ne 0 ]
	[[ "${output}" == *"unable to parse planner output"* ]]
}

@test "normalize_planner_plan extracts JSON arrays from mixed text output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
raw_plan=$'Here is the plan:\n[{"tool":"terminal","args":{"command":"pwd"},"thought":"check"}]\nThanks!'
normalize_planner_plan <<<"${raw_plan}" | jq -r '.[0].tool,.[0].args.command,.[0].thought'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "pwd" ]
	[ "${lines[2]}" = "check" ]
}

@test "normalize_planner_plan fails on empty planner output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
normalize_planner_plan <<<""
SCRIPT

	[ "$status" -ne 0 ]
	[[ "${output}" == *"unable to parse planner output"* ]]
}

@test "append_final_answer_step adds missing summary step without duplication" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
without_final=$(append_final_answer_step "[{\"tool\":\"terminal\",\"args\":{},\"thought\":\"list\"}]")
with_final=$(append_final_answer_step "[{\"tool\":\"final_answer\",\"args\":{},\"thought\":\"done\"}]")
printf "%s\n---\n%s\n" "${without_final}" "${with_final}"
SCRIPT

	[ "$status" -eq 0 ]
	first_tools=$(printf '%s' "${lines[0]}" | jq -r '.[].tool')
	[[ "${first_tools}" == *"final_answer" ]]
	second_tools=$(printf '%s' "${lines[2]}" | jq -r '.[].tool')
	[ "${second_tools}" = "final_answer" ]
	second_thought=$(printf '%s' "${lines[2]}" | jq -r '.[0].thought')
	[ "${second_thought}" = "done" ]
}

@test "derive_allowed_tools_from_plan gathers unique tools and ensures summary" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
tool_names() { printf "%s\n" terminal notes_create final_answer; }
plan_json='[{"tool":"terminal","args":{},"thought":"choose"},{"tool":"notes_create","args":{},"thought":"capture"}]'
tools=()
while IFS= read -r line; do
        tools+=("$line")
done < <(derive_allowed_tools_from_plan "${plan_json}")
printf "%s\n" "${tools[@]}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "notes_create" ]
	[ "${lines[2]}" = "final_answer" ]
}

@test "derive_allowed_tools_from_plan unwraps planner response objects" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
tool_names() { printf "%s\n" terminal notes_create final_answer; }
response='{"mode":"plan","plan":[{"tool":"terminal","args":{},"thought":"choose"}]}'
tools=()
while IFS= read -r line; do
        tools+=("$line")
done < <(derive_allowed_tools_from_plan "${response}")
printf "%s\n" "${tools[@]}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "final_answer" ]
}

@test "derive_allowed_tools_from_plan expands react_fallback to available tools" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
tool_names() { printf "%s\n" terminal notes_create calendar_list; }
plan_json='[{"tool":"react_fallback"},{"tool":"final_answer"}]'
tools=()
while IFS= read -r line; do
        tools+=("$line")
done < <(derive_allowed_tools_from_plan "${plan_json}")
printf "%s\n" "${tools[@]}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "notes_create" ]
	[ "${lines[2]}" = "calendar_list" ]
	[ "${lines[3]}" = "final_answer" ]
}

@test "derive_allowed_tools_from_plan rejects non-plan payloads" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
invalid='{"mode":"quickdraw","quickdraw":{"final_answer":"done","rationale":"direct"}}'
derive_allowed_tools_from_plan "${invalid}" >/dev/null
SCRIPT

	[ "$status" -ne 0 ]
}

@test "derive_allowed_tools_from_plan de-duplicates web_search entries" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/lib/planning/planner.sh
tool_names() { printf "%s\n" terminal web_search final_answer; }
plan_json='[{"tool":"web_search","args":{}},{"tool":"web_search","args":{}},{"tool":"final_answer","args":{}}]'
tools=()
while IFS= read -r line; do
        tools+=("$line")
done < <(derive_allowed_tools_from_plan "${plan_json}")
printf "tools=%s\n" "${tools[*]}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "tools=web_search final_answer" ]
}

@test "plan_json_to_entries unwraps planner response objects" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
response='{"mode":"plan","plan":[{"tool":"terminal","args":{},"thought":"list"},{"tool":"final_answer","args":{},"thought":"summarize"}]}'
plan_json_to_entries "${response}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = '{"tool":"terminal","args":{},"thought":"list"}' ]
	[ "${lines[1]}" = '{"tool":"final_answer","args":{},"thought":"summarize"}' ]
}

@test "plan_json_to_entries errors on non-plan payloads" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
invalid='{"mode":"quickdraw","quickdraw":{"final_answer":"done","rationale":"direct"}}'
plan_json_to_entries "${invalid}"
SCRIPT

	[ "$status" -ne 0 ]
}

@test "select_next_action uses deterministic plan when llama disabled" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
source ./src/lib/react/react.sh
VERBOSITY=0
state_prefix=state
plan_entry=$(jq -nc --arg tool "terminal" --arg command "echo" --arg arg0 "hi" --arg thought "echo and report" '{tool:$tool,thought:$thought,args:{command:$command,args:[$arg0]}}')
plan_outline=$'1. terminal -> echo hi\n2. final_answer -> summarize'
initialize_react_state "${state_prefix}" "list files" $'terminal\nfinal_answer' "${plan_entry}" "${plan_outline}"
state_set "${state_prefix}" "max_steps" 2
USE_REACT_LLAMA=false
LLAMA_AVAILABLE=false
select_next_action "${state_prefix}" action_json
printf "%s\n" "${action_json}"
plan_index="$(state_get "${state_prefix}" "plan_index")"
pending_plan_step="$(state_get "${state_prefix}" "pending_plan_step")"
if [[ "${plan_index}" -ne 0 ]]; then
        echo "expected plan index to stay constant until execution"
        exit 1
fi

if [[ "${pending_plan_step}" -ne 0 ]]; then
        echo "expected pending plan step to be tracked"
        exit 1
fi
SCRIPT

	[ "$status" -eq 0 ]
	action_json=$(printf '%s' "${output}" | tail -n 1)
	tool=$(printf '%s' "${action_json}" | jq -r '.tool')
	command=$(printf '%s' "${action_json}" | jq -r '.args.command')
	arg0=$(printf '%s' "${action_json}" | jq -r '.args.args[0]')
	thought=$(printf '%s' "${action_json}" | jq -r '.thought')

	[ "${tool}" = "terminal" ]
	[ "${command}" = "echo" ]
	[ "${arg0}" = "hi" ]
	[ "${thought}" = "echo and report" ]
}
