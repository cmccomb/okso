#!/usr/bin/env bats
#
# Focused unit tests for shared Bash modules.
#
# Usage: bats tests/test_modules.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "parse_model_spec falls back to default file" {
	run bash -lc 'source ./src/config.sh; parts=(); mapfile -t parts < <(parse_model_spec "example/repo" "fallback.gguf"); echo "${parts[0]}"; echo "${parts[1]}"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "example/repo" ]
	[ "${lines[1]}" = "fallback.gguf" ]
}

@test "init_environment forces llama off when testing passthrough set" {
	run bash -lc '
                export TESTING_PASSTHROUGH=true
                MODEL_SPEC="demo/repo:demo.gguf"
                DEFAULT_MODEL_FILE="demo.gguf"
                APPROVE_ALL=false
                FORCE_CONFIRM=false
                NOTES_DIR="$(mktemp -d)"
                source ./src/config.sh
                init_environment
                printf "%s" "${LLAMA_AVAILABLE}"
        '
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "false" ]
}

@test "init_environment keeps llama enabled when passthrough is unset" {
	run bash -lc '
                unset TESTING_PASSTHROUGH
                MODEL_SPEC="demo/repo:demo.gguf"
                DEFAULT_MODEL_FILE="demo.gguf"
                LLAMA_BIN="/bin/true"
                APPROVE_ALL=false
                FORCE_CONFIRM=false
                NOTES_DIR="$(mktemp -d)"
                source ./src/config.sh
                init_environment
                printf "%s" "${LLAMA_AVAILABLE}"
        '
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "true" ]
}

@test "init_tool_registry clears previous tools" {
	run bash -lc 'source ./src/tools.sh; TOOLS=(stub); TOOL_DESCRIPTION=( [stub]="desc"); init_tool_registry; echo "${#TOOLS[@]}"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 0 ]
}

@test "initialize_tools registers each module" {
	run bash -lc 'source ./src/tools.sh; init_tool_registry; initialize_tools; printf "%s\n" "${TOOLS[@]}"'
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 22 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "file_search" ]
	[ "${lines[2]}" = "clipboard_copy" ]
	[ "${lines[3]}" = "clipboard_paste" ]
	[ "${lines[4]}" = "notes_create" ]
	[ "${lines[5]}" = "notes_append" ]
	[ "${lines[6]}" = "notes_list" ]
	[ "${lines[7]}" = "notes_search" ]
	[ "${lines[8]}" = "notes_read" ]
	[ "${lines[9]}" = "reminders_create" ]
	[ "${lines[10]}" = "reminders_list" ]
	[ "${lines[11]}" = "reminders_complete" ]
	[ "${lines[12]}" = "calendar_create" ]
	[ "${lines[13]}" = "calendar_list" ]
	[ "${lines[14]}" = "calendar_search" ]
	[ "${lines[15]}" = "mail_draft" ]
	[ "${lines[16]}" = "mail_send" ]
	[ "${lines[17]}" = "mail_search" ]
	[ "${lines[18]}" = "mail_list_inbox" ]
	[ "${lines[19]}" = "mail_list_unread" ]
	[ "${lines[20]}" = "applescript" ]
	[ "${lines[21]}" = "final_answer" ]
}

@test "log emits JSON with escaped fields" {
	run bash -lc $'VERBOSITY=2; source ./src/logging.sh; log "INFO" $'"'"'quote\nline'"'"' "detail"'
	[ "$status" -eq 0 ]
	message=$(echo "${output}" | jq -r '.message')
	[ "${message}" = $'quote\nline' ]
}

@test "generate_plan_outline adds final answer step" {
	run bash -lc '
                source ./src/planner.sh
                initialize_tools
                VERBOSITY=0
                LLAMA_AVAILABLE=true
                LLAMA_BIN="./tests/fixtures/mock_llama_relevance.sh"
                MODEL_REPO="demo/repo"
                MODEL_FILE="demo.gguf"
                generate_plan_outline "list files"
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *"terminal"* ]]
	[[ "${output}" == *"final_answer"* ]]
}

