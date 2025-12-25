#!/usr/bin/env bats
# shellcheck shell=bash
#
# ReAct schema validation tests for tool argument handling.
#
# Usage:
#   bats tests/lib/test_react_schema.sh
#
# Dependencies:
#   - bats
#   - jq

@test "build_react_action_schema avoids combinators for llama.cpp" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/react/schema.sh
schema_path=$(build_react_action_schema $'web_search\nterminal')
trap 'rm -f "${schema_path}"' EXIT

if jq -e 'paths | map(tostring) | join("/") | test("oneOf|anyOf")' "${schema_path}" >/dev/null; then
        echo "Schema includes unsupported combinators" >&2
        exit 1
fi

jq -e '(.properties.tool.enum | sort) == ["terminal","web_search"] and (."$defs".args_by_tool | length == 2)' "${schema_path}" >/dev/null
SCRIPT
	[ "$status" -eq 0 ]
}

@test "validate_react_action accepts integer web_search num" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/react/schema.sh
schema_path=$(build_react_action_schema "web_search")
trap 'rm -f "${schema_path}"' EXIT

action='{"thought":"Search for docs","tool":"web_search","args":{"query":"okso","num":3}}'
validate_react_action "${action}" "${schema_path}"
SCRIPT
	[ "$status" -eq 0 ]
}

@test "validate_react_action rejects non-integer web_search num" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/react/schema.sh
schema_path=$(build_react_action_schema "web_search")
trap 'rm -f "${schema_path}"' EXIT

action='{"thought":"Search for docs","tool":"web_search","args":{"query":"okso","num":2.5}}'
set +e
validate_react_action "${action}" "${schema_path}"
result=$?
set -e
if [ "${result}" -eq 0 ]; then
        echo "Expected validation failure" >&2
        exit 1
fi
SCRIPT
	[ "$status" -eq 0 ]
}

@test "validate_react_action tolerates optional null args" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/react/schema.sh
schema_path=$(build_react_action_schema "web_search")
trap 'rm -f "${schema_path}"' EXIT

action='{"thought":"Search for docs","tool":"web_search","args":{"query":"okso","num":null}}'
validate_react_action "${action}" "${schema_path}"
SCRIPT
	[ "$status" -eq 0 ]
}

@test "validate_react_action enforces active tool schema" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/react/schema.sh

schema_path=$(mktemp)
cat >"${schema_path}" <<'JSON'
{
  "$defs": {
    "args_by_tool": {
      "web_search": {
        "type": "object",
        "properties": {
          "query": {"type": "string"},
          "num": {"type": "integer"}
        },
        "required": ["query"],
        "additionalProperties": false
      },
      "terminal": {
        "type": "object",
        "properties": {
          "command": {"type": "string"}
        },
        "required": ["command"],
        "additionalProperties": false
      }
    }
  },
  "properties": {
    "tool": {"type": "string", "enum": ["web_search", "terminal"]}
  }
}
JSON

invalid_action='{"thought":"run","tool":"terminal","args":{"query":"oops"}}'

set +e
validate_react_action "${invalid_action}" "${schema_path}" 2>err.log
result=$?
set -e

if [ "${result}" -eq 0 ]; then
        echo "Expected validation failure" >&2
        exit 1
fi

grep -F "Missing arg: command" err.log >/dev/null
if grep -F "Unexpected arg: query" err.log >/dev/null; then
        echo "unexpected arg rejection triggered" >&2
        exit 1
fi
SCRIPT
	[ "$status" -eq 0 ]
}
