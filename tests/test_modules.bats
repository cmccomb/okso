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

@test "init_tool_registry clears previous tools" {
	run bash -lc 'source ./src/tools.sh; TOOLS=(stub); TOOL_DESCRIPTION=( [stub]="desc"); init_tool_registry; echo "${#TOOLS[@]}"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" -eq 0 ]
}

@test "initialize_tools registers each module" {
	run bash -lc 'source ./src/tools.sh; init_tool_registry; initialize_tools; printf "%s\n" "${TOOLS[@]}"'
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 21 ]
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
}

@test "log emits JSON with escaped fields" {
run bash -lc $'VERBOSITY=2; source ./src/logging.sh; log "INFO" $'"'"'quote\nline'"'"' "detail"'
[ "$status" -eq 0 ]
message=$(echo "${output}" | jq -r '.message')
[ "${message}" = $'quote\nline' ]
}

@test "parse_llama_ranking reads JSON responses" {
run bash -lc 'source ./src/planner.sh; initialize_tools; raw='"'"'[{"tool":"terminal","score":4,"reason":"ok"},{"tool":"file_search","score":5}]'"'"'; parse_llama_ranking "${raw}"'
[ "$status" -eq 0 ]
[ "${lines[0]}" = "5:file_search" ]
[ "${lines[1]}" = "4:terminal" ]
}

@test "structured_tool_relevance parses boolean map grammar" {
        run bash -lc '
                source ./src/planner.sh
                initialize_tools
                LLAMA_AVAILABLE=true
                LLAMA_BIN="./tests/fixtures/mock_llama_relevance.sh"
                MODEL_REPO="demo/repo"
                MODEL_FILE="demo.gguf"
                structured_tool_relevance "list files"
        '
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "5:terminal" ]
}

@test "emit_plan_json builds valid array" {
run bash -lc $'source ./src/planner.sh; plan=$'"'"'terminal|echo "hi"|4\nnotes_create|add note|3'"'"'; emit_plan_json "${plan}"'
[ "$status" -eq 0 ]
[ "$(echo "${output}" | jq -r '.[0].tool')" = "terminal" ]
[ "$(echo "${output}" | jq -r '.[0].query')" = 'echo "hi"' ]
[ "$(echo "${output}" | jq -r '.[1].score')" = "3" ]
}
