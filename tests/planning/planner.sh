#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for planner.sh.

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034 # TD-001: dynamic globals are intentionally consumed across sourced modules and tests.
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

@test "planner reuses caller-provided TOOLS array" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

declare -a TOOLS=(alpha beta)
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh

planner_collect_tools | paste -sd ',' -
SCRIPT

	[ "$status" -eq 0 ]
	catalog=$(printf '%s' "${output}" | tail -n 1)
	[ "${catalog}" = "alpha,beta,final_answer" ]
}

@test "planner_collect_tools appends final_answer when missing from override" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh

planner_collect_tools $'notes_read\nweb_search' | paste -sd ',' -
SCRIPT

	[ "$status" -eq 0 ]
	catalog=$(printf '%s' "${output}" | tail -n 1)
	[ "${catalog}" = "notes_read,web_search,final_answer" ]
}

@test "planner falls back to tool_names when TOOLS is unset" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh

tool_names() { printf '%s\n' web final_answer; }
export -f tool_names

planner_collect_tools | paste -sd ',' -
SCRIPT

	[ "$status" -eq 0 ]
	catalog=$(printf '%s' "${output}" | tail -n 1)
	[ "${catalog}" = "web,final_answer" ]
}

@test "planner falls back to tool_names when TOOLS is empty" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

declare -a TOOLS=()
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh

tool_names() { printf '%s\n' scratch final_answer; }
export -f tool_names

planner_collect_tools | paste -sd ',' -
SCRIPT

	[ "$status" -eq 0 ]
	catalog=$(printf '%s' "${output}" | tail -n 1)
	[ "${catalog}" = "scratch,final_answer" ]
}

@test "planner prompt avoids duplicate args-schema tool catalog text" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

export PLANNER_SKIP_TOOL_LOAD=true
export LLAMA_AVAILABLE=true
export VERBOSITY=0
source ./src/lib/planning/planner.sh

prompt_file="$(mktemp)"
tool_description() { printf 'desc-%s' "$1"; }
planner_build_plan_schema() { printf '{"type":"array","items":{"type":"object"}}'; }
planner_plan_criteria_report() { printf '{"ok":true,"reasons":[]}'; }
llama_infer() {
        printf '%s' "$1" >"${prompt_file}"
        printf '[{"thought":"Return answer","tool":"final_answer","args":{"input":"ok"}}]'
}

generate_planner_response_with_context "help me" "Search 1: recipe" $'terminal\nfinal_answer' '{}'
if grep -q "Args Schema:" "${prompt_file}"; then
        echo "planner prompt still includes duplicate Args Schema text"
        exit 1
fi
SCRIPT

	[ "$status" -eq 0 ]
}

@test "planner budgets oversized search context before llama invocation" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

export PLANNER_SKIP_TOOL_LOAD=true
export LLAMA_AVAILABLE=true
export LLAMA_DEFAULT_CONTEXT_SIZE=4096
export LLAMA_CONTEXT_CAP=4096
export PLANNER_MAX_OUTPUT_TOKENS=1024
export VERBOSITY=0
source ./src/lib/planning/planner.sh

prompt_file="$(mktemp)"
tool_description() { printf 'desc-%s' "$1"; }
planner_build_plan_schema() { printf '{"type":"array","items":{"type":"object"}}'; }
planner_plan_criteria_report() { printf '{"ok":true,"reasons":[]}'; }
llama_infer() {
        printf '%s' "$1" >"${prompt_file}"
        printf '[{"thought":"Return answer","tool":"final_answer","args":{"input":"ok"}}]'
}

large_search_context="$(printf 'Search 1: %s\n' "$(printf 'entry %.0s' {1..12000})")"
generate_planner_response_with_context "help me" "${large_search_context}" $'terminal\nfinal_answer' '{}'

prompt_tokens="$(estimate_token_count "$(cat "${prompt_file}")")"
if ((prompt_tokens + 1024 > 4096)); then
        echo "planner prompt exceeded context budget: prompt_tokens=${prompt_tokens}"
        exit 1
fi
SCRIPT

	[ "$status" -eq 0 ]
}
