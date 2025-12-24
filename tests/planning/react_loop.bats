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
printf 'final=%s step=%s attempts=%s' \
        "$(state_get react_state final_answer)" \
        "$(state_get react_state step)" \
        "$(state_get react_state attempts)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "final=fallback_response step=0 attempts=2" ]
}

@test "react_loop advances plan index after successful planned step" {
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
plan_entry=$(jq -nc '{tool:"alpha",thought:"planned",args:{}}')
react_loop "what time is it" "alpha" "${plan_entry}" ""
printf 'plan_index=%s pending=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state pending_plan_step)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "plan_index=1 pending=" ]
}

@test "react_loop completes multi-step plans before emitting fallback" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback_response'; }
validate_tool_permission() { return 0; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
_select_action_from_llama() { return 1; }

plan_step_one=$(jq -nc '{tool:"alpha",thought:"step1",args:{}}')
plan_step_two=$(jq -nc '{tool:"final_answer",thought:"step2",args:{input:"done"}}')
plan_entries=$(printf '%s\n%s' "${plan_step_one}" "${plan_step_two}")

react_loop "question" "alpha" "${plan_entries}" ""

printf 'final=%s plan_index=%s attempts=%s' \
        "$(state_get react_state final_answer)" \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state attempts)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "final=done plan_index=2 attempts=2" ]
}

@test "react_loop keeps plan index when llama returns invalid JSON" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=true
USE_REACT_LLAMA=true
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback'; }
validate_tool_permission() { return 0; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
llama_infer() { printf 'not-json'; }
plan_entry=$(jq -nc '{tool:"alpha",thought:"planned",args:{}}')
react_loop "question" $'alpha\nbeta' "${plan_entry}" ""
printf 'plan_index=%s skip_reason=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state plan_skip_reason)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "plan_index=0 skip_reason=action_selection_failed" ]
}

@test "react_loop records plan skip reason without advancing index when execution is bypassed" {
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
validate_tool_permission() { return 1; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
plan_entry=$(jq -nc '{tool:"alpha",thought:"planned",args:{}}')
react_loop "question" "alpha" "${plan_entry}" ""
printf 'plan_index=%s pending=%s skip_reason=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state pending_plan_step)" \
        "$(state_get react_state plan_skip_reason)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "plan_index=0 pending=0 skip_reason=tool_not_permitted" ]
}

@test "react_loop keeps plan index when a planned tool fails" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=false
USE_REACT_LLAMA=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback_response'; }
validate_tool_permission() { return 0; }
execute_tool_action() { printf '{"output":"fail","exit_code":9}'; return 9; }
plan_entry=$(jq -nc '{tool:"alpha",thought:"planned",args:{}}')
react_loop "question" "alpha" "${plan_entry}" ""
printf 'plan_index=%s pending=%s skip_reason=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state pending_plan_step)" \
        "$(state_get react_state plan_skip_reason)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "plan_index=0 pending=0 skip_reason=" ]
}

@test "react_loop logs skip reasons without plan progress" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log_messages=()
log() {
        log_messages+=("$1:$2:${3:-}")
}
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback_response'; }
validate_tool_permission() { return 1; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
plan_entry=$(jq -nc '{tool:"alpha",thought:"planned",args:{}}')
react_loop "question" "alpha" "${plan_entry}" ""
printf 'plan_index=%s pending=%s skip_reason=%s logs=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state pending_plan_step)" \
        "$(state_get react_state plan_skip_reason)" \
        "$(printf '%s' "${log_messages[*]}")"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" == "plan_index=0 pending=0 skip_reason=tool_not_permitted logs="*"reason=tool_not_permitted"* ]]
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

@test "state_get_history_lines prefers summaries except for the latest raw observation" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
respond_text() { printf 'done'; }
validate_tool_permission() { return 0; }
execute_tool_action() { :; }

initialize_react_state react_state "question" "alpha" "" ""

record_tool_execution "react_state" "alpha" "first" '{}' '{"output":"long output","exit_code":0}' "summary first" 1
record_tool_execution "react_state" "alpha" "second" '{}' '{"output":"second raw","exit_code":0}' "summary second" 2

history_lines="$(state_get_history_lines react_state)"
first_line=$(printf '%s\n' "${history_lines}" | sed -n '1p')
second_line=$(printf '%s\n' "${history_lines}" | sed -n '2p')

first_obs=$(printf '%s' "${first_line}" | jq -r '.observation')
second_obs_output=$(printf '%s' "${second_line}" | jq -r '.observation.output')

printf 'first=%s second=%s' "${first_obs}" "${second_obs_output}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "first=summary first second=second raw" ]
}

