#!/usr/bin/env bats
#
# Regression tests for generate_plan_outline.
#
# Usage:
#   bats tests/planner/test_generate_plan_outline.sh
#
# Dependencies:
#   - bats
#   - bash 5+

@test "generate_plan_outline works when mapfile builtin is unavailable" {
        run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                enable -n mapfile 2>/dev/null || true

                source ./src/lib/planner.sh

                log() { :; }

                LLAMA_AVAILABLE=false
                output="$(generate_plan_outline "Summarize request")"
                [[ "${output}" == "1. Use final_answer to respond directly to the user request." ]]
        '
        [ "$status" -eq 0 ]
}
