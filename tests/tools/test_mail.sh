#!/usr/bin/env bats
#
# Focused tests for Apple Mail tool helpers.
#
# Usage: bats tests/tools/test_mail.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "mail tools warn when run off macOS" {
	run bash -lc 'source ./src/tools/mail/index.sh; IS_MACOS=false; VERBOSITY=1; TOOL_QUERY=$'"'"'a'"'"'; tool_mail_list_inbox'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Apple Mail is only available on macOS"* ]]
}

@test "mail_draft forwards recipients subject and body to osascript" {
	run bash -lc '
    export MAIL_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
    export MAIL_STUB_LOG="$(mktemp)"
    export IS_MACOS=true
    export VERBOSITY=0
    TOOL_QUERY=$'"'"'a@example.com, b@example.com\nSubject line\nBody text'"'"'
    source ./src/tools/mail/index.sh
    tool_mail_draft
    cat "${MAIL_STUB_LOG}"
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"ARGS: - Subject\\ line Body\\ text a@example.com b@example.com"* ]]
	[[ "$output" == *"Body\\ text"* ]]
}

@test "mail_draft parses recipients without mapfile (Bash 3 compatible)" {
	run bash -lc '
    enable -n mapfile
    export MAIL_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
    export MAIL_STUB_LOG="$(mktemp)"
    export IS_MACOS=true
    export VERBOSITY=0
    TOOL_QUERY=$'"'"'a@example.com , b@example.com , , c@example.com\nSubject line\nBody text'"'"'
    source ./src/tools/mail/index.sh
    tool_mail_draft
    cat "${MAIL_STUB_LOG}"
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"ARGS: - Subject\\ line Body\\ text a@example.com b@example.com c@example.com"* ]]
	[[ "$output" == *"Body\\ text"* ]]
}

@test "mail_send requires a recipient" {
	run bash -lc '
    export MAIL_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
    export IS_MACOS=true
    export VERBOSITY=1
    TOOL_QUERY=$'"'"'\nSubject only'"'"'
    source ./src/tools/mail/index.sh
    tool_mail_send
  '
	[ "$status" -eq 1 ]
	[[ "$output" == *"Unable to parse mail envelope"* ]]
}

@test "mail_send parses recipients without mapfile (Bash 3 compatible)" {
	run bash -lc '
    enable -n mapfile
    export MAIL_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
    export MAIL_STUB_LOG="$(mktemp)"
    export IS_MACOS=true
    export VERBOSITY=0
    TOOL_QUERY=$'"'"'first@example.com,second@example.com\nSubject line\nBody text'"'"'
    source ./src/tools/mail/index.sh
    tool_mail_send
    cat "${MAIL_STUB_LOG}"
  '
	[ "$status" -eq 0 ]
	[[ "$output" == *"ARGS: - Subject\\ line Body\\ text first@example.com second@example.com"* ]]
	[[ "$output" == *"Body\\ text"* ]]
}

@test "mail_search requires a search term" {
	run bash -lc '
    export MAIL_OSASCRIPT_BIN="$(pwd)/tests/fixtures/osascript_stub.sh"
    export IS_MACOS=true
    export VERBOSITY=1
    TOOL_QUERY="   "
    source ./src/tools/mail/index.sh
    tool_mail_search
  '
	[ "$status" -eq 1 ]
	[[ "$output" == *"Search term is required"* ]]
}
