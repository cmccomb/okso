#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "plan_json_to_outline numbers steps from raw planner text" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
raw_plan='[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"final_answer","args":{},"thought":"wrap up"}]'
plan_json_to_outline "${raw_plan}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "1. list" ]
	[ "${lines[1]}" = "2. wrap up" ]
}

@test "build_planner_prompt_with_tools injects tool descriptions when provided" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
prompt=$(build_planner_prompt_with_tools "find files" terminal notes_create)
printf '%s' "${prompt}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"terminal"* ]]
	[[ "${output}" == *"notes_create"* ]]
}
