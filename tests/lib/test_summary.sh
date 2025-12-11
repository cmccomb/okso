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

@test "render_boxed_summary builds boxed output with sections" {
        mapfile -t lines < <(bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/formatting.sh
                tool_history=$'"'"'step1\nstep2'"'"'
                render_boxed_summary "What is new?" "Outline details" "${tool_history}" "Final thoughts"
        ')
        status=$?
        output="${lines[*]}"
        [[ "${output}" == *"Query:"* ]]
        [[ "${output}" == *"Plan:"* ]]
        [[ "${output}" == *"Tool runs:"* ]]
        [[ "${output}" == *"Final answer:"* ]]
        if ! [[ "${output}" == *"step1"* && "${output}" == *"step2"* ]]; then
                echo "DEBUG output: ${output}" >&2
        fi
        [[ "${output}" == *"step1"* && "${output}" == *"step2"* ]]
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
