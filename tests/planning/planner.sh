#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "generate_plan_json falls back when llama is unavailable" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh
planner_fetch_search_context() { printf 'Search context unavailable.'; }
LLAMA_AVAILABLE=false
PLANNER_SAMPLE_COUNT=1
generate_plan_json "tell me a joke"
SCRIPT

	[ "$status" -eq 0 ]
	plan_length=$(printf '%s' "${output}" | tail -n 1 | jq -r 'length')
	final_tool=$(printf '%s' "${output}" | tail -n 1 | jq -r '.[-1].tool')
	[ "${plan_length}" -ge 1 ]
	[ "${final_tool}" = "final_answer" ]
}
