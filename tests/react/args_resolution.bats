#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "resolve_action_args normalizes once while filling missing values" {
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
        printf '%s' "$2"
}

fill_missing_args_with_llm() {
        printf '{"title":"filled","body":"done"}'
}

missing_arg_keys() {
        if [[ "$1" == *"__MISSING__"* ]]; then
                printf 'title\n'
        fi
}

resolved=$(resolve_action_args "notes_create" '{"title":"__MISSING__","body":"__MISSING__"}' '{"args_control":{}}' "User" "Outline" "Thought")
normalize_calls=$(wc -l <"${normalize_log}")
printf 'resolved=%s\nnormalizations=%s\n' "${resolved}" "${normalize_calls}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *'"title":"filled"'* ]]
	[[ "${lines[0]}" == *'"body":"done"'* ]]
	[ "${lines[1]}" = "normalizations=1" ]
}

@test "resolve_action_args skips missing scans when args complete" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

log() {
        :
}

missing_scan_log=$(mktemp)
missing_arg_keys() {
        printf 'scan\n' >>"${missing_scan_log}"
}

apply_plan_arg_controls() {
        printf '{"title":"ready"}'
}

normalize_args_json() {
        printf '%s' "$1"
}

resolved=$(resolve_action_args "notes_create" '{"title":"ready"}' '{"args_control":{}}' "User" "Outline" "Thought")
missing_scans=$(wc -l <"${missing_scan_log}")
printf 'resolved=%s\nmissing_scans=%s\n' "${resolved}" "${missing_scans}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "missing_scans=0" ]
	[[ "${lines[0]}" == *'"title":"ready"'* ]]
}

@test "execute_planned_action forwards resolved args and preserves output" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

log() {
        :
}

state_get() {
        if [[ "$2" == "user_query" ]]; then
                printf 'user question'
        elif [[ "$2" == "plan_outline" ]]; then
                printf 'plan outline'
        fi
}

resolve_action_args() {
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
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "recorded" ]
	[ "${lines[1]}" = '{"alpha":1,"beta":2}' ]
}
