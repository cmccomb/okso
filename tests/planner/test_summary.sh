#!/usr/bin/env bats
#
# Tests for planner summary emission.
#
# Usage:
#   bats tests/planner/test_summary.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "finalize_executor_result emits boxed summary" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/planning/planner.sh
                # Silence structured logs for assertion clarity.
                log() { :; }
                log_pretty() { :; }

                state_prefix="summary_state"
                initialize_executor_state "${state_prefix}" "Do something" "tool-a" "" "Plan outline"
                state_append_history "${state_prefix}" "tool-a did work"
                state_set "${state_prefix}" "final_answer" "All done"

                output="$(finalize_executor_result "${state_prefix}")"
                [[ "${output}" == *"Do something"* ]]
                [[ "${output}" == *"Plan outline"* ]]
                [[ "${output}" == *"tool-a did work"* ]]
                [[ "${output}" == *"All done"* ]]
        '
	[ "$status" -eq 0 ]
}
