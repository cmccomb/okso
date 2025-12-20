#!/usr/bin/env bats
#
# Regression tests for ReAct action validation and selection.
#
# Usage:
#   bats tests/planner/test_react_action.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "validate_react_action accepts actions without type" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}},"additionalProperties":false}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_react_action_schema "alpha")"
action='{"thought":"go","tool":"alpha","args":{"input":"hi"}}'
validated="$(validate_react_action "${action}" "${schema_path}")"
rm -f "${schema_path}"

jq -e 'has("thought") and has("tool") and has("args") and (.thought=="go") and (.tool=="alpha") and (.args.input=="hi") and (has("type")|not)' <<<"${validated}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "build_react_action_schema disallows extra args unless opted in" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}}}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_react_action_schema "alpha")"

jq -e '."$defs".args_by_tool.alpha.additionalProperties == false' "${schema_path}"

rm -f "${schema_path}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "validate_react_action rejects extraneous arguments" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}}}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_react_action_schema "alpha")"

invalid_action='{"thought":"go","tool":"alpha","args":{"input":"hi","noise":"boom"}}'

set +e
validate_react_action "${invalid_action}" "${schema_path}" 2>err.log
status=$?
set -e

if [[ ${status} -eq 0 ]]; then
        echo "validation unexpectedly succeeded"
        exit 1
fi

grep -F "Unexpected arg: noise" err.log
rm -f "${schema_path}" err.log
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "validate_react_action accepts terminal arg arrays" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

schema_path="$(build_react_action_schema "terminal")"

action='{"thought":"execute","tool":"terminal","args":{"command":"echo","args":["hi"]}}'
validate_react_action "${action}" "${schema_path}" >/dev/null

rm -f "${schema_path}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "select_next_action emits simplified payload when llama is unavailable" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

USE_REACT_LLAMA=false
LLAMA_AVAILABLE=false

source ./src/lib/planning/planner.sh

state_prefix=react
initialize_react_state "${state_prefix}" "demo request" $'terminal\nfinal_answer' $'terminal|echo hi|0' $'1. terminal -> run echo'

next_action="$(select_next_action "${state_prefix}")"

jq -e 'has("thought") and has("tool") and has("args") and (has("type")|not)' <<<"${next_action}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "select_next_action invokes llama even when plan step is fully specified" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

llama_prompt_file=$(mktemp)
llama_infer() {
        printf '%s' "$1" >"${llama_prompt_file}"
        printf '%s' '{"thought":"llama chose","tool":"terminal","args":{"command":"echo","args":["hi"]}}'
}

state_prefix=react
plan_entry=$(jq -nc '{tool:"terminal",args:{command:"echo",args:["hi"]},thought:"planned guidance"}')
plan_outline=$'1. terminal -> echo hi\n2. final_answer -> summarize'

initialize_react_state "${state_prefix}" "demo request" $'terminal\nfinal_answer' "${plan_entry}" "${plan_outline}"

USE_REACT_LLAMA=true
LLAMA_AVAILABLE=true

select_next_action "${state_prefix}" action_json

if [[ ! -s "${llama_prompt_file}" ]]; then
        echo "llama_infer was not called"
        exit 1
fi

plan_index="$(state_get "${state_prefix}" "plan_index")"
if [[ "${plan_index}" -ne 1 ]]; then
        echo "plan index did not advance: ${plan_index}"
        exit 1
fi

if ! grep -F 'planned guidance' "${llama_prompt_file}" >/dev/null; then
        echo "plan thought missing from prompt"
        exit 1
fi

if ! grep -F '"command":"echo"' "${llama_prompt_file}" >/dev/null; then
        echo "plan args missing from prompt"
        exit 1
fi

jq -e '.tool == "terminal" and .args.command == "echo" and .thought == "llama chose"' <<<"${action_json}"
rm -f "${llama_prompt_file}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "select_next_action keeps plan index when llama validation fails" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

llama_calls_file=$(mktemp)
llama_infer() {
        echo "call" >>"${llama_calls_file}"
        printf '%s' '{"not_valid":true}'
}

state_prefix=react
plan_entry=$(jq -nc '{tool:"terminal",args:{command:"echo",args:["hi"]},thought:"planned guidance"}')
plan_outline=$'1. terminal -> echo hi\n2. final_answer -> summarize'

initialize_react_state "${state_prefix}" "demo request" $'terminal\nfinal_answer' "${plan_entry}" "${plan_outline}"

USE_REACT_LLAMA=true
LLAMA_AVAILABLE=true

set +e
select_next_action "${state_prefix}" action_json
status=$?
set -e

if [[ ${status} -eq 0 ]]; then
        echo "expected llama validation to fail"
        exit 1
fi

plan_index="$(state_get "${state_prefix}" "plan_index")"
if [[ "${plan_index}" -ne 0 ]]; then
        echo "plan index should not advance on failure: ${plan_index}"
        exit 1
fi

llama_calls=$(wc -l <"${llama_calls_file}")
rm -f "${llama_calls_file}"
if [[ "${llama_calls}" -ne 2 ]]; then
        echo "expected corrective llama retry"
        exit 1
fi
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "build_react_prompt includes allowed tool schemas" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["python_repl","final_answer"],"registry":{"python_repl":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}}}},"final_answer":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}}}}}}'
}

tool_names() {
        printf "%s\n" "python_repl" "final_answer"
}

allowed_tools=$'python_repl\nfinal_answer'
allowed_tool_lines="$(format_tool_descriptions "${allowed_tools}" format_tool_example_line)"
allowed_tool_descriptions="Available tools:"
if [[ -n "${allowed_tool_lines}" ]]; then
        allowed_tool_descriptions+=$'\n'"${allowed_tool_lines}"
fi

react_schema_path="$(build_react_action_schema "${allowed_tools}")"
react_schema_text="$(cat "${react_schema_path}")"

prompt="$(build_react_prompt "demo request" "${allowed_tool_descriptions}" "demo plan" "demo history" "${react_schema_text}" "step 1")"

rm -f "${react_schema_path}"

grep -F '"python_repl"' <<<"${prompt}"
grep -F '"input"' <<<"${prompt}"
grep -F '"final_answer"' <<<"${prompt}"
grep -F '"input"' <<<"${prompt}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}
