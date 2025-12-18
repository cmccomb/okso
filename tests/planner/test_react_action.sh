#!/usr/bin/env bats
#
# Regression tests for ReAct action validation and selection.
#
# Usage:
#   bats tests/planner/test_react_action.sh
#
# Dependencies:
#   - bats
#   - bash 5+

@test "validate_react_action accepts actions without type" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["message"],"properties":{"message":{"type":"string","minLength":1}},"additionalProperties":false}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_react_action_grammar "alpha")"
action='{"thought":"go","tool":"alpha","args":{"message":"hi"}}'
validated="$(validate_react_action "${action}" "${schema_path}")"
rm -f "${schema_path}"

jq -e 'has("thought") and has("tool") and has("args") and (.thought=="go") and (.tool=="alpha") and (.args.message=="hi") and (has("type")|not)' <<<"${validated}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "build_react_action_grammar disallows extra args unless opted in" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["message"],"properties":
{"message":{"type":"string","minLength":1}}}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_react_action_grammar "alpha")"

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

source ./src/lib/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["message"],"properties":
{"message":{"type":"string","minLength":1}}}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_react_action_grammar "alpha")"

invalid_action='{"thought":"go","tool":"alpha","args":{"message":"hi","noise":"boom"}}'

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

source ./src/lib/planner.sh

schema_path="$(build_react_action_grammar "terminal")"

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

source ./src/lib/planner.sh

state_prefix=react
initialize_react_state "${state_prefix}" "demo request" $'terminal\nfinal_answer' $'terminal|echo hi|0' $'1. terminal -> run echo'

next_action="$(select_next_action "${state_prefix}")"

jq -e 'has("thought") and has("tool") and has("args") and (has("type")|not)' <<<"${next_action}"
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

source ./src/lib/planner.sh

tool_registry_json() {
        printf "%s" '{"names":["python_repl","final_answer"],"registry":{"python_repl":{"args_schema":{"type":"object","required":["code"],"properties":{"code":{"type":"string","minLength":1}}}},"final_answer":{"args_schema":{"type":"object","required":["message"],"properties":{"message":{"type":"string","minLength":1}}}}}}'
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

react_grammar_path="$(build_react_action_grammar "${allowed_tools}")"
react_grammar_text="$(cat "${react_grammar_path}")"

prompt="$(build_react_prompt "demo request" "${allowed_tool_descriptions}" "demo plan" "demo history" "${react_grammar_text}")"

rm -f "${react_grammar_path}"

grep -F '"python_repl"' <<<"${prompt}"
grep -F '"code"' <<<"${prompt}"
grep -F '"final_answer"' <<<"${prompt}"
grep -F '"message"' <<<"${prompt}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}
