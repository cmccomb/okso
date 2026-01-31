#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	export VERBOSITY=0
	export LLAMA_AVAILABLE=false
	export TESTING_PASSTHROUGH=true
	export TOOL_REGISTRY_JSON='{"names":["notes_create","notes_read","terminal","final_answer","web_search"],"registry":{}}'
}

@test "recognize_intent falls back to heuristic when llama is unavailable" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/intent.sh
intent_json="$(recognize_intent "Create a note about the meeting")"
printf '%s' "${intent_json}" | jq -r '.intent'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "notes" ]
}

@test "intent_to_tools returns full catalog when confidence is low" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/registry.sh
source ./src/lib/planning/intent.sh
intent_json='{"intent":"notes","confidence":0.1,"rationale":"uncertain"}'
intent_to_tools "${intent_json}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "notes_create" ]
	[ "${lines[1]}" = "notes_read" ]
	[ "${lines[2]}" = "terminal" ]
	[ "${lines[3]}" = "final_answer" ]
	[ "${lines[4]}" = "web_search" ]
}

@test "intent_to_tools filters to matching group when confidence is high" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/registry.sh
source ./src/lib/planning/intent.sh
intent_json='{"intent":"notes","confidence":0.9,"rationale":"notes task"}'
intent_to_tools "${intent_json}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "notes_create" ]
	[ "${lines[1]}" = "notes_read" ]
	[ "${lines[2]}" = "final_answer" ]
}

@test "planner_fetch_search_context skips search for non-web intents" {
	run bash <<'SCRIPT'
set -euo pipefail
export PLANNER_SKIP_TOOL_LOAD=true
source ./src/lib/planning/planner.sh
tool_web_search() {
	printf '%s' "unexpected"
	return 1
}
intent_json='{"intent":"filesystem","confidence":0.9,"rationale":"local"}'
planner_fetch_search_context "List local files" "${intent_json}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "" ]
}
