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

@test "generate_planner_response short-circuits when the first candidate is quickdraw" {
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
build_planner_prompt_static_prefix() { printf 'PREFIX '; }
build_planner_prompt_dynamic_suffix() { printf 'SUFFIX'; }

llama_infer() {
        local call_count
        call_count=$(cat "${LLAMA_CALL_COUNTER_FILE}" 2>/dev/null || printf '0')
        if [[ -z "${call_count}" ]]; then
                call_count=0
        fi
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
: >"${LLAMA_CALL_COUNTER_FILE}"

response_json="$(generate_planner_response "Run a task")"

call_count=$(<"${LLAMA_CALL_COUNTER_FILE}")

[[ "${call_count}" -eq 1 ]]
[[ -f "${PLANNER_DEBUG_LOG}" ]]
[[ "$(wc -l <"${PLANNER_DEBUG_LOG}")" -eq 1 ]]
[[ "$(grep -c '"mode":"quickdraw"' "${PLANNER_DEBUG_LOG}")" -eq 1 ]]

jq -e '.mode == "quickdraw"' <<<"${response_json}" >/dev/null
[[ "$(cat /tmp/planner_temperature_1)" == "0.15" ]]
[[ ! -f /tmp/planner_temperature_2 ]]
INNERSCRIPT
        )"
        [ "$status" -eq 0 ]
}

@test "generate_planner_response samples all candidates when the first plan uses tools" {
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
build_planner_prompt_static_prefix() { printf 'PREFIX '; }
build_planner_prompt_dynamic_suffix() { printf 'SUFFIX'; }

llama_infer() {
        local call_count
        call_count=$(cat "${LLAMA_CALL_COUNTER_FILE}" 2>/dev/null || printf '0')
        if [[ -z "${call_count}" ]]; then
                call_count=0
        fi
        call_count=$((call_count + 1))
        printf '%s' "${call_count}" >"${LLAMA_CALL_COUNTER_FILE}"

        printf '%s' "${LLAMA_TEMPERATURE}" >"/tmp/planner_temperature_${call_count}"
        if [[ ${call_count} -eq 1 ]]; then
                printf '{"mode":"plan","plan":[{"tool":"terminal","args":{},"thought":"first"},{"tool":"final_answer","args":{"input":"done"},"thought":"finish"}]}'
        else
                printf '{"mode":"plan","plan":[{"tool":"terminal","args":{},"thought":"first"},{"tool":"web_search","args":{},"thought":"lookup"},{"tool":"final_answer","args":{"input":"done"},"thought":"finish"}]}'
        fi
}

tool_names() { printf '%s\n' "terminal" "web_search"; }

LLAMA_AVAILABLE=true
PLANNER_WEB_SEARCH_BUDGET_CAP=2
PLANNER_SAMPLE_COUNT=2
PLANNER_TEMPERATURE=0.15
PLANNER_DEBUG_LOG="/tmp/planner_candidates_test.log"
LLAMA_CALL_COUNTER_FILE="/tmp/planner_llama_calls"
: >"${LLAMA_CALL_COUNTER_FILE}"

response_json="$(generate_planner_response "Run a task")"

call_count=$(<"${LLAMA_CALL_COUNTER_FILE}")

[[ "${call_count}" -eq 2 ]]
[[ -f "${PLANNER_DEBUG_LOG}" ]]
[[ "$(wc -l <"${PLANNER_DEBUG_LOG}")" -eq 2 ]]
[[ "$(grep -c '"mode":"plan"' "${PLANNER_DEBUG_LOG}")" -eq 2 ]]

jq -e '.mode == "plan"' <<<"${response_json}" >/dev/null
jq -e '.plan | length == 3' <<<"${response_json}" >/dev/null
[[ "$(cat /tmp/planner_temperature_1)" == "0.15" ]]
[[ "$(cat /tmp/planner_temperature_2)" == "0.15" ]]
INNERSCRIPT
        )"
        [ "$status" -eq 0 ]
}
