#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "normalize_planner_response accepts top-level plan arrays" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_response='[{"tool":"notes_create","args":{"title":"t"},"thought":"note"},{"tool":"final_answer","args":{"input":"done"},"thought":"reply"}]'
normalize_planner_response <<<"${raw_response}" | jq -r '.[0].tool,.[0].args.title,.[0].thought,.[1].tool,.[1].args.input'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "notes_create" ]
	[ "${lines[1]}" = "t" ]
	[ "${lines[2]}" = "note" ]
	[ "${lines[3]}" = "final_answer" ]
	[ "${lines[4]}" = "done" ]
}

@test "extract_plan_array enforces array shape" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
extract_plan_array '{"plan": "not an array"}'
SCRIPT

	[ "$status" -ne 0 ]
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
