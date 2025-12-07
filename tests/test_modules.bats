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

@test "json_escape preserves newlines and quotes" {
	run bash -lc "source ./src/logging.sh; json_escape $'quote\nline'"
	[ "$status" -eq 0 ]
	[ "${output}" = "quote\\nline" ]
}
