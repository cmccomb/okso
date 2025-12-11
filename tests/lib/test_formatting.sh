#!/usr/bin/env bats
#
# Tests for formatting helpers.
#
# Usage:
#   bats tests/lib/test_formatting.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

@test "format_tool_descriptions filters empty lines and applies formatter" {
	run bash -s <<'EOF'
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/formatting.sh
tool_description() { printf "desc-%s" "$1"; }
tool_command() { printf "cmd-%s" "$1"; }
input=$'alpha\n\nbeta'
output="$(format_tool_descriptions "${input}" format_tool_summary_line)"
expected=$'- alpha: desc-alpha\n- beta: desc-beta'
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
                line="$(format_tool_example_line "demo")"
                [[ "${line}" == "- demo: describe-demo (example query: run-demo)" ]]
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
