#!/usr/bin/env bats
#
# Tests for boxed summary formatting helpers.
#
# Usage:
#   bats tests/lib/test_summary.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "format_tool_history is idempotent and avoids double-dashes" {
	run bash -lc '
                set -e
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                
                # Input that looks like it was already formatted (e.g. from previous run or weird state)
                history=$(printf -- " -  - Step 1\n  action: search\n  observation: result")
                output=$(format_tool_history "${history}")
                
                # Should NOT have quadruple dashes or double actions
                [[ "${output}" == "- Step 1"* ]]
                [[ "${output}" == *"action: search"* ]]
                [[ "${output}" == *"observation: result"* ]]
                
                # Re-formatting should be stable
                output2=$(format_tool_history "${output}")
                [[ "${output2}" == "${output}" ]]
        '
	[ "$status" -eq 0 ]
}