@test "react_loop does not advance plan index when llama selects a different tool" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
MAX_STEPS=1
LLAMA_AVAILABLE=true
USE_REACT_LLAMA=true
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
validate_tool_permission() { return 0; }
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
llama_infer() { printf '{"thought":"llm","tool":"beta","args":{"input":"alt"}}'; }
plan_entry=$(jq -nc '{tool:"alpha",thought:"planned",args:{input:"orig"}}')
react_loop "question" $'alpha\nbeta' "${plan_entry}" ""
printf 'plan_index=%s skip_reason=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state plan_skip_reason)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "plan_index=0 skip_reason=plan_tool_mismatch" ]
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

@test "react_loop derives attempt budget from plan length" {
	run env -i HOME="$HOME" PATH="$PATH" REACT_RETRY_BUFFER=1 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback'; }
validate_tool_permission() { return 0; }
selection=0
select_next_action() {
        if [[ ${selection:-0} -eq 0 ]]; then
                selection=1
                return 1
        fi
        printf -v "$2" '{"thought":"finish","tool":"final_answer","args":{"input":"done"}}'
}
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
plan_entry=$(jq -nc '{tool:"alpha"}')
react_loop "question" "final_answer" "${plan_entry}" ""
printf 'max_steps=%s attempts=%s step=%s retry_count=%s final=%s' \
        "$(state_get react_state max_steps)" \
        "$(state_get react_state attempts)" \
        "$(state_get react_state step)" \
        "$(state_get react_state retry_count)" \
        "$(state_get react_state final_answer)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "max_steps=2 attempts=2 step=1 retry_count=1 final=done" ]
}

@test "react_loop retries planned step without consuming step counter" {
	run env -i HOME="$HOME" PATH="$PATH" REACT_RETRY_BUFFER=2 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
validate_tool_permission() { return 0; }
_select_action_from_llama() { return 1; }
execution_count=0
execute_tool_action() {
        execution_count=$((execution_count + 1))
        if [[ ${execution_count} -eq 1 ]]; then
                printf '{"output":"fail","exit_code":1}'
                return 1
        fi
        printf '{"output":"ok","exit_code":0}'
}
plan_entry=$(jq -nc '{tool:"alpha"}')
react_loop "question" "alpha" "${plan_entry}" ""
printf 'plan_index=%s step=%s attempts=%s retry_count=%s pending=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state step)" \
        "$(state_get react_state attempts)" \
        "$(state_get react_state retry_count)" \
        "$(state_get react_state pending_plan_step)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "plan_index=1 step=1 attempts=2 retry_count=1 pending=" ]
}

@test "react_loop derives attempt budget from plan length" {
	run env -i HOME="$HOME" PATH="$PATH" REACT_RETRY_BUFFER=1 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'fallback'; }
validate_tool_permission() { return 0; }
selection=0
select_next_action() {
        if [[ ${selection:-0} -eq 0 ]]; then
                selection=1
                return 1
        fi
        printf -v "$2" '{"thought":"finish","tool":"final_answer","args":{"input":"done"}}'
}
execute_tool_action() { printf '{"output":"ok","exit_code":0}'; }
plan_entry=$(jq -nc '{tool:"alpha"}')
react_loop "question" "final_answer" "${plan_entry}" ""
printf 'max_steps=%s attempts=%s step=%s retry_count=%s final=%s' \
        "$(state_get react_state max_steps)" \
        "$(state_get react_state attempts)" \
        "$(state_get react_state step)" \
        "$(state_get react_state retry_count)" \
        "$(state_get react_state final_answer)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "max_steps=2 attempts=2 step=1 retry_count=1 final=done" ]
}

@test "react_loop retries planned step without consuming step counter" {
	run env -i HOME="$HOME" PATH="$PATH" REACT_RETRY_BUFFER=2 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
LLAMA_AVAILABLE=false
source ./src/lib/react/react.sh
log() { :; }
log_pretty() { :; }
emit_boxed_summary() { :; }
format_tool_history() { printf '%s' "$1"; }
respond_text() { printf 'done'; }
validate_tool_permission() { return 0; }
selection=0
execution_count=0
select_next_action() {
        selection=$((selection + 1))
        if [[ ${selection} -eq 1 ]]; then
                printf -v "$2" '{"thought":"try","tool":"alpha","args":{}}'
        else
                printf -v "$2" '{"thought":"retry","tool":"alpha","args":{}}'
        fi
}
execute_tool_action() {
        execution_count=$((execution_count + 1))
        if [[ ${execution_count} -eq 1 ]]; then
                printf '{"output":"fail","exit_code":1}'
                return 1
        fi
        printf '{"output":"ok","exit_code":0}'
}
plan_entry=$(jq -nc '{tool:"alpha"}')
react_loop "question" "alpha" "${plan_entry}" ""
printf 'plan_index=%s step=%s attempts=%s retry_count=%s pending=%s' \
        "$(state_get react_state plan_index)" \
        "$(state_get react_state step)" \
        "$(state_get react_state attempts)" \
        "$(state_get react_state retry_count)" \
        "$(state_get react_state pending_plan_step)"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "plan_index=1 step=1 attempts=2 retry_count=1 pending=" ]
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
