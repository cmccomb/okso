#!/usr/bin/env bats
#
# Focused unit tests for shared Bash modules.
#
# Usage: bats tests/core/test_modules.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

bats_require_minimum_version 1.5.0
load ../helpers/log_parsing.sh

setup() {
	export HOME="${BATS_TMPDIR}/okso-modules"
	mkdir -p "${HOME}/.cargo"
	: >"${HOME}/.cargo/env"
	export VERBOSITY=0
}

@test "parse_model_spec falls back to default file" {
	run bash -lc 'source ./src/lib/config.sh; parts=(); mapfile -t parts < <(parse_model_spec "example/repo" "fallback.gguf"); echo "${parts[0]}"; echo "${parts[1]}"'
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
                source ./src/lib/config.sh
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
                source ./src/lib/config.sh
                init_environment
                printf "%s" "${LLAMA_AVAILABLE}"
        '
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "true" ]
}

@test "llama_infer reports unavailability without invoking llama" {
	run bash -lc '
                tmpdir=$(mktemp -d)
                export LLAMA_AVAILABLE=false
                export LLAMA_BIN="${tmpdir}/llama"
                cat >"${LLAMA_BIN}"<<'"'"'EOF'"'"'
#!/usr/bin/env bash
echo "invoked" >>"${TMP_LOG}" 2>/dev/null
EOF
                chmod +x "${LLAMA_BIN}"
                TMP_LOG="${tmpdir}/log"
                source ./src/lib/planner.sh
                log() { :; }
                llama_infer "demo prompt" "" 4
                infer_status=$?
                printf "STATUS:%s\n" "${infer_status}"
                printf "LOG:%s\n" "$(cat "${TMP_LOG}" 2>/dev/null || true)"
        '

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "STATUS:1" ]
	[ "${lines[1]}" = "LOG:" ]
}

@test "init_tool_registry clears previous tools" {
	run bash -lc 'source ./src/tools/registry.sh; register_tool alpha "desc" "cmd" "safe" handler; init_tool_registry; echo "$(tool_names)"; echo "$(tool_description alpha)"'
	[ "$status" -eq 0 ]
	[ -z "${lines[0]}" ]
	[ -z "${lines[1]}" ]
}

@test "assert_osascript_available warns and exits when not on macOS" {
	run bash -lc '
                IS_MACOS=false
                VERBOSITY=1
                TOOL_QUERY="demo query"
                source ./src/tools/osascript_helpers.sh
                assert_osascript_available \
                        "AppleScript not available on this platform" \
                        "missing" \
                        "osascript" \
                        "${TOOL_QUERY}"
        '

	[ "$status" -eq 1 ]
	logs_json="$(printf '%s' "${output}" | parse_json_logs)"
	[ "$(printf '%s' "${logs_json}" | jq -r 'try (.[0].message) catch ""')" = "AppleScript not available on this platform" ]
	[ "$(printf '%s' "${logs_json}" | jq -r 'try (.[0].detail) catch ""')" = "demo query" ]
}

@test "assert_osascript_available flags missing binary on macOS" {
	run bash -lc '
                IS_MACOS=true
                VERBOSITY=1
                source ./src/tools/osascript_helpers.sh
                assert_osascript_available \
                        "AppleScript not available on this platform" \
                        "osascript missing; cannot execute AppleScript" \
                        "/nonexistent/osascript" \
                        ""
        '

	[ "$status" -eq 1 ]
	logs_json="$(printf '%s' "${output}" | parse_json_logs)"
	[ "$(printf '%s' "${logs_json}" | jq -r 'try (.[0].message) catch ""')" = "osascript missing; cannot execute AppleScript" ]
}

@test "initialize_tools registers each module" {
	run bash -lc 'source ./src/lib/tools.sh; init_tool_registry; initialize_tools; mapfile -t names < <(tool_names); printf "%s\n" "${names[@]}"'
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 22 ]
	[[ "${lines[*]}" == *"terminal"* ]]
	[[ "${lines[*]}" == *"final_answer"* ]]
}

@test "log emits JSON with escaped fields" {
	run bash -lc $'VERBOSITY=2; source ./src/lib/logging.sh; log "INFO" $'"'"'quote\nline'"'"' "detail"'
	[ "$status" -eq 0 ]
	logs_json="$(printf '%s' "${output}" | parse_json_logs)"
	message=$(printf '%s' "${logs_json}" | jq -r 'try (.[0].message) catch ""')
	[ "${message}" = $'quote\nline' ]
}

