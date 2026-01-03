#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "plan_json_to_outline numbers steps from raw planner text" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
raw_plan='[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"wrap up"}]'
plan_json_to_outline "${raw_plan}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "1. list" ]
	[ "${lines[1]}" = "2. wrap up" ]
}

@test "plan_json_to_outline requires array payloads" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
response='[{"tool":"terminal","args":{"command":"ls"},"thought":"step one"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"finish"}]'
plan_json_to_outline "${response}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "1. step one" ]
	[ "${lines[1]}" = "2. finish" ]
}

@test "build_planner_prompt_with_tools injects tool descriptions when provided" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
tool_description() { printf "desc-%s" "$1"; }
tool_command() { printf "cmd-%s" "$1"; }
tool_safety() { printf "safe-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
prompt=$(build_planner_prompt_with_tools "find files" terminal notes_create)
printf '%s' "${prompt}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"terminal"* ]]
	[[ "${output}" == *"notes_create"* ]]
}

@test "build_planner_prompt_with_tools renders args schema for tools" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
tool_description() { printf "desc-%s" "$1"; }
tool_command() { printf "cmd-%s" "$1"; }
tool_safety() { printf "safe-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
prompt=$(build_planner_prompt_with_tools "collect data" terminal)
printf '%s' "${prompt}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *'Args Schema: {"type":"object","properties":{"input"'* ]]
}

@test "executor prompt template exposes infill placeholders" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/prompt/templates.sh
template="$(load_prompt_template executor)"
grep -F '${tool}' <<<"${template}"
grep -F '${args_json}' <<<"${template}"
grep -F '${context_fields}' <<<"${template}"
SCRIPT

	[ "$status" -eq 0 ]
}
