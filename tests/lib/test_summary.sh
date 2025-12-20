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

@test "render_boxed_summary builds boxed output with nested tool history" {
	lines=()
	while IFS= read -r line; do
		lines+=("$line")
	done < <(bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                tool_history=$'"'"'Step 1 action search query=weather\nObservation: sunny\nStep 2 action final_answer query=done\nObservation: finished'"'"'
                render_boxed_summary "What is new?" "Outline details" "${tool_history}" "Final thoughts"
        ')
	status=$?
	output=$(printf '%s\n' "${lines[@]}")
	[[ "${output}" == *$'│ Query:'* ]]
	[[ "${output}" == *$'What is new?'* ]]
	[[ "${output}" == *$'│ Plan:'* ]]
	[[ "${output}" == *$'Outline details'* ]]
	[[ "${output}" == *$'│ Tool runs:'* ]]
	[[ "${output}" == *$'- Step 1'* ]]
	[[ "${output}" == *$'action: search query=weather'* ]]
	[[ "${output}" == *$'observation: sunny'* ]]
	[[ "${output}" == *$'- Step 2'* ]]
	[[ "${output}" == *$'action: final_answer query=done'* ]]
	[[ "${output}" == *$'observation: finished'* ]]
	[[ "${output}" == *$'│ Final answer:'* ]]
	[[ "${output}" == *$'Final thoughts'* ]]
	[ "$status" -eq 0 ]
}

@test "render_boxed_summary handles empty tool history" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                render_boxed_summary "Question" "" "" "Answer"
        '
	[[ "${output}" == *$'│ Tool runs:'* ]]
	[[ "${output}" == *$'│   (none)'* ]]
	[ "$status" -eq 0 ]
}

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
