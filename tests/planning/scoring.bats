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
plan='{"plan":[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"reply"}]}'
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

@test "score_planner_candidate accepts structured web_search args" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/tools/registry.sh
source ./src/tools/web/web_search.sh
source ./src/tools/final_answer/index.sh
source ./src/lib/planning/normalization.sh
source ./src/lib/planning/scoring.sh
init_tool_registry
register_web_search
register_final_answer
plan=$(jq -nc '{"plan":[{"tool":"web_search","args":{"query":"mars weather","num":2},"thought":"check"},{"tool":"final_answer","args":{"input":"done"},"thought":"respond"}]}')
normalized=$(normalize_planner_response <<<"${plan}")
scorecard=$(score_planner_candidate "${normalized}" | tail -n 1)
jq -e '.score | type == "number"' <<<"${scorecard}"
jq -e '.rationale | map(select(contains("Planner args satisfy registered tool schemas."))) | length == 1' <<<"${scorecard}"
SCRIPT

	[ "$status" -eq 0 ]
}

@test "score_planner_candidate honors web_search input alias" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/tools/registry.sh
source ./src/tools/web/web_search.sh
source ./src/tools/final_answer/index.sh
source ./src/lib/planning/normalization.sh
source ./src/lib/planning/scoring.sh
init_tool_registry
register_web_search
register_final_answer
plan=$(jq -nc '{"plan":[{"tool":"web_search","args":{"input":"mars weather"},"thought":"check"},{"tool":"final_answer","args":{"input":"done"},"thought":"respond"}]}')
normalized=$(normalize_planner_response <<<"${plan}")
scorecard=$(score_planner_candidate "${normalized}" | tail -n 1)
jq -e '.rationale | map(select(contains("Planner args satisfy registered tool schemas."))) | length == 1' <<<"${scorecard}"
SCRIPT

	[ "$status" -eq 0 ]
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
valid='{"plan":[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"finish"}]}'
invalid='{"plan":[{"tool":"missing_tool","args":{"command":5},"thought":"broken"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"finish"}]}'
good=$(score_planner_candidate "${valid}" | tail -n 1 | jq -r '.score')
bad=$(score_planner_candidate "${invalid}" | tail -n 1 | jq -r '.score')
printf "good=%s\n" "${good}"
printf "bad=%s\n" "${bad}"
SCRIPT

	[ "$status" -eq 0 ]
	good=$(printf '%s\n' "${output}" | grep '^good=' | tail -n 1 | cut -d= -f2)
	bad=$(printf '%s\n' "${output}" | grep '^bad=' | tail -n 1 | cut -d= -f2)
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
unsafe_first='{"plan":[{"tool":"notes_create","args":{"title":"t"},"thought":"start"},{"tool":"web_search","args":{"query":"topic"},"thought":"research"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"summarize"}]}'
safer_first='{"plan":[{"tool":"web_search","args":{"query":"topic"},"thought":"research"},{"tool":"notes_create","args":{"title":"t"},"thought":"capture"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"summarize"}]}'
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

@test "score_planner_candidate treats read-only terminal steps as informational" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" terminal notes_create final_answer; }
tool_args_schema() {
        if [[ "$1" == "terminal" ]]; then
                jq -nc '{"type":"object","required":["command"],"properties":{"command":{"type":"string"}},"additionalProperties":false}'
        else
                printf '{}'
        fi
}
plan='{"plan":[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"notes_create","args":{"title":"t"},"thought":"note"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"finish"}]}'
scorecard=$(score_planner_candidate "${plan}" | tail -n 1)
printf '%s\n' "${scorecard}"
SCRIPT

	[ "$status" -eq 0 ]
	rationale=$(printf '%s' "${output}" | tail -n 1 | jq -r '.rationale | join(" ")')
	[[ "${rationale}" == *"Side-effecting actions are deferred until step 2."* ]]
}

@test "score_planner_candidate penalizes mutating terminal steps immediately" {
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
plan='{"plan":[{"tool":"terminal","args":{"command":"rm -rf /tmp/demo"},"thought":"cleanup"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"finish"}]}'
scorecard=$(score_planner_candidate "${plan}" | tail -n 1)
printf '%s\n' "${scorecard}"
SCRIPT

	[ "$status" -eq 0 ]
	rationale=$(printf '%s' "${output}" | tail -n 1 | jq -r '.rationale | join(" ")')
	[[ "${rationale}" == *"First step is side-effecting before gathering information."* ]]
}

@test "score_planner_candidate emits informative INFO logs" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=1
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" terminal final_answer; }
tool_args_schema() { printf '{}'; }
plan='{"plan":[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"finish"}]}'
score_planner_candidate "${plan}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"Planner scoring summary"* ]]
}