@test "generate_plan_outline adds final answer step" {
        run bash -lc '
                source ./src/lib/planner.sh
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

@test "generate_plan_outline tolerates missing TOOLS under set -u" {
        run bash -lc '
                set -u
                source ./src/lib/planner.sh
                init_tool_registry
                initialize_tools
                VERBOSITY=0
                LLAMA_AVAILABLE=true
                LLAMA_BIN="./tests/fixtures/mock_llama_relevance.sh"
                MODEL_REPO="demo/repo"
                MODEL_FILE="demo.gguf"
                plan="$(generate_plan_outline "list files")"
                printf "%s" "${plan}"
        '
        [ "$status" -eq 0 ]
        [[ "${output}" == *"terminal"* ]]
        [[ "${output}" == *"final_answer"* ]]
}

@test "generate_plan_outline bypasses llama when unavailable" {
        # shellcheck disable=SC2016
        run --separate-stderr bash -lc '
tmpdir=$(mktemp -d)
export MOCK_LLAMA_LOG="${tmpdir}/llama.log"
export LLAMA_BIN="./tests/fixtures/mock_llama.sh"
source ./src/lib/planner.sh
initialize_tools
LLAMA_AVAILABLE=false
plan="$(generate_plan_outline "offline request")"
if [[ -f "${MOCK_LLAMA_LOG}" ]]; then
echo "unexpected llama invocation"
exit 1
fi
printf "%s" "${plan}"
'
	[ "$status" -eq 0 ]
	[ "${output}" = "1. Use final_answer to respond directly to the user request." ]
	# shellcheck disable=SC2154
	[[ "${stderr}" == *"Using static plan outline"* ]]
}

@test "extract_tools_from_plan returns ordered list" {
	run bash -lc '
                source ./src/lib/planner.sh
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
	run bash -lc $'source ./src/lib/planner.sh; plan=$'"'"'terminal|echo "hi"|4\nnotes_create|add note|3'"'"'; emit_plan_json "${plan}"'
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
source ./src/lib/planner.sh
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
source ./src/lib/planner.sh
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
VERBOSITY=1
source ./src/lib/planner.sh
demo_handler() { echo "ran ${TOOL_QUERY}"; }
init_tool_registry
register_tool terminal "demo" "echo" "safe" demo_handler
FORCE_CONFIRM=true
APPROVE_ALL=false
DRY_RUN=false
PLAN_ONLY=false
execute_tool_with_query "terminal" "echo hi"
'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"Requesting tool confirmation"* ]]
	[ "$(echo "${lines[0]}" | jq -r '.detail')" = "tool=terminal query=echo hi" ]
	[ "${lines[1]}" = "PROMPT:confirm --affirmative Run --negative Skip Execute tool \"terminal\"?" ]
	[ "${lines[2]}" = "ran echo hi" ]
}

@test "execute_tool_with_query skips confirmation logging in preview modes" {
	run bash -lc '
VERBOSITY=1
source ./src/lib/planner.sh
demo_handler() { echo "ran ${TOOL_QUERY}"; }
init_tool_registry
register_tool terminal "demo" "echo" "safe" demo_handler
FORCE_CONFIRM=true
APPROVE_ALL=false
DRY_RUN=false
PLAN_ONLY=true
execute_tool_with_query "terminal" "noop"
'
	[ "$status" -eq 0 ]
	[[ "${output}" != *"Requesting tool confirmation"* ]]
	logs_json="$(printf '%s' "${output}" | parse_json_logs)"
	[ "$(printf '%s' "${logs_json}" | jq -r 'try (.[0].message) catch ""')" = "Skipping execution in preview mode" ]
}

@test "execute_tool_with_query captures stdout observation without stderr noise" {
	run bash -lc '
tmpdir=$(mktemp -d)
err_log="${tmpdir}/stderr.log"
VERBOSITY=1
source ./src/lib/planner.sh
demo_handler() { echo "stdout payload"; echo "stderr noise" >&2; }
init_tool_registry
register_tool terminal "demo" "echo" "safe" demo_handler
FORCE_CONFIRM=false
APPROVE_ALL=true
DRY_RUN=false
PLAN_ONLY=false
observation="$(execute_tool_with_query "terminal" "demo" 2>"${err_log}")"
printf "OBS:%s\n" "${observation}"
printf "ERR:%s\n" "$(cat "${err_log}")"
'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "OBS:stdout payload" ]
	[[ "${lines[1]}" == ERR:*"stderr noise"* ]]
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
source ./src/lib/cli.sh
show_help
printf "LOG:%s\n" "$(cat "${LOG_FILE}")"
'
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[ "${lines[${last_index}]}" = "LOG:format" ]
}

@test "select_next_action follows plan entries before finalizing" {
	run bash -lc '
                source ./src/lib/planner.sh
                respond_text() { printf "offline response"; }
                state_prefix=state
                initialize_react_state "${state_prefix}" "list files" $'"'"'terminal\nfinal_answer'"'"' $'"'"'terminal|echo hi|4'"'"' $'"'"'1. terminal -> echo hi\n2. final_answer -> respond'"'"'
                state_set "${state_prefix}" "max_steps" 2
                USE_REACT_LLAMA=false
                LLAMA_AVAILABLE=false
                select_next_action "${state_prefix}" | jq -r ".type,.tool,.query"
        '
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "tool" ]
	[ "${lines[1]}" = "terminal" ]
	[ "${lines[2]}" = "echo hi" ]
}

