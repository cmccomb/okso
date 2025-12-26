#!/usr/bin/env bats

setup() {
        unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "apply_plan_arg_controls marks context args and preserves planner seeds" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

tool_args_schema() {
        printf '{"properties":{"title":{"type":"string"},"body":{"type":"string"}}}'
}

plan_entry='{"tool":"notes_create","args":{"title":"Planner Title","body":"Original body"},"args_control":{"title":"locked","body":"context"}}'
executor_args='{"title":"User Title","body":"User body"}'
user_query='Provide meeting summary'
resolved=$(apply_plan_arg_controls "notes_create" "${executor_args}" "${plan_entry}" "${user_query}" "")
jq -r '.title,.body,."__context_controlled"[0],."__context_seeds".body' <<<"${resolved}"
SCRIPT

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "Planner Title" ]
        [ "${lines[1]}" = "Original body" ]
        [ "${lines[2]}" = "body" ]
        [ "${lines[3]}" = "Original body" ]
}

@test "context args are completed via llama_infer" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh
LLAMA_AVAILABLE=true
LLAMA_PROMPT_LOG=$(mktemp)

llama_infer() {
        cat >"${LLAMA_PROMPT_LOG}" <<<"$1"
        printf '{"body":"Completed from llama"}'
}

log() {
        :
}

log_pretty() {
        :
}

tool_args_schema() {
        printf '{"type":"object","properties":{"body":{"type":"string"}}}'
}

plan_entry='{"tool":"final_answer","args":{"body":"planner seed"},"args_control":{"body":"context"}}'
executor_args='{"body":"planner seed"}'
resolved=$(resolve_action_args "final_answer" "${executor_args}" "${plan_entry}" "User request" "History snippet" "Outline" "Planner thought")
prompt=$(cat "${LLAMA_PROMPT_LOG}")
jq -r '.body' <<<"${resolved}"
printf '%s' "${prompt}"
SCRIPT

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "Completed from llama" ]
        [[ "${output}" == *"History snippet"* ]]
        [[ "${output}" == *"Planner thought"* ]]
        [[ "${output}" == *"Outline"* ]]
        [[ "${output}" == *"planner seed"* ]]
}

@test "validate_planner_action rejects disallowed tools" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh
allowed_tools=$'notes_create\nfinal_answer'
if validate_planner_action '{"tool":"unknown","args":{}}' "${allowed_tools}" 2>/tmp/validation_err; then
        exit 1
fi
cat /tmp/validation_err
SCRIPT

        [ "$status" -eq 0 ]
        [[ "${output}" == *"not permitted"* ]]
}

@test "fill_missing_args_with_llm uses llama output for context args" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh
LLAMA_AVAILABLE=true
llama_infer() {
        printf '{"title":"Filled title","body":"Filled body"}'
}
log() {
        :
}
log_pretty() {
        :
}
tool_args_schema() {
        printf '{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"}}}'
}
filled=$(fill_missing_args_with_llm "notes_create" '{"title":"User seed"}' "User question" "Outline" "Planner thought" "" '["title","body"]')
jq -r '.title,.body' <<<"${filled}"
SCRIPT

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "Filled title" ]
        [ "${lines[1]}" = "Filled body" ]
}
