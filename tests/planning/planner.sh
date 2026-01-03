#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "generate_planner_response falls back when llama is unavailable" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
TESTING_PASSTHROUGH=true
export TESTING_PASSTHROUGH
source ./src/lib/planning/planner.sh
llama_infer() { printf '[{"tool":"final_answer","args":{}}]'; }
export -f llama_infer
planner_fetch_search_context() { printf 'Search context unavailable.'; }
LLAMA_AVAILABLE=false
PLANNER_SAMPLE_COUNT=1
generate_planner_response "tell me a joke"
SCRIPT

	[ "$status" -eq 0 ]
	plan_length=$(printf '%s' "${output}" | tail -n 1 | jq -r 'length')
	final_tool=$(printf '%s' "${output}" | tail -n 1 | jq -r '.[-1].tool')
	[ "${plan_length}" -ge 1 ]
	[ "${final_tool}" = "final_answer" ]
}

@test "planner sources executor loop entrypoint by default" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TESTING_PASSTHROUGH=true
export TESTING_PASSTHROUGH
source ./src/lib/planning/planner.sh

expected_entrypoint="$(cd ./src/lib/executor && pwd)/loop.sh"
actual_entrypoint="$(cd -- "$(dirname "${EXECUTOR_ENTRYPOINT}")" && pwd)/$(basename "${EXECUTOR_ENTRYPOINT}")"
[[ "${actual_entrypoint}" == "${expected_entrypoint}" ]]

[[ "$(type -t executor_loop)" == "function" ]]
SCRIPT

	[ "$status" -eq 0 ]
}
