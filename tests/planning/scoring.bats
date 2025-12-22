#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "score_planner_candidate rewards registered tools with satisfiable args" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" terminal final_answer; }
tool_args_schema() {
        if [[ "$1" == "terminal" ]]; then
                jq -nc '{"type":"object","required":["command"],"properties":{"command":{"type":"string"}},"additionalProperties":false}'
        else
                printf '{}'
        fi
}
plan='{"mode":"plan","plan":[{"tool":"terminal","args":{"command":"ls"},"thought":""},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}'
scorecard=$(score_planner_candidate "${plan}" | tail -n 1)
printf '%s\n' "${scorecard}"
SCRIPT

	[ "$status" -eq 0 ]
	scorecard=$(printf '%s\n' "${output}" | tail -n 1)
	score=$(printf '%s' "${scorecard}" | jq -r '.score')
	rationale=$(printf '%s' "${scorecard}" | jq -r '.rationale | join(" ")')
	[[ "${score}" -gt 0 ]]
	[[ "${rationale}" == *"final_answer"* ]]
}

@test "score_planner_candidate penalizes unavailable tools and bad args" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" terminal final_answer; }
tool_args_schema() {
        if [[ "$1" == "terminal" ]]; then
                jq -nc '{"type":"object","required":["command"],"properties":{"command":{"type":"string"}},"additionalProperties":false}'
        else
                printf '{}'
        fi
}
valid='{"mode":"plan","plan":[{"tool":"terminal","args":{"command":"ls"},"thought":""},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}'
invalid='{"mode":"plan","plan":[{"tool":"missing_tool","args":{"command":5}},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}'
good=$(score_planner_candidate "${valid}" | tail -n 1 | jq -r '.score')
bad=$(score_planner_candidate "${invalid}" | tail -n 1 | jq -r '.score')
printf "good=%s\n" "${good}"
printf "bad=%s\n" "${bad}"
SCRIPT

	[ "$status" -eq 0 ]
	good=$(printf '%s' "${lines[0]}" | cut -d= -f2)
	bad=$(printf '%s' "${lines[1]}" | cut -d= -f2)
	[[ "${good}" -gt "${bad}" ]]
}

@test "score_planner_candidate prefers plans that defer side effects" {
	run bash <<'SCRIPT'
set -euo pipefail
export PLANNER_MAX_PLAN_STEPS=4
export VERBOSITY=0
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" web_search notes_create final_answer; }
tool_args_schema() { printf '{}'; }
unsafe_first='{"mode":"plan","plan":[{"tool":"notes_create","args":{},"thought":"start"},{"tool":"web_search","args":{},"thought":"research"},{"tool":"final_answer","args":{},"thought":"summarize"}],"quickdraw":null}'
safer_first='{"mode":"plan","plan":[{"tool":"web_search","args":{},"thought":"research"},{"tool":"notes_create","args":{},"thought":"capture"},{"tool":"final_answer","args":{},"thought":"summarize"}],"quickdraw":null}'
unsafe_score=$(score_planner_candidate "${unsafe_first}" | tail -n 1 | jq -r '.score')
safer_score=$(score_planner_candidate "${safer_first}" | tail -n 1 | jq -r '.score')
printf "unsafe=%s\n" "${unsafe_score}"
printf "safer=%s\n" "${safer_score}"
SCRIPT

	[ "$status" -eq 0 ]
	unsafe=$(printf '%s' "${lines[0]}" | cut -d= -f2)
	safer=$(printf '%s' "${lines[1]}" | cut -d= -f2)
	[[ "${safer}" -gt "${unsafe}" ]]
}

@test "score_planner_candidate emits informative INFO logs" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=1
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" terminal final_answer; }
tool_args_schema() { printf '{}'; }
plan='{"mode":"plan","plan":[{"tool":"terminal","args":{},"thought":""},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}'
score_planner_candidate "${plan}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"Planner scoring summary"* ]]
}
