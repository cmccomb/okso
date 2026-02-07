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
source ./src/lib/cli/output.sh
tool_description() { printf "desc-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
input=$'alpha\n\nbeta'
output="$(format_tool_descriptions "${input}" format_tool_line)"
expected=$'- alpha: desc-alpha | Args Schema: {"type":"object","properties":{"input":{"type":"string"}}}\n- beta: desc-beta | Args Schema: {"type":"object","properties":{"input":{"type":"string"}}}'
[[ "${output}" == "${expected}" ]]
EOF
	[ "$status" -eq 0 ]
}

@test "format_tool_example_line hides schema unless trace verbose is enabled" {
	run bash -s <<'EOF'
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/cli/output.sh
tool_description() { printf "describe-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
line="$(format_tool_example_line "demo")"
[[ "${line}" == "- demo: describe-demo" ]]
OKSO_TRACE_VERBOSE=1
line_with_schema="$(format_tool_example_line "demo")"
[[ "${line_with_schema}" == "- demo: describe-demo | Args Schema: {\"type\":\"object\",\"properties\":{\"input\":{\"type\":\"string\"}}}" ]]
EOF
	[ "$status" -eq 0 ]
}

@test "format_tool_history collects multi-line observations case-insensitively" {
	run bash -lc '
                set -e
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/cli/output.sh

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

@test "format_tool_history preserves web_search JSON observations" {
	run bash -s <<'EOF'
set -e
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/cli/output.sh

observation_json='{"items":[{"title":"Example result","snippet":"Snippet text","url":"https://example.com"}],"total_results":1}'
history_line='{"step":1,"thought":"Search for examples","action":{"tool":"web_search","args":{"query":"example"}},"observation":{"items":[{"title":"Example result","snippet":"Snippet text","url":"https://example.com"}],"total_results":1}}'

output=$(format_tool_history "${history_line}")
printf "%s" "${output}" | grep -Fq "${observation_json}"
EOF
	[ "$status" -eq 0 ]
}
