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

@test "generate_planner_response skips invalid non-plan candidates and continues sampling" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
export TOOL_REGISTRY_JSON
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD

rm -f /tmp/planner_temperature_* /tmp/planner_candidates_test.log /tmp/planner_llama_calls \
        /tmp/planner_model_repo_arg /tmp/planner_model_file_arg \
        /tmp/react_model_repo_arg /tmp/react_model_file_arg

source ./src/lib/planning/planner.sh

PLANNER_MODEL_REPO=""
PLANNER_MODEL_FILE=""
REACT_MODEL_REPO=""
REACT_MODEL_FILE=""

current_date_local() { printf '2024-01-01'; }
current_time_local() { printf '12:00'; }
current_weekday_local() { printf 'Monday'; }
load_schema_text() { printf '{}'; }
format_tool_descriptions() { printf '%s' "$1"; }
build_planner_prompt_static_prefix() { printf 'PREFIX '; }
build_planner_prompt_dynamic_suffix() { printf 'SUFFIX'; }
planner_fetch_search_context() { printf 'SEARCH'; }

llama_infer() {
        local call_count
        call_count=$(cat "${LLAMA_CALL_COUNTER_FILE}" 2>/dev/null || printf '0')
        if [[ -z "${call_count}" ]]; then
                call_count=0
        fi
        call_count=$((call_count + 1))
        printf '%s' "${call_count}" >"${LLAMA_CALL_COUNTER_FILE}"

        printf '%s' "$5" >/tmp/planner_model_repo_arg
        printf '%s' "$6" >/tmp/planner_model_file_arg
        printf '%s' "${REACT_MODEL_REPO}" >/tmp/react_model_repo_arg
        printf '%s' "${REACT_MODEL_FILE}" >/tmp/react_model_file_arg

        printf '%s' "${LLAMA_TEMPERATURE}" >"/tmp/planner_temperature_${call_count}"
        if [[ ${call_count} -eq 1 ]]; then
        printf '{"mode":"quickdraw","final_answer":"fast","rationale":"r"}'
        else
                printf '[{"tool":"terminal","args":{"command":"ls"},"thought":"t"}]'
        fi
}

tool_names() { printf '%s\n' "terminal" "web_search"; }

LLAMA_AVAILABLE=true
PLANNER_SAMPLE_COUNT=2
PLANNER_TEMPERATURE=0.15
PLANNER_DEBUG_LOG="/tmp/planner_candidates_test.log"
LLAMA_CALL_COUNTER_FILE="/tmp/planner_llama_calls"
: >"${LLAMA_CALL_COUNTER_FILE}"

response_json="$(generate_planner_response "Run a task")"

call_count=$(<"${LLAMA_CALL_COUNTER_FILE}")

[[ "${call_count}" -eq 2 ]]
[[ -f "${PLANNER_DEBUG_LOG}" ]]
[[ "$(wc -l <"${PLANNER_DEBUG_LOG}")" -eq 1 ]]
jq -e '.plan | type == "array"' <<<"${response_json}" >/dev/null
[[ "$(cat /tmp/planner_model_repo_arg)" == "${DEFAULT_PLANNER_MODEL_REPO_BASE}" ]]
[[ "$(cat /tmp/planner_model_file_arg)" == "${DEFAULT_PLANNER_MODEL_FILE_BASE}" ]]
[[ "$(cat /tmp/react_model_repo_arg)" == "${DEFAULT_MODEL_REPO_BASE}" ]]
[[ "$(cat /tmp/react_model_file_arg)" == "${DEFAULT_MODEL_FILE_BASE}" ]]
[[ "$(cat /tmp/planner_temperature_1)" == "0.15" ]]
[[ "$(cat /tmp/planner_temperature_2)" == "0.15" ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}

@test "generate_planner_response performs pre-plan search once per session" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
export TOOL_REGISTRY_JSON
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD

rm -f /tmp/preplan_calls /tmp/preplan_context /tmp/preplan_llama_calls

source ./src/lib/planning/planner.sh

current_date_local() { printf '2024-01-01'; }
current_time_local() { printf '12:00'; }
current_weekday_local() { printf 'Monday'; }
load_schema_text() { printf '{}'; }
format_tool_descriptions() { printf '%s' "$1"; }
build_planner_prompt_static_prefix() { printf 'PREFIX '; }
build_planner_prompt_dynamic_suffix() { printf '%s' "$3" > /tmp/preplan_context; printf 'SUFFIX'; }
planner_fetch_search_context() {
        local count
        count=$(cat /tmp/preplan_calls 2>/dev/null || printf '0')
        count=$((count + 1))
        printf '%s' "${count}" >/tmp/preplan_calls
        printf 'Harvested search notes'
}

llama_infer() {
        local call_count
        call_count=$(cat "${LLAMA_CALL_COUNTER_FILE}" 2>/dev/null || printf '0')
        if [[ -z "${call_count}" ]]; then
                call_count=0
        fi
        call_count=$((call_count + 1))
        printf '%s' "${call_count}" >"${LLAMA_CALL_COUNTER_FILE}"

        printf '{"plan":[{"tool":"terminal","args":{"command":"ls"},"thought":"first"},{"tool":"final_answer","args":{"input":"done"},"thought":"finish"}]}'
}

tool_names() { printf '%s\n' "terminal" "web_search"; }

LLAMA_AVAILABLE=true
PLANNER_SAMPLE_COUNT=2
PLANNER_TEMPERATURE=0.15
LLAMA_CALL_COUNTER_FILE="/tmp/preplan_llama_calls"
: >"${LLAMA_CALL_COUNTER_FILE}"

generate_planner_response "Find updates"

[[ "$(cat /tmp/preplan_calls)" -eq 1 ]]
[[ "$(cat /tmp/preplan_context)" == "Harvested search notes" ]]
[[ "$(cat /tmp/preplan_llama_calls)" -eq 2 ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}
