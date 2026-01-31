#!/usr/bin/env bats
#
# Tests for CLI output helpers.
#
# Usage:
#   bats tests/lib/test_output.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "render_step_box prints title before duration" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/cli/output.sh
COLUMNS=40
header="$(render_step_box "Plan Iteration" "00:01" "body" | sed -n '2p')"
[[ "${header}" =~ Plan\ Iteration.*00:01 ]]
SCRIPT

	[ "$status" -eq 0 ]
}
