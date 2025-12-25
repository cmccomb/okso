#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "normalize_planner_plan extracts JSON arrays from mixed text output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_plan=$'Here is the plan:\n[{"tool":"terminal","args":{"command":"pwd"},"thought":"check"}]\nThanks!'
normalize_planner_plan <<<"${raw_plan}" | jq -r '.[0].tool,.[0].args.command,.[0].thought'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "pwd" ]
	[ "${lines[2]}" = "check" ]
}

@test "normalize_planner_response extracts plan from mixed text output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_response=$'Preface before JSON {"mode":"plan","plan":[{"tool":"notes_create","args":{"title":"t"},"thought":"note"}]} trailing text'
normalize_planner_response <<<"${raw_response}" | jq -r '.mode,.plan[0].tool,.plan[0].args.title,.plan[0].thought,.plan[-1].tool'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "plan" ]
	[ "${lines[1]}" = "notes_create" ]
	[ "${lines[2]}" = "t" ]
	[ "${lines[3]}" = "note" ]
	[ "${lines[4]}" = "final_answer" ]
}

@test "normalize_planner_plan maps code alias to args.input" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_plan='[{"tool":"python_repl","args":{"code":"print(1)"},"thought":"run code"}]'
normalize_planner_plan <<<"${raw_plan}" | jq -r '.[0].args.input, (.[0].args|has("code"))'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "print(1)" ]
	[ "${lines[1]}" = "false" ]
}

@test "normalize_planner_plan preserves valid arg controls" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_plan='[{"tool":"notes_create","args":{"title":"t","body":"b"},"args_control":{"title":"context","body":"locked"}}]'
normalize_planner_plan <<<"${raw_plan}" | jq -r '.[0].args_control.title,.[0].args_control.body'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "context" ]
	[ "${lines[1]}" = "locked" ]
}

@test "normalize_planner_response normalizes code alias inside plan" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_response='{ "mode": "plan", "plan": [{"tool":"python_repl","args":{"code":"x=1"},"thought":"prep"}] }'
normalize_planner_response <<<"${raw_response}" | jq -r '.plan[0].args.input,.plan[0].tool,.plan[-1].tool'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "x=1" ]
	[ "${lines[1]}" = "python_repl" ]
	[ "${lines[2]}" = "final_answer" ]
}

@test "append_final_answer_step adds missing summary step without duplication" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
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

@test "normalize_planner_plan rejects unstructured outline text" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
normalize_planner_plan <<<"1) first step\n- second step"
SCRIPT

	[ "$status" -ne 0 ]
	[[ "${output}" == *"unable to parse planner output"* ]]
}
