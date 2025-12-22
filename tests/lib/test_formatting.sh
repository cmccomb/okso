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
input=$'alpha\n\nbeta'
output="$(format_tool_descriptions "${input}" format_tool_line)"
expected=$'- alpha: desc-alpha | Example: cmd-alpha | Safety: safe-alpha\n- beta: desc-beta | Example: cmd-beta | Safety: safe-beta'
[[ "${output}" == "${expected}" ]]
EOF
	[ "$status" -eq 0 ]
}

@test "format_tool_example_line includes command examples" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                tool_description() { printf "describe-%s" "$1"; }
                tool_command() { printf "run-%s" "$1"; }
                tool_safety() { printf "limit-%s" "$1"; }
                line="$(format_tool_example_line "demo")"
                [[ "${line}" == "- demo: describe-demo | Example: run-demo | Safety: limit-demo" ]]
        '
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
