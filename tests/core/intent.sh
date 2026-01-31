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

@test "planner_fetch_search_context skips search for non-web intents" {
	run bash <<'SCRIPT'
set -euo pipefail
export PLANNER_SKIP_TOOL_LOAD=true
source ./src/lib/planning/planner.sh
tool_web_search() {
	printf '%s' "unexpected"
	return 1
}
intent_json='{"intent":"filesystem","rationale":"local"}'
planner_fetch_search_context "List local files" "${intent_json}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "" ]
}
