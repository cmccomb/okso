#!/usr/bin/env bats
#
# Tests for boxed summary formatting helpers.
#
# Usage:
#   bats tests/lib/test_summary.sh
#
# Dependencies:
#   - bats
#   - bash 5+

@test "render_boxed_summary builds boxed output with nested tool history" {
        mapfile -t lines < <(bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                tool_history=$'"'"'Step 1 action search query=weather\nObservation: sunny\nStep 2 action final_answer query=done\nObservation: finished'"'"'
                render_boxed_summary "What is new?" "Outline details" "${tool_history}" "Final thoughts"
        ')
        status=$?
        output="${lines[*]}"
        [[ "${output}" == *"Query:"* ]]
        [[ "${output}" == *"Plan:"* ]]
        [[ "${output}" == *"Tool runs:"* ]]
        [[ "${output}" == *"Final answer:"* ]]
        [[ "${output}" == *"- Step 1"* ]]
        [[ "${output}" == *"action: search query=weather"* ]]
        [[ "${output}" == *"observation: sunny"* ]]
        [[ "${output}" == *"- Step 2"* ]]
        [[ "${output}" == *"action: final_answer query=done"* ]]
        [[ "${output}" == *"observation: finished"* ]]
        [ "$status" -eq 0 ]
}

@test "render_boxed_summary handles empty tool history" {
        run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                render_boxed_summary "Question" "" "" "Answer"
        '
	[[ "${output}" == *"(none)"* ]]
	[ "$status" -eq 0 ]
}
