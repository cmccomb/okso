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
LLAMA_AVAILABLE=false
generate_plan_json "tell me a joke"
SCRIPT

	[ "$status" -eq 0 ]
	mode=$(printf '%s' "${output}" | jq -r '.mode')
	answer=$(printf '%s' "${output}" | jq -r '.quickdraw.final_answer')
	[ "${mode}" = "quickdraw" ]
	[ -n "${answer}" ]
}

@test "generate_plan_json appends final step to llama output" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
LLAMA_AVAILABLE=true
PLANNER_MODEL_REPO=fake
PLANNER_MODEL_FILE=fake
llama_infer() { printf '[{"tool":"terminal","args":{},"thought":"do"}]'; }
generate_plan_json "list" | jq -r '.[].tool'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "final_answer" ]
}
