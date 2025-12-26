#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "resolve_action_args normalizes once while filling context args" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

log() {
        :
}

normalize_log=$(mktemp)
normalize_args_json() {
        printf 'normalize\n' >>"${normalize_log}"
        printf '%s' "$1"
}

apply_plan_arg_controls() {
        printf '{"title":"seed","__context_controlled":["title"]}'
}

fill_missing_args_with_llm() {
        printf '{"title":"filled","body":"done"}'
}

tool_args_schema() { printf '{}'; }

resolved=$(resolve_action_args "notes_create" '{"title":"pending"}' '{"args_control":{}}' "User" "" "Outline" "Thought")
normalize_calls=$(wc -l <"${normalize_log}")
printf 'resolved=%s\nnormalizations=%s\n' "${resolved}" "${normalize_calls}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *'"title":"filled"'* ]]
	[[ "${lines[0]}" == *'"body":"done"'* ]]
	[ "${lines[1]}" = "normalizations=1" ]
}

@test "resolve_action_args skips LLM when args complete" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

log() {
        :
}

fill_missing_args_with_llm() {
        echo "llm_called" >>/tmp/llm_log
        printf '{}'
}

apply_plan_arg_controls() {
        printf '{"title":"ready"}'
}

normalize_args_json() {
        printf '%s' "$1"
}

resolved=$(resolve_action_args "notes_create" '{"title":"ready"}' '{"args_control":{}}' "User" "" "Outline" "Thought")
llm_calls=0
if [[ -f /tmp/llm_log ]]; then
        llm_calls=$(wc -l </tmp/llm_log)
fi
printf 'resolved=%s\nllm_calls=%s\n' "${resolved}" "${llm_calls}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "llm_calls=0" ]
	[[ "${lines[0]}" == *'"title":"ready"'* ]]
}

@test "execute_planned_action forwards resolved args and preserves output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

log() {
        :
}

history_log=$(mktemp)

state_get() {
        if [[ "$2" == "user_query" ]]; then
                printf 'user question'
        elif [[ "$2" == "plan_outline" ]]; then
                printf 'plan outline'
        fi
}

state_get_history_lines() {
        printf 'recent observation'
}

resolve_action_args() {
        printf '%s\n' "$5" >"${history_log}"
        printf '{"alpha":1,"beta":2}'
}

format_action_context() {
        printf 'context:%s:%s:%s' "$1" "$2" "$3"
}

extract_tool_query() {
        printf 'query:%s:%s' "$1" "$2"
}

execute_tool_with_query() {
        printf '%s' "$4" > /tmp/resolved_args.json
        printf '{"output":"ok"}'
}

record_tool_execution() {
        printf 'recorded\n'
}

state_set() {
        :
}

validated_action='{"tool":"demo","args":{"beta":2,"alpha":1},"thought":"thinking"}'
execute_planned_action "prefix" 1 "${validated_action}"
cat /tmp/resolved_args.json
printf '\n'
cat "${history_log}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "recorded" ]
	[ "${lines[1]}" = '{"alpha":1,"beta":2}' ]
	[ "${lines[2]}" = 'recent observation' ]
}

@test "resolve_action_args ignores malformed context metadata" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

log() { :; }

fill_missing_args_with_llm() {
        echo "llm_invoked" >>/tmp/llm_metadata_log
        printf '{}'
}

apply_plan_arg_controls() {
        printf '{"title":"seed","__context_controlled":"title","__context_seeds":["bad"]}'
}

normalize_args_json() {
        printf '%s' "$1"
}

tool_args_schema() { printf '{}'; }

resolved=$(resolve_action_args "notes_create" '{}' '{"args_control":{}}' "User" "" "Outline" "Thought")

llm_calls=0
if [[ -f /tmp/llm_metadata_log ]]; then
        llm_calls=$(wc -l </tmp/llm_metadata_log)
fi

printf 'resolved=%s\nllm_calls=%s\n' "${resolved}" "${llm_calls}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "llm_calls=0" ]
	[[ "${lines[0]}" == *'"title":"seed"'* ]]
}
