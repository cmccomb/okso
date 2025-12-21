#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "planner fails fast when ReAct entrypoint is missing" {
	run env -i HOME="$HOME" PATH="$PATH" REACT_ENTRYPOINT="/tmp/missing-react.sh" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/planner.sh
SCRIPT

	[ "$status" -ne 0 ]
	[[ "$output" == *"ReAct entrypoint missing"* ]]
}

@test "react_loop finalizes after invalid action selection" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback_response'; }
validate_tool_permission() { return 0; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
record_tool_execution() { :; }
select_next_action() { return 1; }
react_loop "what time is it" "alpha" "" ""
printf 'final=%s step=%s' "$(state_get react_state final_answer)" "$(state_get react_state step)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "final=fallback_response step=1" ]
}

@test "react_loop records duplicate actions with warning observation" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=2
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
validate_tool_permission() { return 0; }
call_count=0
select_next_action() {
        call_count=$((call_count + 1))
        if [[ ${call_count} -eq 1 ]]; then
                printf -v "$2" '{"thought":"first","tool":"alpha","args":{}}'
        else
                printf -v "$2" '{"thought":"second","tool":"alpha","args":{}}'
        fi
}
react_loop "question" "alpha" "" ""
history_lines="$(state_get_history_lines react_state)"
first_entry=$(printf '%s\n' "${history_lines}" | sed -n '1p')
second_entry=$(printf '%s\n' "${history_lines}" | sed -n '2p')
printf 'first_thought=%s second_thought=%s' \
        "$(printf '%s' "${first_entry}" | jq -r '.thought')" \
        "$(printf '%s' "${second_entry}" | jq -r '.thought')"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "first_thought=first second_thought=second (REPEATED)" ]
}

@test "react_loop identifies duplicates with reordered args" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=2
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
validate_tool_permission() { return 0; }
call_count=0
select_next_action() {
        call_count=$((call_count + 1))
        if [[ ${call_count} -eq 1 ]]; then
                printf -v "$2" '{"thought":"first","tool":"alpha","args":{"b":1,"a":2}}'
        else
                printf -v "$2" '{"thought":"second","tool":"alpha","args":{"a":2,"b":1}}'
        fi
}
react_loop "question" "alpha" "" ""
history_lines="$(state_get_history_lines react_state)"
first_entry=$(printf '%s\n' "${history_lines}" | sed -n '1p')
second_entry=$(printf '%s\n' "${history_lines}" | sed -n '2p')
printf 'first_thought=%s second_thought=%s' \
        "$(printf '%s' "${first_entry}" | jq -r '.thought')" \
        "$(printf '%s' "${second_entry}" | jq -r '.thought')"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "first_thought=first second_thought=second (REPEATED)" ]
}

@test "react_loop allows retries after failed actions" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=2
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
validate_tool_permission() { return 0; }
selection_count=0
select_next_action() {
        selection_count=$((selection_count + 1))
        if [[ ${selection_count} -eq 1 ]]; then
                printf -v "$2" '{"thought":"initial","tool":"alpha","args":{"q":1}}'
        else
                printf -v "$2" '{"thought":"retry","tool":"alpha","args":{"q":1}}'
        fi
}
tool_calls=0
execute_tool_action() {
        tool_calls=$((tool_calls + 1))
        if [[ ${tool_calls} -eq 1 ]]; then
                printf '{"output":"failed","exit_code":1}'
        else
                printf '{"output":"ok","exit_code":0}'
        fi
}
react_loop "question" "alpha" "" ""
history_lines="$(state_get_history_lines react_state)"
first_entry=$(printf '%s\n' "${history_lines}" | sed -n '1p')
second_entry=$(printf '%s\n' "${history_lines}" | sed -n '2p')
printf 'first_thought=%s second_thought=%s' \
        "$(printf '%s' "${first_entry}" | jq -r '.thought')" \
        "$(printf '%s' "${second_entry}" | jq -r '.thought')"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "first_thought=initial second_thought=retry" ]
}

@test "react_loop records tool invocation failures" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log_messages=()
log() {
        if [[ "$1" == "ERROR" ]]; then
                log_messages+=("$1:$2:${3:-}")
        fi
}
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback'; }
validate_tool_permission() { return 0; }
execute_tool_with_query() { echo ""; return 9; }
select_next_action() { printf -v "$2" '{"thought":"fail","tool":"alpha","args":{}}'; }
react_loop "question" "alpha" "" ""
last_action_exit=$(state_get react_state last_action | jq -r '.exit_code')
last_error=$(state_get react_state last_tool_error)
log_count=${#log_messages[@]}
printf 'exit=%s error=%s logs=%s' "${last_action_exit}" "${last_error}" "${log_count}"
SCRIPT

	[ "$status" -eq 0 ]
	echo "$output"
	[[ "$output" == *"exit=9"* ]]
	[[ "$output" == *"error="* ]]
	[[ "$output" == *"logs="* ]]
}

@test "react_loop clears plan entries after tool failure" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=true
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
validate_tool_permission() { return 0; }
execute_tool_action() { printf '{"output":"fail","exit_code":1}'; }
record_tool_execution() { :; }
select_next_action() { printf -v "$2" '{"thought":"try","tool":"alpha","args":{}}'; }
react_loop "question" "alpha" '{"tool":"alpha"}' ""
history_len=$(state_get_history_lines react_state | wc -l | tr -d ' ')
plan_steps=$(jq length <<<"${PLAN_JSON:-[]}")
printf 'history_len=%s plan_steps=%s' "${history_len}" "${plan_steps}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "history_len=0 plan_steps=0" ]
}

@test "react_loop stops after final_answer" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=3
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { echo "fallback should not be used" 1>&2; exit 1; }
validate_tool_permission() { return 0; }
execute_tool_action() { printf '{"output":"complete","exit_code":0}'; }
record_tool_execution() { :; }
select_next_action() { printf -v "$2" '{"thought":"finish","tool":"final_answer","args":{}}'; }
react_loop "question" "final_answer" "" ""
printf 'final=%s step=%s' "$(state_get react_state final_answer)" "$(state_get react_state step)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "final=complete step=1" ]
}

@test "react_loop stores final_answer payload when execution bypassed" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { echo "fallback should not be used" 1>&2; exit 1; }
validate_tool_permission() { return 1; }
execute_tool_action() { echo "should not run" 1>&2; exit 1; }
record_tool_execution() { :; }
select_next_action() { printf -v "$2" '{"thought":"finish","tool":"final_answer","args":{"input":"done"}}'; }
react_loop "question" "final_answer" "" ""
printf 'final=%s stored=%s' "$(state_get react_state final_answer)" "$(state_get react_state final_answer_action)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "final=done stored=done" ]
}
