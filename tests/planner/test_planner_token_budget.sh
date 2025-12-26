#!/usr/bin/env bats
#
# Regression tests for the planner token budget handling.
#
# Usage:
#   bats tests/planner/test_planner_token_budget.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "planner token budget honors override" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD

source ./src/lib/planning/planner.sh

build_planner_prompt_static_prefix() { printf 'PREFIX'; }
build_planner_prompt_dynamic_suffix() { printf 'SUFFIX'; }
load_schema_text() { printf '{}'; }
planner_fetch_search_context() { printf 'context'; }
normalize_planner_response() { cat; }
score_planner_candidate() { printf '{"score":1,"tie_breaker":0,"rationale":[]}'; }

llama_infer() {
        printf '%s' "$3" > /tmp/planner_token_budget_override
        printf '[{"tool":"final_answer","args":{"input":"done"},"thought":"done"}]'
}

LLAMA_AVAILABLE=true
PLANNER_SAMPLE_COUNT=1
PLANNER_MAX_OUTPUT_TOKENS=1024
export PLANNER_MAX_OUTPUT_TOKENS

if ! generate_planner_response "Need more tokens"; then
        echo "planner generation failed"
        exit 1
fi

expected="1024"
actual="$(cat /tmp/planner_token_budget_override)"

[[ "${actual}" == "${expected}" ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}
