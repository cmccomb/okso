#!/usr/bin/env bats
#
# Tests for JSON-backed state helpers.
#
# Usage:
#   bats tests/lib/test_state.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper behaviour.

@test "state helpers persist values and history" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/state.sh
                prefix=state_case
                state_set "${prefix}" "foo" "bar"
                [[ "$(state_get "${prefix}" "foo")" == "bar" ]]
                state_increment "${prefix}" "counter" 2
                state_increment "${prefix}" "counter"
                [[ "$(state_get "${prefix}" "counter")" == "3" ]]
                state_append_history "${prefix}" "entry one"
                state_append_history "${prefix}" "entry two"
                [[ "$(state_get "${prefix}" "history")" == $'"'"'entry one\nentry two'"'"' ]]
        '
	[ "$status" -eq 0 ]
}