@test "select_next_action uses llama grammar and captures output" {
	run bash -lc '
                source ./src/lib/planner.sh

                llama_arg_file="$(mktemp)"
                llama_grammar_file="$(mktemp)"
                llama_infer() {
                        printf "%s" "$#" >"${llama_arg_file}"
                        printf "%s" "$4" >"${llama_grammar_file}"
                        printf "{\"type\":\"tool\",\"tool\":\"terminal\",\"query\":\"ls\"}"
                }

                state_prefix=state
                initialize_react_state "${state_prefix}" "list files" $'"'"'terminal\nfinal_answer'"'"' "" $'"'"'1. terminal -> list\n2. final_answer -> summarize'"'"'
                state_set "${state_prefix}" "max_steps" 2

                USE_REACT_LLAMA=true
                LLAMA_AVAILABLE=true
                action_json=""

                select_next_action "${state_prefix}" action_json

                llama_arg_count="$(cat "${llama_arg_file}")"
                llama_grammar="$(cat "${llama_grammar_file}")"
                expected_grammar="$(cd src && pwd)/grammars/react_action.schema.json"
                printf "%s\n" "${action_json}" "COUNT:${llama_arg_count}" "GRAMMAR:${llama_grammar}" "EXPECTED:${expected_grammar}"
        '

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = '{"type":"tool","tool":"terminal","query":"ls"}' ]
	[ "${lines[1]}" = "COUNT:4" ]
	[ "${lines[2]}" = "GRAMMAR:${lines[3]#EXPECTED:}" ]
}

@test "generate_plan_outline uses shared planner grammar" {
	source ./src/lib/planner.sh
	initialize_tools
	LLAMA_AVAILABLE=true

	llama_grammar_file="$(mktemp)"
	llama_infer() {
		printf "%s" "$4" >"${llama_grammar_file}"
		printf '["Inspect repo", "Use terminal"]'
	}

	plan_text="$(generate_plan_outline "list files")"

	expected_grammar="$(cd src && pwd)/grammars/planner_plan.schema.json"
	[ "$(cat "${llama_grammar_file}")" = "${expected_grammar}" ]
	[[ "${plan_text}" == *"1. Inspect repo"* ]]
	[[ "${plan_text}" == *"2. Use terminal"* ]]
	[[ "${plan_text}" == *"3. Use final_answer to summarize the result for the user."* ]]
}

@test "generate_plan_outline short-circuits when llama unavailable" {
	run bash -lc '
                tmpdir=$(mktemp -d)
                source ./src/lib/planner.sh
                llama_infer() { printf "called" >"${tmpdir}/llama.called"; }
                log() { :; }
                initialize_tools
                LLAMA_AVAILABLE=false

                plan_text="$(generate_plan_outline "offline request")"
                call_log="$(cat "${tmpdir}/llama.called" 2>/dev/null || true)"
                printf "PLAN:%s\nCALLED:%s\n" "${plan_text}" "${call_log}"
        '

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "PLAN:1. Use final_answer to respond directly to the user request." ]
	[ "${lines[1]}" = "CALLED:" ]
}

