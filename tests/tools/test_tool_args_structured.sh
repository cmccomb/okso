#!/usr/bin/env bats
#
# Tests for mapping structured JSON tool arguments to CLI flags.
#
# Usage:
#   bats tests/tools/test_tool_args_structured.sh
#
# Regression tests ensuring TOOL_ARGS drive tool handlers.

@test "final_answer requires structured TOOL_ARGS" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

chpwd_functions=()
unset -f chpwd _mise_hook 2>/dev/null || true

source ./src/tools/final_answer.sh

output=$(TOOL_ARGS='{"input":"structured value"}' tool_final_answer)

if [[ "${output}" != "structured value" ]]; then
        echo "final_answer did not prefer structured args"
        exit 1
fi

if TOOL_ARGS="" TOOL_QUERY="legacy" tool_final_answer >/dev/null 2>&1; then
        echo "final_answer unexpectedly accepted TOOL_QUERY fallback"
        exit 1
fi
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "${status}" -eq 0 ]
}

@test "planner replay uses structured args for file_search" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

chpwd_functions=()
unset -f chpwd _mise_hook 2>/dev/null || true

source ./src/lib/planning/planner.sh
source ./src/lib/tools.sh

init_tool_registry
register_file_search
register_final_answer

extract_tool_query() { printf '%s' "legacy"; }

working_dir=$(mktemp -d)
cd "${working_dir}"

: >structured_match.txt
: >legacy_only.txt

plan_json='[{"tool":"file_search","args":{"input":"structured_match"},"thought":"search"},{"tool":"final_answer","args":{"input":"done"},"thought":"finish"}]'
plan_entries="$(plan_json_to_entries "${plan_json}")"
allowed_tools="$(derive_allowed_tools_from_plan "${plan_json}")"
plan_outline="$(plan_json_to_outline "${plan_json}")"

USE_REACT_LLAMA=false
LLAMA_AVAILABLE=false
VERBOSITY=0
APPROVE_ALL=true
PLAN_ONLY=false
DRY_RUN=false
FORCE_CONFIRM=false

output=$(react_loop "find files" "${allowed_tools}" "${plan_entries}" "${plan_outline}" 2>/dev/null)

rm -rf "${working_dir}"

grep -F "structured_match" <<<"${output}"
if grep -F "legacy_only" <<<"${output}"; then
        echo "file_search used TOOL_QUERY instead of TOOL_ARGS"
        exit 1
fi
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "${status}" -eq 0 ]
}

@test "ReAct loop forwards structured args to applescript" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

chpwd_functions=()
unset -f chpwd _mise_hook 2>/dev/null || true

source ./src/lib/planning/planner.sh
source ./src/lib/tools.sh

init_tool_registry
register_applescript
register_final_answer

extract_tool_query() { printf '%s' "legacy"; }
assert_osascript_available() { return 0; }
# shellcheck disable=SC2120
osascript_run_evaluated() { printf '%s' "$2"; }

llama_queue=$(mktemp)
printf '%s\n' '{"thought":"run it","tool":"applescript","args":{"input":"beep"}}' '{"thought":"wrap up","tool":"final_answer","args":{"input":"done"}}' >"${llama_queue}"
llama_infer() {
        local next remaining
        next=$(head -n 1 "${llama_queue}" || printf '{}')
        remaining=$(tail -n +2 "${llama_queue}" 2>/dev/null || true)
        printf '%s' "${remaining}" >"${llama_queue}"
        printf '%s' "${next}"
}

allowed_tools=$'applescript\nfinal_answer'
plan_entries=""
plan_outline=$'1. run applescript\n2. wrap up'
state_prefix=react_state

initialize_react_state "${state_prefix}" "demo" "${allowed_tools}" "${plan_entries}" "${plan_outline}"

USE_REACT_LLAMA=true
LLAMA_AVAILABLE=true
VERBOSITY=0
MAX_STEPS=3
APPROVE_ALL=true
PLAN_ONLY=false
DRY_RUN=false
FORCE_CONFIRM=false

select_next_action "${state_prefix}" first_action
tool_one=$(jq -r '.tool' <<<"${first_action}")
args_one=$(jq -c '.args' <<<"${first_action}")
observation_one=$(execute_tool_action "${tool_one}" "legacy" "ctx" "${args_one}")

select_next_action "${state_prefix}" second_action
tool_two=$(jq -r '.tool' <<<"${second_action}")
args_two=$(jq -c '.args' <<<"${second_action}")
observation_two=$(execute_tool_action "${tool_two}" "legacy" "ctx" "${args_two}")

if [[ "${observation_one}" != "beep" ]]; then
        echo "unexpected first observation: ${observation_one}"
        exit 1
fi

if [[ "${observation_two}" != "done" ]]; then
        echo "unexpected second observation: ${observation_two}"
        exit 1
fi
rm -f "${llama_queue}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "${status}" -eq 0 ]
}
