#!/usr/bin/env bats
#
# Regression tests for generate_planner_response prompt construction.
#
# Usage:
#   bats tests/planner/test_generate_planner_response.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; assertions fail the test case.

@test "generate_planner_response includes web_search budget constraints" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

current_date_local() { printf '2024-01-01'; }
current_time_local() { printf '12:00'; }
current_weekday_local() { printf 'Monday'; }
load_schema_text() { printf '{}'; }

llama_infer() {
        printf '%s' "$1" > /tmp/planner_prompt_budget_constraints
        printf '[]'
}

tool_names() { printf '%s\n' "web_search"; }

LLAMA_AVAILABLE=true
PLANNER_WEB_SEARCH_BUDGET_CAP=2
export PLANNER_WEB_SEARCH_BUDGET_CAP

generate_planner_response "Find facts"

prompt="$(cat /tmp/planner_prompt_budget_constraints)"

[[ "${prompt}" == *"at most 2 short, targeted queries"* ]]
[[ "${prompt}" == *"may not include more than 2 web_search steps"* ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}

@test "generate_planner_response surfaces web_search budget in tool list" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planning/planner.sh

current_date_local() { printf '2024-01-01'; }
current_time_local() { printf '12:00'; }
current_weekday_local() { printf 'Monday'; }
load_schema_text() { printf '{}'; }

llama_infer() {
        printf '%s' "$1" > /tmp/planner_prompt_budget_tools
        printf '[]'
}

tool_names() { printf '%s\n' "terminal" "web_search"; }

LLAMA_AVAILABLE=true
PLANNER_WEB_SEARCH_BUDGET_CAP=2
export PLANNER_WEB_SEARCH_BUDGET_CAP

generate_planner_response "Find docs"

prompt="$(cat /tmp/planner_prompt_budget_tools)"

[[ "${prompt}" == *"- web_search: Budget: up to 2 searches per plan"* ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}