@test "respond_text forwards concise response grammar" {
	run bash -lc '
                source ./src/lib/respond.sh
                LLAMA_AVAILABLE=true
                LLAMA_BIN=""

                llama_grammar_file="$(mktemp)"
                llama_infer() {
                        printf "%s" "$4" >"${llama_grammar_file}"
                }

                response_output="$(respond_text "hello" 12)"
                printf "RESPONSE:%s\nGRAMMAR:%s\n" "${response_output}" "$(cat "${llama_grammar_file}")"
        '

	[ "$status" -eq 0 ]
	expected_grammar="$(cd src && pwd)/grammars/concise_response.schema.json"
	last_index=$((${#lines[@]} - 1))
	[ "${lines[${last_index}]}" = "GRAMMAR:${expected_grammar}" ]
}

@test "respond_text falls back when llama is unavailable" {
	run bash -lc '
                tmpdir=$(mktemp -d)
                export TESTING_PASSTHROUGH=true
                export LLAMA_BIN="${tmpdir}/llama"
                printf "#!/usr/bin/env bash\necho llama >>\"${tmpdir}/llama.log\"" >"${LLAMA_BIN}"
                chmod +x "${LLAMA_BIN}"
                MODEL_SPEC="demo/repo:demo.gguf"
                DEFAULT_MODEL_FILE="demo.gguf"
                NOTES_DIR="${tmpdir}/notes"
                APPROVE_ALL=false
                FORCE_CONFIRM=false
                source ./src/lib/config.sh
                init_environment
                source ./src/lib/respond.sh
                log() { :; }
                response_output="$(respond_text "offline question" 8)"
                printf "OUTPUT:%s\nLOG:%s\nAVAILABLE:%s\n" "${response_output}" "$(cat "${tmpdir}/llama.log" 2>/dev/null || true)" "${LLAMA_AVAILABLE}"
        '

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "OUTPUT:LLM unavailable. Request received: offline question" ]
	[ "${lines[1]}" = "LOG:" ]
	[ "${lines[2]}" = "AVAILABLE:false" ]
}

@test "select_next_action logs and fails on invalid llama output" {
	run bash -lc '
                source ./src/lib/planner.sh

                llama_infer() {
                        printf "invalid json"
                }

                state_prefix=state
                initialize_react_state "${state_prefix}" "list files" $'"'"'terminal\nfinal_answer'"'"' "" $'"'"'1. terminal -> list'"'"'
                state_set "${state_prefix}" "max_steps" 2

                USE_REACT_LLAMA=true
                LLAMA_AVAILABLE=true
                action_json=""

                select_next_action "${state_prefix}" action_json
                rc=$?
                echo "STATUS:${rc}"
                exit ${rc}
        '

	[ "$status" -eq 1 ]
	[[ "${output}" == *"Invalid action output from llama"* ]]
	last_index=$((${#lines[@]} - 1))
	[ "${lines[${last_index}]}" = "STATUS:1" ]
}

@test "validate_tool_permission records history for disallowed tool" {
	run bash -lc '
                source ./src/lib/planner.sh
                state_prefix=state
                state_set "${state_prefix}" "allowed_tools" $'"'"'terminal\nnotes_create'"'"'
                validate_tool_permission "${state_prefix}" "mail_send"
                echo "$?"
                printf "%s" "$(state_get "${state_prefix}" "history")"
        '
	[ "${lines[0]}" -eq 1 ]
	[ "${lines[1]}" = "Tool mail_send not permitted." ]
}

@test "state json helpers preserve ordering and counters" {
	run bash -lc '
                source ./src/lib/planner.sh
                state_prefix=state
                initialize_react_state "${state_prefix}" "question" "terminal" "" "1. terminal"
                state_append_history "${state_prefix}" "first"
                state_append_history "${state_prefix}" "second"
                state_increment "${state_prefix}" "plan_index" 2
                printf "%s\n%s\n" "$(state_get "${state_prefix}" "history")" "$(state_get "${state_prefix}" "plan_index")"
        '

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "first" ]
	[ "${lines[1]}" = "second" ]
	[ "${lines[2]}" = "2" ]
}

@test "finalize_react_result generates answer when none provided" {
	run bash -lc '
VERBOSITY=1
source ./src/lib/planner.sh
respond_text() { printf "%s" "stubbed response"; }
state_prefix=state
initialize_react_state "${state_prefix}" "demo question" "terminal" "" $'"'"'1. terminal -> list'"'"'
state_set "${state_prefix}" "history" $'"'"'Action terminal query=list\nObservation: ok'"'"'
state_set "${state_prefix}" "step" 2
state_set "${state_prefix}" "max_steps" 3
finalize_react_result "${state_prefix}"
'
	[ "$status" -eq 0 ]
	logs_json="$(printf '%s' "$output" | parse_json_logs)"
	final_answer="$(jq -r 'try (map(select(.message=="Final answer")) | .[0].detail) catch ""' <<<"${logs_json}")"
	execution="$(jq -r 'try (map(select(.message=="Execution summary")) | .[0].detail) catch ""' <<<"${logs_json}")"
	plan_outline_logs="$(jq -r 'map(select(.message=="Plan outline")) | length' <<<"${logs_json}")"

	[ "${final_answer}" = "stubbed response" ]
	[[ "${execution}" == *"Action terminal query=list"* ]]
	[[ "${execution}" == *"Observation: ok"* ]]
	[ "${plan_outline_logs}" -eq 0 ]
}

@test "react_loop returns final_answer tool output" {
	run bash -lc '
VERBOSITY=1
source ./src/lib/planner.sh
execute_tool_action() { printf "%s" "${2}"; }
react_loop "question" $'"'"'final_answer'"'"' "final_answer|done|5" $'"'"'1. final_answer -> done'"'"'
'

	[ "$status" -eq 0 ]
	logs_json="$(printf '%s' "$output" | parse_json_logs)"
	final_answer="$(jq -r 'try (map(select(.message=="Final answer")) | .[0].detail) catch ""' <<<"${logs_json}")"
	execution="$(jq -r 'try (map(select(.message=="Execution summary")) | .[0].detail) catch ""' <<<"${logs_json}")"
	plan_outline_logs="$(jq -r 'map(select(.message=="Plan outline")) | length' <<<"${logs_json}")"

	[ "${final_answer}" = "done" ]
	[[ "${execution}" == *"Step 1 action final_answer query=done"* ]]
	[[ "${execution}" == *"Observation: done"* ]]
	[ "${plan_outline_logs}" -eq 0 ]
}

@test "direct response logging follows execution order" {
	run bash -lc '
VERBOSITY=1
source ./src/lib/planner.sh
source ./src/lib/runtime.sh

respond_text() { printf "%s" "direct reply"; }

settings_prefix=settings
settings_clear_namespace "${settings_prefix}"
settings_set "${settings_prefix}" "plan_only" "false"
settings_set "${settings_prefix}" "dry_run" "false"
settings_set "${settings_prefix}" "user_query" "demo request"

required_tools=""
plan_entries=""
plan_outline=$'"'"'1. final_answer -> reply'"'"'

render_plan_outputs action "${settings_prefix}" "${required_tools}" "${plan_entries}" "${plan_outline}"
select_response_strategy "${settings_prefix}" "${required_tools}" "${plan_entries}" "${plan_outline}"
'

	[ "$status" -eq 0 ]
	logs_json="$(printf '%s' "$output" | parse_json_logs)"
	messages="$(printf '%s' "${logs_json}" | jq -r '.[].message')"
	readarray -t message_lines <<<"${messages}"
	expected=(
		"Suggested tools"
		"Plan outline"
		"No tools selected; responding directly"
		"Planner emitted no tools; using direct response"
		"Final answer"
		"Execution summary"
	)
	[ "${#message_lines[@]}" -eq "${#expected[@]}" ]
	for idx in "${!expected[@]}"; do
		[ "${message_lines[${idx}]}" = "${expected[${idx}]}" ]
	done
}

@test "react logging orders plan, actions, and summary" {
	run bash -lc '
VERBOSITY=1
USE_REACT_LLAMA=false
LLAMA_AVAILABLE=false
source ./src/lib/planner.sh
source ./src/lib/runtime.sh

execute_tool_action() { printf "%s observation" "${2}"; }

settings_prefix=settings
settings_clear_namespace "${settings_prefix}"
settings_set "${settings_prefix}" "plan_only" "false"
settings_set "${settings_prefix}" "dry_run" "false"
settings_set "${settings_prefix}" "user_query" "demo"

required_tools=$'"'"'final_answer'"'"'
plan_entries=$'"'"'final_answer|answer|1'"'"'
plan_outline=$'"'"'1. final_answer -> answer'"'"'

render_plan_outputs action "${settings_prefix}" "${required_tools}" "${plan_entries}" "${plan_outline}"
react_loop "demo" "${required_tools}" "${plan_entries}" "${plan_outline}"
'

	[ "$status" -eq 0 ]
	logs_json="$(printf '%s' "$output" | parse_json_logs)"
	messages="$(printf '%s' "${logs_json}" | jq -r '.[].message')"
	readarray -t message_lines <<<"${messages}"
	expected=(
		"Suggested tools"
		"Plan outline"
		"Recorded tool execution"
		"Final answer"
		"Execution summary"
	)
	[ "${#message_lines[@]}" -eq "${#expected[@]}" ]
	for idx in "${!expected[@]}"; do
		[ "${message_lines[${idx}]}" = "${expected[${idx}]}" ]
	done
}
