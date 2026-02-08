#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for CLI output helpers.
#
# Usage:
#   bats tests/lib/test_output.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "render_step_box emits only in trace mode" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/cli/output.sh
without_trace="$(render_step_box "Plan Iteration" "00:01" "body" 2>&1)"
[[ -z "${without_trace}" ]]
OKSO_TRACE=1
with_trace="$(render_step_box "Plan Iteration" "00:01" "body" 2>&1)"
[[ "${with_trace}" == *"trace: Plan Iteration"* ]]
[[ "${with_trace}" == *"00:01"* ]]
SCRIPT

	[ "$status" -eq 0 ]
}
