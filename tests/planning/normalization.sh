#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

registry_payload() {
	cat <<'JSON'
{"names":["notes_create","final_answer"],"registry":{"notes_create":{"args_schema":{"type":"object","required":["title"],"properties":{"title":{"type":"string","minLength":1}},"additionalProperties":false}},"final_answer":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}},"additionalProperties":false}}}}
JSON
}

@test "normalize_plan accepts top-level plan arrays" {
	# shellcheck disable=SC2155
	# shellcheck disable=SC2030
	export TOOL_REGISTRY_JSON=$(registry_payload)
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_response='[{"tool":"notes_create","args":{"title":"t"},"thought":"note"},{"tool":"final_answer","args":{"input":"done"},"thought":"reply"}]'
normalize_plan <<<"${raw_response}" | jq -r '.[0].tool,.[0].args.title,.[0].thought,.[1].tool,.[1].args.input'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "notes_create" ]
	[ "${lines[1]}" = "t" ]
	[ "${lines[2]}" = "note" ]
	[ "${lines[3]}" = "final_answer" ]
	[ "${lines[4]}" = "done" ]
}

@test "normalize_plan enforces array shape from arguments" {
	# shellcheck disable=SC2155
	# shellcheck disable=SC2030
	# shellcheck disable=SC2031
	export TOOL_REGISTRY_JSON=$(registry_payload)
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
normalize_plan '{"plan": "not an array"}'
SCRIPT

	[ "$status" -ne 0 ]
}

@test "normalize_plan fails cleanly on empty output" {

	# shellcheck disable=SC2031
	# shellcheck disable=SC2155
	export TOOL_REGISTRY_JSON=$(registry_payload)
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
normalize_plan <<<""
SCRIPT

	[ "$status" -ne 0 ]
	[[ "${output}" == *"planner_output_empty"* ]]
}
