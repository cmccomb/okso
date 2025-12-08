#!/usr/bin/env bats
#
# Tests for planning and ReAct helpers.
#
# Usage:
#   bats tests/test_planner.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

@test "extract_tools_from_plan dedupes and enforces final_answer" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/planner.sh; TOOLS=(alpha beta final_answer); plan=$"1. Use Alpha\n2. Use alpha\n3. Then beta"; mapfile -t tools < <(extract_tools_from_plan "${plan}"); [[ ${#tools[@]} -eq 3 ]]; [[ "${tools[0]}" == "alpha" ]]; [[ "${tools[1]}" == "beta" ]]; [[ "${tools[2]}" == "final_answer" ]]'
	[ "$status" -eq 0 ]
}

@test "build_plan_entries_from_tools omits final_answer" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/planner.sh; entries=$(build_plan_entries_from_tools $'"'"'alpha\nbeta\nfinal_answer'"'"' "Tell me"); first=$(printf "%s" "${entries}" | sed -n "1p"); second=$(printf "%s" "${entries}" | sed -n "2p"); [[ "${first}" == "alpha|Tell me|0" ]]; [[ "${second}" == "beta|Tell me|0" ]]; [[ "${entries}" != *"final_answer"* ]]'
	[ "$status" -eq 0 ]
}

@test "should_prompt_for_tool respects execution toggles" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/planner.sh; PLAN_ONLY=true DRY_RUN=false APPROVE_ALL=false FORCE_CONFIRM=false should_prompt_for_tool; first=$?; PLAN_ONLY=false DRY_RUN=false APPROVE_ALL=true FORCE_CONFIRM=false should_prompt_for_tool; second=$?; PLAN_ONLY=false DRY_RUN=false APPROVE_ALL=false FORCE_CONFIRM=true should_prompt_for_tool; third=$?; [[ ${first} -eq 1 ]]; [[ ${second} -eq 1 ]]; [[ ${third} -eq 0 ]]'
	[ "$status" -eq 0 ]
}

@test "initialize_react_state seeds defaults" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/planner.sh; declare -A state; initialize_react_state state "answer me" $"alpha" "alpha|query|0" "1. alpha"; [[ "${state[user_query]}" == "answer me" ]]; [[ "${state[allowed_tools]}" == "alpha" ]]; [[ "${state[plan_index]}" == "0" ]]; [[ "${state[max_steps]}" -eq ${MAX_STEPS:-6} ]]'
	[ "$status" -eq 0 ]
}

@test "validate_tool_permission records disallowed tools" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/planner.sh; declare -A state; initialize_react_state state "answer me" $"alpha" "" "1. alpha"; validate_tool_permission state beta; [[ "$?" -eq 1 ]]; [[ "${state[history]}" == *"not permitted"* ]]'
	[ "$status" -eq 0 ]
}
