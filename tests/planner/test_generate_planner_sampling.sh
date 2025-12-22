#!/usr/bin/env bats
#
# Regression tests for multi-sample planner generation.
#
# Usage:
#   bats tests/planner/test_generate_planner_sampling.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; assertions fail the test case.

@test "generate_planner_response samples candidates and picks the best plan" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
export TOOL_REGISTRY_JSON

rm -f /tmp/planner_temperature_* /tmp/planner_candidates_test.log /tmp/planner_llama_calls

source ./src/lib/planning/planner.sh

current_date_local() { printf '2024-01-01'; }
current_time_local() { printf '12:00'; }
current_weekday_local() { printf 'Monday'; }
load_schema_text() { printf '{}'; }
format_tool_descriptions() { printf '%s' "$1"; }
build_planner_prompt_static_prefix() { static_calls=$((static_calls + 1)); printf 'PREFIX '; }
build_planner_prompt_dynamic_suffix() { suffix_calls=$((suffix_calls + 1)); printf 'SUFFIX'; }

llama_infer() {
        local call_count
        call_count=$(<"${LLAMA_CALL_COUNTER_FILE}" 2>/dev/null || printf '0')
        call_count=$((call_count + 1))
        printf '%s' "${call_count}" >"${LLAMA_CALL_COUNTER_FILE}"

        printf '%s' "${LLAMA_TEMPERATURE}" >"/tmp/planner_temperature_${call_count}"
        if [[ ${call_count} -eq 1 ]]; then
                printf '{"mode":"quickdraw","final_answer":"fast","rationale":"r"}'
        else
                printf '[{"tool":"terminal","args":{},"thought":"t"}]'
        fi
}

tool_names() { printf '%s\n' "terminal" "web_search"; }

LLAMA_AVAILABLE=true
PLANNER_WEB_SEARCH_BUDGET_CAP=2
PLANNER_SAMPLE_COUNT=2
PLANNER_TEMPERATURE=0.15
PLANNER_DEBUG_LOG="/tmp/planner_candidates_test.log"
LLAMA_CALL_COUNTER_FILE="/tmp/planner_llama_calls"
static_calls=0
suffix_calls=0

response_json="$(generate_planner_response "Run a task")"

call_count=$(<"${LLAMA_CALL_COUNTER_FILE}")

[[ "${call_count}" -eq 2 ]]
[[ "${static_calls}" -eq 1 ]]
[[ "${suffix_calls}" -eq 1 ]]
[[ -f "${PLANNER_DEBUG_LOG}" ]]
[[ "$(wc -l <"${PLANNER_DEBUG_LOG}")" -eq 2 ]]
[[ "$(grep -c '"mode":"plan"' "${PLANNER_DEBUG_LOG}")" -eq 1 ]]

jq -e '.mode == "plan"' <<<"${response_json}" >/dev/null
jq -e '.plan | length == 2' <<<"${response_json}" >/dev/null
[[ "$(cat /tmp/planner_temperature_1)" == "0.15" ]]
[[ "$(cat /tmp/planner_temperature_2)" == "0.15" ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}
