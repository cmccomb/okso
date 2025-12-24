#!/usr/bin/env bats
#
# Tests for formatting helpers.
#
# Usage:
#   bats tests/lib/test_formatting.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

@test "format_tool_descriptions filters empty lines and applies formatter" {
	run bash -s <<'EOF'
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/formatting.sh
tool_description() { printf "desc-%s" "$1"; }
tool_command() { printf "cmd-%s" "$1"; }
tool_safety() { printf "safe-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
input=$'alpha\n\nbeta'
output="$(format_tool_descriptions "${input}" format_tool_line)"
expected=$'- alpha: desc-alpha | Args Schema: {"type":"object","properties":{"input":{"type":"string"}}} | Example: cmd-alpha | Safety: safe-alpha\n- beta: desc-beta | Args Schema: {"type":"object","properties":{"input":{"type":"string"}}} | Example: cmd-beta | Safety: safe-beta'
[[ "${output}" == "${expected}" ]]
EOF
	[ "$status" -eq 0 ]
}

@test "format_tool_example_line includes command examples" {
	run bash -s <<'EOF'
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/formatting.sh
tool_description() { printf "describe-%s" "$1"; }
tool_command() { printf "run-%s" "$1"; }
tool_safety() { printf "limit-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
line="$(format_tool_example_line "demo")"
[[ "${line}" == "- demo: describe-demo | Args Schema: {\"type\":\"object\",\"properties\":{\"input\":{\"type\":\"string\"}}} | Example: run-demo | Safety: limit-demo" ]]
EOF
	[ "$status" -eq 0 ]
}

@test "format_tool_descriptions rejects unknown formatter" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                format_tool_descriptions "demo" missing_formatter
        '
	[ "$status" -eq 1 ]
}

@test "format_tool_history collects multi-line observations case-insensitively" {
        run bash -lc '
                set -e
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh

                tool_history=$(printf "Step 1 action search query=weather\nobservation: first line\n  second line\ntrailing text\nStep 2 action finalize\nObservation: done")
                output=$(format_tool_history "${tool_history}")

                [[ "${output}" == *"- Step 1"* ]]
                [[ "${output}" == *"action: search query=weather"* ]]
                [[ "${output}" == *"observation: first line"* ]]
                [[ "${output}" == *"  second line"* ]]
                [[ "${output}" == *"  trailing text"* ]]
                [[ "${output}" == *"- Step 2"* ]]
                [[ "${output}" == *"action: finalize"* ]]
                [[ "${output}" == *"observation: done"* ]]
        '
        [ "$status" -eq 0 ]
}

@test "format_tool_history prefers summaries and preserves latest raw observation" {
        run bash -lc '
                set -euo pipefail
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh

                tool_history=$(cat <<'JSON'
{"step":1,"action":{"tool":"terminal","args":{}},"thought":"list","observation":"legacy","observation_summary":"summary-1","observation_raw":"raw-1"}
{"step":2,"action":{"tool":"web_search","args":{"query":"okso"}},"thought":"search","observation_summary":"summary-2","observation_raw":"raw-2"}
{"step":3,"action":{"tool":"web_fetch","args":{"url":"http://example"}},"thought":"fetch","observation_summary":"summary-3","observation_raw":"raw-3"}
JSON
)

                output=$(format_tool_history "${tool_history}")

                [[ "${output}" == *"- Step 1"* ]]
                [[ "${output}" == *"observation: summary-1"* ]]
                [[ "${output}" != *"raw-1"* ]]

                [[ "${output}" == *"- Step 2"* ]]
                [[ "${output}" == *"observation: summary-2"* ]]
                [[ "${output}" != *"raw-2"* ]]

                [[ "${output}" == *"- Step 3"* ]]
                [[ "${output}" == *"observation: raw-3"* ]]
                [[ "${output}" != *"summary-3"* ]]
        '
        [ "$status" -eq 0 ]
}
