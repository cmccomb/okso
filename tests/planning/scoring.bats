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
plan='{"mode":"plan","plan":[{"tool":"terminal","args":{"command":"ls"}},{"tool":"notes_create","args":{},"thought":""},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}'
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
plan='{"mode":"plan","plan":[{"tool":"terminal","args":{"command":"rm -rf /tmp/demo"},"thought":""},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}'
scorecard=$(score_planner_candidate "${plan}" | tail -n 1)
printf '%s\n' "${scorecard}"
SCRIPT

	[ "$status" -eq 0 ]
	rationale=$(printf '%s' "${output}" | tail -n 1 | jq -r '.rationale | join(" ")')
	[[ "${rationale}" == *"First step is side-effecting before gathering information."* ]]
}

@test "python_repl_has_side_effects treats informational snippets as non-mutating" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/scoring.sh
set +e
python_repl_has_side_effects '{"code":"print(2+2)"}'
print_status=$?
python_repl_has_side_effects '{"code":"import math\nmath.sqrt(4)"}'
math_status=$?
set -e
printf '%s\n' "${print_status}" "${math_status}"
SCRIPT

	[ "$status" -eq 0 ]
	print_status=${lines[0]}
	math_status=${lines[1]}
	[[ "${print_status}" -eq 1 ]]
	[[ "${math_status}" -eq 1 ]]
}

@test "score_planner_candidate treats informational python_repl as informational" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" python_repl final_answer; }
tool_args_schema() { printf '{}'; }
plan=$(jq -nc '{"mode":"plan","plan":[{"tool":"python_repl","args":{"code":"print(2+2)"},"thought":""},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}')
scorecard=$(score_planner_candidate "${plan}" | tail -n 1)
printf '%s\n' "${scorecard}"
SCRIPT

	[ "$status" -eq 0 ]
	rationale=$(printf '%s' "${output}" | tail -n 1 | jq -r '.rationale | join(" ")')
	[[ "${rationale}" == *"No side-effecting tools detected in the plan."* ]]
}

@test "score_planner_candidate penalizes mutating python_repl steps" {
	run bash <<'SCRIPT'
set -euo pipefail
export VERBOSITY=0
source ./src/lib/planning/scoring.sh
tool_names() { printf "%s\n" python_repl final_answer; }
tool_args_schema() { printf '{}'; }
mutating_snippets=(
        '{"code":"open(\"x.txt\",\"w\").write(\"hi\")"}'
        '{"code":"from pathlib import Path\nPath(\"a\").write_text(\"x\")"}'
        '{"code":"import subprocess\nsubprocess.run([\"echo\",\"hi\"])"}'
        '{"code":"import requests\nrequests.get(\"https://example.com\")"}'
)

for snippet in "${mutating_snippets[@]}"; do
        plan=$(jq -nc --argjson args "${snippet}" '{"mode":"plan","plan":[{"tool":"python_repl","args":$args,"thought":""},{"tool":"final_answer","args":{},"thought":""}],"quickdraw":null}')
        rationale=$(score_planner_candidate "${plan}" | tail -n 1 | jq -r '.rationale | join(" ")')
        printf '%s\n' "${rationale}"
done
SCRIPT

	[ "$status" -eq 0 ]
	for line in "${lines[@]}"; do
		[[ "${line}" == *"First step is side-effecting before gathering information."* ]]
	done
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
