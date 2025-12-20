#!/usr/bin/env bats

setup() {
        unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "normalize_planner_plan extracts JSON arrays from mixed text output" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
raw_plan=$'Here is the plan:\n[{"tool":"terminal","args":{"command":"pwd"},"thought":"check"}]\nThanks!'
normalize_planner_plan <<<"${raw_plan}" | jq -r '.[0].tool,.[0].args.command,.[0].thought'
SCRIPT

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "terminal" ]
        [ "${lines[1]}" = "pwd" ]
        [ "${lines[2]}" = "check" ]
}

@test "append_final_answer_step adds missing summary step without duplication" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
without_final=$(append_final_answer_step "[{\"tool\":\"terminal\",\"args\":{},\"thought\":\"list\"}]")
with_final=$(append_final_answer_step "[{\"tool\":\"final_answer\",\"args\":{},\"thought\":\"done\"}]")
printf "%s\n---\n%s\n" "${without_final}" "${with_final}"
SCRIPT

        [ "$status" -eq 0 ]
        first_tools=$(printf '%s' "${lines[0]}" | jq -r '.[].tool')
        [[ "${first_tools}" == *"final_answer" ]]
        second_tools=$(printf '%s' "${lines[2]}" | jq -r '.[].tool')
        [ "${second_tools}" = "final_answer" ]
        second_thought=$(printf '%s' "${lines[2]}" | jq -r '.[0].thought')
        [ "${second_thought}" = "done" ]
}

@test "normalize_planner_plan rejects unstructured outline text" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/normalization.sh
normalize_planner_plan <<<"1) first step\n- second step"
SCRIPT

        [ "$status" -ne 0 ]
        [[ "${output}" == *"unable to parse planner output"* ]]
}
