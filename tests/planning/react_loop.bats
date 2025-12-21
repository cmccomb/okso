#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "react_loop finalizes after invalid action selection" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=false
source ./src/lib/planning/react.sh
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
source ./src/lib/planning/react.sh
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

@test "react_loop clears plan entries after tool failure" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=true
source ./src/lib/planning/react.sh
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
source ./src/lib/planning/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
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
