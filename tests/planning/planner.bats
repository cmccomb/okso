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
source ./src/lib/planning/planner.sh
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
planner_fetch_search_context() { printf 'Search context unavailable.'; }
LLAMA_AVAILABLE=false
generate_plan_json "tell me a joke"
SCRIPT

	[ "$status" -eq 0 ]
	mode=$(printf '%s' "${output}" | tail -n 1 | jq -r '.mode')
	answer=$(printf '%s' "${output}" | tail -n 1 | jq -r '.quickdraw.final_answer')
	[ "${mode}" = "quickdraw" ]
	[ -n "${answer}" ]
}

@test "generate_plan_json appends final step to llama output" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
LLAMA_AVAILABLE=true
PLANNER_MODEL_REPO=fake
PLANNER_MODEL_FILE=fake
planner_fetch_search_context() { printf 'Search context unavailable.'; }
llama_infer() { printf '[{"tool":"terminal","args":{},"thought":"do"}]'; }
generate_plan_json "list" | jq -r '.[].tool'
SCRIPT

	[ "$status" -eq 0 ]
	tools=$(printf '%s\n' "${output}" | grep -E '^(terminal|final_answer)$')
	first_tool=$(printf '%s\n' "${tools}" | sed -n '1p')
	second_tool=$(printf '%s\n' "${tools}" | sed -n '2p')
	[ "${first_tool}" = "terminal" ]
	[ "${second_tool}" = "final_answer" ]
}
