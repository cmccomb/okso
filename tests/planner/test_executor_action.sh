#!/usr/bin/env bats
#
# Regression tests for executor action validation and selection.
#
# Usage:
#   bats tests/planner/test_executor_action.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "executor_action schema documents action wrapper" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

schema_path="./src/schemas/executor_action.schema.json"

jq -e '
        (.oneOf | length == 1)
        and (.oneOf[0].required == ["action"])
        and (.oneOf[0].properties.action.required | sort == ["args","tool"])
        and (.oneOf[0].properties.action.properties.tool.const == "final_answer")
        and (.oneOf[0].properties.action.properties.args.required == ["input"])
' "${schema_path}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "build_executor_action_schema constrains allowed tools" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/executor/schema.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}},"additionalProperties":false}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_executor_action_schema "alpha")"

jq -e '
        (.oneOf | length == 1)
        and (.oneOf[0].properties.action.properties.tool.const == "alpha")
        and (.oneOf[0].properties.action.properties.args.properties.input.minLength == 1)
' "${schema_path}"

rm -f "${schema_path}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "validate_executor_action rejects unsupported tools" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/executor/schema.sh
schema_path=$(mktemp)
cat >"${schema_path}" <<'JSON'
{
  "oneOf": [
    {
      "type": "object",
      "required": ["action"],
      "properties": {
        "action": {
          "type": "object",
          "required": ["tool", "args"],
          "additionalProperties": false,
          "properties": {
            "tool": {"const": "alpha"},
            "args": {"type": "object", "properties": {"input": {"type": "string"}}, "required": ["input"], "additionalProperties": false}
          }
        }
      },
      "additionalProperties": false
    }
  ]
}
JSON

invalid_action='{"action":{"tool":"beta","args":{"input":"hi"}}}'

set +e
validate_executor_action "${invalid_action}" "${schema_path}" 2>err.log
status=$?
set -e

if [[ ${status} -eq 0 ]]; then
        echo "validation unexpectedly succeeded"
        exit 1
fi

grep -F "Unsupported tool: beta" err.log
rm -f "${schema_path}" err.log
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "validate_executor_action surfaces schema validation errors" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/executor/schema.sh

schema_path=$(mktemp)
cat >"${schema_path}" <<'JSON'
{
  "oneOf": [
    {
      "type": "object",
      "required": ["action"],
      "properties": {
        "action": {
          "type": "object",
          "required": ["tool", "args"],
          "additionalProperties": false,
          "properties": {
            "tool": {"const": "alpha"},
            "args": {
              "type": "object",
              "properties": {"count": {"type": "integer"}},
              "required": ["count"],
              "additionalProperties": false
            }
          }
        }
      },
      "additionalProperties": false
    }
  ]
}
JSON

invalid_action='{"action":{"tool":"alpha","args":{"count":"oops"}}}'

set +e
validate_executor_action "${invalid_action}" "${schema_path}" 2>err.log
status=$?
set -e

if [[ ${status} -eq 0 ]]; then
        echo "validation unexpectedly succeeded"
        exit 1
fi

grep -F "action/args/count: 'oops' is not of type 'integer'" err.log
rm -f "${schema_path}" err.log
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "fill_missing_args_with_llm renders executor template" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

prompt_log="$(mktemp)"
prompt_capture="${prompt_log}.prompt"
trap 'rm -f "${prompt_log}" "${prompt_capture}"' EXIT

source ./src/lib/executor/loop.sh

render_prompt_template() {
        printf 'executor:%s' "$*" >"${prompt_log}"
        printf 'stubbed executor prompt'
}
export -f render_prompt_template

tool_args_schema() { printf '{"type":"object"}'; }
export -f tool_args_schema

llama_infer() {
        cat >"${prompt_capture}" <<<"$1"
        printf '{"args":{"filled":true}}'
}
export -f llama_infer

LLAMA_AVAILABLE=true

output="$(fill_missing_args_with_llm "demo_tool" '{"input":"provided"}' "user wants" "a plan" "planner note" "" '["input"]')"

grep -F 'stubbed executor prompt' "${prompt_capture}"
grep -F 'executor:executor tool demo_tool user_query user wants plan_outline a plan planner_thought planner note args_json {"input":"provided"} args_schema {"type":"object"} context_fields ["input"]' "${prompt_log}"
[[ "${output}" == '{"args":{"filled":true}}' ]]
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}
