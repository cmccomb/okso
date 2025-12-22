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

@test "generate_planner_response omits web_search caps" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
export TOOL_REGISTRY_JSON
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD

source ./src/lib/planning/planner.sh

current_date_local() { printf '2024-01-01'; }
current_time_local() { printf '12:00'; }
current_weekday_local() { printf 'Monday'; }
load_schema_text() { printf '{}'; }
planner_fetch_search_context() { printf 'Search context unavailable.'; }

llama_infer() {
        printf '%s' "$1" > /tmp/planner_prompt_budget_constraints
        printf '[]'
}

tool_names() { printf '%s\n' "web_search"; }

LLAMA_AVAILABLE=true

generate_planner_response "Find facts"

prompt="$(cat /tmp/planner_prompt_budget_constraints)"

[[ "${prompt}" != *"web_search discipline"* ]]
[[ "${prompt}" != *"Cap web_search"* ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}

@test "generate_planner_response lists tools without web_search caps" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
export TOOL_REGISTRY_JSON
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD

source ./src/lib/planning/planner.sh

current_date_local() { printf '2024-01-01'; }
current_time_local() { printf '12:00'; }
current_weekday_local() { printf 'Monday'; }
load_schema_text() { printf '{}'; }
planner_fetch_search_context() { printf 'Search context unavailable.'; }

llama_infer() {
        printf '%s' "$1" > /tmp/planner_prompt_budget_tools
        printf '[]'
}

tool_names() { printf '%s\n' "terminal" "web_search"; }

LLAMA_AVAILABLE=true

generate_planner_response "Find docs"

prompt="$(cat /tmp/planner_prompt_budget_tools)"

[[ "${prompt}" != *"Budget: up to"* ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}
