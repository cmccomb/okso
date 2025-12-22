#!/usr/bin/env bats
#
# Tests for enforcing the planner web_search budget during ReAct execution.
#
# Usage:
#   bats tests/lib/test_web_search_budget.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "enforce_web_search_budget blocks over-cap searches" {
	run bash -s <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
export VERBOSITY=0
source ./src/lib/react/history.sh
source ./src/lib/react/loop.sh
state_prefix="budget_state"
PLANNER_WEB_SEARCH_BUDGET=1
initialize_react_state "${state_prefix}" "query" "web_search" "[]" "outline"
if enforce_web_search_budget "${state_prefix}" "web_search" 1; then
        echo "first_allowed"
fi
if ! enforce_web_search_budget "${state_prefix}" "web_search" 2; then
        echo "second_blocked"
fi
history=$(state_get "${state_prefix}" "history")
printf 'history=%s\n' "${history}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"first_allowed"* ]]
	[[ "${output}" == *"second_blocked"* ]]
	[[ "${output}" == *"web_search budget exceeded"* ]]
}
