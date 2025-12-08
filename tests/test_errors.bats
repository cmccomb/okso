#!/usr/bin/env bats
#
# Focused tests for shared error envelope helpers.
#
# Usage: bats tests/test_errors.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "die surfaces exit codes from failed pipelines" {
	run bash -lc '
                set -o pipefail
                source ./src/errors.sh
                ERROR_CONTEXT="runtime"

                { false | true; } || die "${ERROR_CONTEXT}" "pipeline" "upstream pipeline failure" 17
        '

	[ "$status" -eq 17 ]
	[[ "$output" == *'"name":"runtime"'* ]]
	[[ "$output" == *'"category":"pipeline"'* ]]
	[[ "$output" == *'"message":"upstream pipeline failure"'* ]]
}

@test "die exits from subshells with serialized envelope" {
	run bash -lc '
                source ./src/errors.sh

                (die "tool_runner" "fatal" "subshell explosion" 23)
        '

	[ "$status" -eq 23 ]
	[[ "$output" == *'"name":"tool_runner"'* ]]
	[[ "$output" == *'"category":"fatal"'* ]]
	[[ "$output" == *'"message":"subshell explosion"'* ]]
}
