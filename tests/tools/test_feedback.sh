#!/usr/bin/env bats
#
# Tests for the feedback collection tool.
#
# Usage:
#   bats tests/tools/test_feedback.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#   - jq
#
# Exit codes:
#   Inherits Bats semantics; individual cases assert tool behaviour.

@test "register_feedback adds tool metadata" {
        run bash -lc '
                cd "$(git rev-parse --show-toplevel)" &&
                source ./src/lib/tools.sh &&
                init_tool_registry &&
                register_feedback &&
                [[ "$(tool_description feedback)" == *"rating"* ]] &&
                [[ "$(tool_command feedback)" == "feedback <json context>" ]]
        '
        [ "$status" -eq 0 ]
}

@test "feedback respects opt-out" {
        run bash -lc '
                cd "$(git rev-parse --show-toplevel)" &&
                source ./src/lib/tools.sh &&
                TOOL_QUERY="{\"plan_item\":\"review notes\",\"observations\":\"done\"}" \
                        FEEDBACK_ENABLED=false tool_feedback
        '
        [ "$status" -eq 0 ]
        [[ "${output}" == *"\"status\":\"skipped\""* ]]
}

@test "feedback records rating and writes payload" {
        run bash -lc '
                set -e
                cd "$(git rev-parse --show-toplevel)"
                source ./src/lib/tools.sh
                TOOL_QUERY="{\"plan_item\":\"draft summary\",\"observations\":\"created outline\"}"
                FEEDBACK_NONINTERACTIVE_INPUT="5|ship it"
                FEEDBACK_OUTPUT_PATH="${HOME}/.okso/test-feedback.json"
                rm -f -- "${FEEDBACK_OUTPUT_PATH}"
                payload=$(tool_feedback)
                jq -e ".rating == 5 and .comment == \"ship it\" and .plan_item == \"draft summary\"" <<<"${payload}"
                jq -e ".status == \"recorded\"" "${FEEDBACK_OUTPUT_PATH}"
        '
        [ "$status" -eq 0 ]
}
