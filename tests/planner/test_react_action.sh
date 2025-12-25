#!/usr/bin/env bats
#
# Regression tests for executor action validation and selection.
#
# Usage:
#   bats tests/planner/test_react_action.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "react_action schema documents action wrapper" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

schema_path="./src/schemas/react_action.schema.json"

jq -e '
        (.oneOf | length == 2)
        and (.oneOf[0].required == ["action"])
        and (.oneOf[0].properties.action.required | sort == ["args","tool"])
        and (.oneOf[0].properties.action.properties.tool.const == "final_answer")
        and (.oneOf[0].properties.action.properties.args.required == ["input"])
        and (.oneOf[1].properties.action.const == "__MISSING__")
' "${schema_path}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "build_react_action_schema injects missing sentinel" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/react/schema.sh
source ./src/lib/prompt/build_react.sh

tool_registry_json() {
        printf "%s" '{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}},"additionalProperties":false}}}}'
}

tool_names() { printf "%s\n" "alpha"; }

schema_path="$(build_react_action_schema "alpha")"

jq -e '
        (.oneOf[0].properties.action.properties.tool.anyOf | map(.const) | index("__MISSING__")) as $tool_missing
        | (.oneOf[0].properties.action.properties.args.anyOf | map(.const) | index("__MISSING__")) as $args_missing
        | ($tool_missing != null and $args_missing != null)
' "${schema_path}"

rm -f "${schema_path}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "validate_react_action accepts missing sentinel payloads" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/react/schema.sh

schema_path="$(build_react_action_schema "final_answer")"
action='{"action":{"tool":"__MISSING__","args":"__MISSING__"}}'

validate_react_action "${action}" "${schema_path}" >/dev/null
rm -f "${schema_path}"
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}

@test "validate_react_action rejects unsupported tools" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/react/schema.sh
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
            "tool": {"anyOf": [{"const": "alpha"}, {"const": "__MISSING__"}]},
            "args": {"anyOf": [{"type": "object", "properties": {"input": {"type": "string"}}, "required": ["input"], "additionalProperties": false}, {"const": "__MISSING__"}]}
          }
        }
      },
      "additionalProperties": false
    },
    {"properties": {"action": {"const": "__MISSING__"}}}
  ]
}
JSON

invalid_action='{"action":{"tool":"beta","args":{"input":"hi"}}}'

set +e
validate_react_action "${invalid_action}" "${schema_path}" 2>err.log
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

@test "validate_react_action enforces argument type schemas" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/react/schema.sh

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
            "tool": {"anyOf": [{"const": "alpha"}, {"const": "__MISSING__"}]},
            "args": {"anyOf": [
              {
                "type": "object",
                "properties": {"count": {"type": "integer"}},
                "required": ["count"],
                "additionalProperties": false
              },
              {"const": "__MISSING__"}
            ]}
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
validate_react_action "${invalid_action}" "${schema_path}" 2>err.log
status=$?
set -e

if [[ ${status} -eq 0 ]]; then
        echo "validation unexpectedly succeeded"
        exit 1
fi

grep -F "Arg count must be a integer" err.log
rm -f "${schema_path}" err.log
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

source ./src/lib/react/schema.sh
source ./src/lib/prompt/build_react.sh

allowed_tools=$'terminal\nfinal_answer'
allowed_tool_descriptions=$'Available tools:\n- terminal: Run shell commands.\n- final_answer: Return a response.'
react_schema_path="$(build_react_action_schema "${allowed_tools}")"
react_schema_text="$(cat "${react_schema_path}")"

prompt="$(build_react_prompt "demo request" "${allowed_tool_descriptions}" "demo plan" "${react_schema_text}" "step 1")"
rm -f "${react_schema_path}"

grep -qi "executor" <<<"${prompt}"
grep -F "demo request" <<<"${prompt}"
if grep -F "history" <<<"${prompt}"; then
        echo "prompt unexpectedly referenced history"
        exit 1
fi
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "$status" -eq 0 ]
}
