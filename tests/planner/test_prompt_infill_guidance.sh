#!/usr/bin/env bats
#
# Tests for planner prompt infill guidance.
#
# Usage:
#   bats tests/planner/test_prompt_infill_guidance.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "planner prompt instructs use of executor infill placeholder" {
	run bash -lc '
                set -euo pipefail
                cd "$(git rev-parse --show-toplevel)" || exit 1
                export PLANNER_SKIP_TOOL_LOAD=true
                source ./src/lib/planning/planner.sh

                log() { :; }
                log_pretty() { :; }

                prompt="$(build_planner_prompt "Summarize" "tool: demo" "none")"
                grep -q "\\$Q" <<<"${prompt}"
        '
	[ "$status" -eq 0 ]
}