@test "extract_tools_from_plan returns ordered list" {
	run bash -lc '
                source ./src/planner.sh
                initialize_tools
                plan_text=$'"'"'1. Use notes_create to capture details.\n2. Use terminal to list files.\n3. Use final_answer to wrap up.'"'"'
                extract_tools_from_plan "${plan_text}"
        '
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "notes_create" ]
	[ "${lines[1]}" = "terminal" ]
	[ "${lines[2]}" = "final_answer" ]
}

@test "emit_plan_json builds valid array" {
	run bash -lc $'source ./src/planner.sh; plan=$'"'"'terminal|echo "hi"|4\nnotes_create|add note|3'"'"'; emit_plan_json "${plan}"'
	[ "$status" -eq 0 ]
	[ "$(echo "${output}" | jq -r '.[0].tool')" = "terminal" ]
	[ "$(echo "${output}" | jq -r '.[0].query')" = 'echo "hi"' ]
	[ "$(echo "${output}" | jq -r '.[1].score')" = "3" ]
}

@test "confirm_tool uses gum when available" {
	run bash -lc '
tmpdir=$(mktemp -d)
export LOG_FILE="${tmpdir}/gum.log"
cat >"${tmpdir}/gum"<<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >>"${LOG_FILE}"
exit 0
EOF
chmod +x "${tmpdir}/gum"
PATH="${tmpdir}:$PATH"
FORCE_CONFIRM=true
APPROVE_ALL=false
DRY_RUN=false
PLAN_ONLY=false
source ./src/planner.sh
confirm_tool "terminal"
cat "${LOG_FILE}"
'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "confirm --affirmative Run --negative Skip Execute tool \"terminal\"?" ]
}

@test "confirm_tool surfaces skipped message when gum declines" {
	run bash -lc '
tmpdir=$(mktemp -d)
export LOG_FILE="${tmpdir}/gum.log"
cat >"${tmpdir}/gum"<<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >>"${LOG_FILE}"
exit 1
EOF
chmod +x "${tmpdir}/gum"
PATH="${tmpdir}:$PATH"
FORCE_CONFIRM=true
APPROVE_ALL=false
DRY_RUN=false
PLAN_ONLY=false
source ./src/planner.sh
confirm_tool "terminal"
status=$?
cat "${LOG_FILE}"
exit ${status}
'
	[ "$status" -eq 1 ]
	[ "${lines[1]}" = "[terminal skipped]" ]
	[ "${lines[2]}" = "confirm --affirmative Run --negative Skip Execute tool \"terminal\"?" ]
}

@test "execute_tool_with_query logs confirmation before prompt" {
	run bash -lc '
tmpdir=$(mktemp -d)
cat >"${tmpdir}/gum"<<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo "PROMPT:$*"
exit 0
EOF
chmod +x "${tmpdir}/gum"
PATH="${tmpdir}:$PATH"
source ./src/planner.sh
demo_handler() { echo "ran ${TOOL_QUERY}"; }
TOOL_HANDLER["demo_tool"]="demo_handler"
FORCE_CONFIRM=true
APPROVE_ALL=false
DRY_RUN=false
PLAN_ONLY=false
execute_tool_with_query "demo_tool" "echo hi"
'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"Requesting tool confirmation"* ]]
	[ "$(echo "${lines[0]}" | jq -r '.detail')" = "tool=demo_tool query=echo hi" ]
	[ "${lines[1]}" = "PROMPT:confirm --affirmative Run --negative Skip Execute tool \"demo_tool\"?" ]
	[ "${lines[2]}" = "ran echo hi" ]
}

