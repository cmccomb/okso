#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "normalize_planner_response accepts canonical object payloads" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_response='{ "plan": [{"tool":"notes_create","args":{"title":"t"},"thought":"note"}] }'
normalize_planner_response <<<"${raw_response}" | jq -r '.plan[0].tool,.plan[0].args.title,.plan[0].thought,.plan[-1].tool,.plan[-1].args.input'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "notes_create" ]
	[ "${lines[1]}" = "t" ]
	[ "${lines[2]}" = "note" ]
	[ "${lines[3]}" = "final_answer" ]
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

@test "normalize_planner_response normalizes code alias inside plan" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_response='{ "plan": [{"tool":"python_repl","args":{"code":"x=1"},"thought":"prep"}] }'
normalize_planner_response <<<"${raw_response}" | jq -r '.plan[0].args.input,.plan[0].tool,.plan[-1].tool'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "x=1" ]
	[ "${lines[1]}" = "python_repl" ]
	[ "${lines[2]}" = "final_answer" ]
}

@test "extract_plan_array handles bare plan arrays" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_plan='[{"tool":"terminal","args":{"command":"ls"},"thought":"list"}]'
extract_plan_array "${raw_plan}" | jq -r '.[0].tool'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
}

@test "normalize_planner_response fails cleanly on empty output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
normalize_planner_response <<<"" 
SCRIPT

	[ "$status" -ne 0 ]
	[[ "${output}" == *"planner_output_empty"* ]]
}