@test "execute_tool_with_query skips confirmation logging in preview modes" {
	run bash -lc '
source ./src/planner.sh
demo_handler() { echo "ran ${TOOL_QUERY}"; }
TOOL_HANDLER["demo_tool"]="demo_handler"
FORCE_CONFIRM=true
APPROVE_ALL=false
DRY_RUN=false
PLAN_ONLY=true
execute_tool_with_query "demo_tool" "noop"
'
	[ "$status" -eq 0 ]
	[[ "${output}" != *"Requesting tool confirmation"* ]]
	[ "$(echo "${output}" | jq -r '.message')" = "Skipping execution in preview mode" ]
}

@test "show_help renders through gum when available" {
	run bash -lc '
tmpdir=$(mktemp -d)
export LOG_FILE="${tmpdir}/gum.log"
cat >"${tmpdir}/gum"<<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >>"${LOG_FILE}"
cat
EOF
chmod +x "${tmpdir}/gum"
PATH="${tmpdir}:$PATH"
source ./src/cli.sh
show_help
printf "LOG:%s\n" "$(cat "${LOG_FILE}")"
'
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[ "${lines[${last_index}]}" = "LOG:format" ]
}

@test "select_next_action follows plan entries before finalizing" {
	run bash -lc '
                source ./src/planner.sh
                respond_text() { printf "offline response"; }
                declare -A state=(
                        [user_query]="list files"
                        [allowed_tools]=$'"'"'terminal\nfinal_answer'"'"'
                        [plan_entries]=$'"'"'terminal|echo hi|4'"'"'
                        [plan_outline]=$'"'"'1. terminal -> echo hi\n2. final_answer -> respond'"'"'
                        [history]=""
                        [step]=0
                        [max_steps]=2
                        [final_answer]=""
                )
                USE_REACT_LLAMA=false
                LLAMA_AVAILABLE=false
                select_next_action state | jq -r ".type,.tool,.query"
        '
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "tool" ]
	[ "${lines[1]}" = "terminal" ]
	[ "${lines[2]}" = "echo hi" ]
}

@test "validate_tool_permission records history for disallowed tool" {
	run bash -lc '
                source ./src/planner.sh
                declare -A state=(
                        [allowed_tools]=$'"'"'terminal\nnotes_create'"'"'
                        [history]=""
                )
                validate_tool_permission state "mail_send"
                echo "$?"
                printf "%s" "${state[history]}"
        '
	[ "${lines[0]}" -eq 1 ]
	[ "${lines[1]}" = "Tool mail_send not permitted." ]
}

@test "finalize_react_result generates answer when none provided" {
	run bash -lc '
                source ./src/planner.sh
                respond_text() { printf "%s" "stubbed response"; }
                declare -A state=(
                        [user_query]="demo question"
                        [allowed_tools]="terminal"
                        [plan_entries]=""
                        [plan_outline]=$'"'"'1. terminal -> list'"'"'
                        [history]=$'"'"'Action terminal query=list\nObservation: ok'"'"'
                        [step]=2
                        [max_steps]=3
                        [final_answer]=""
                )
                finalize_react_result state
        '
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "stubbed response" ]
	[ "${lines[1]}" = "Plan outline:" ]
	[ "${lines[2]}" = "1. terminal -> list" ]
	[ "${lines[3]}" = "Execution summary:" ]
	[ "${lines[4]}" = "Action terminal query=list" ]
	[ "${lines[5]}" = "Observation: ok" ]
}

@test "react_loop returns final_answer tool output" {
	run bash -lc '
                source ./src/planner.sh
                execute_tool_action() { printf "%s" "${2}"; }
                react_loop "question" $'"'"'final_answer'"'"' "final_answer|done|5" $'"'"'1. final_answer -> done'"'"'
        '

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "done" ]
	[ "${lines[1]}" = "Plan outline:" ]
	[ "${lines[2]}" = "1. final_answer -> done" ]
	[ "${lines[3]}" = "Execution summary:" ]
	[ "${lines[4]}" = "Step 1 action final_answer query=done" ]
	[ "${lines[5]}" = "Observation: done" ]
}
