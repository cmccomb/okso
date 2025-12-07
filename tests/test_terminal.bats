#!/usr/bin/env bats
#
# Focused tests for the terminal tool's persistent terminal session.
#
# Usage: bats tests/test_terminal.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "status default exposes allowed commands" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY=""; tool_terminal'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == Session:* ]]
	[[ "${output}" == *"Allowed commands:"* ]]
}

@test "cd updates persistent working directory" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TERMINAL_WORKDIR="$(pwd)"; TOOL_QUERY="cd tests"; tool_terminal; TOOL_QUERY="pwd"; tool_terminal'
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == *"/tests" ]]
}

@test "unknown command falls back to status" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="launch rockets"; tool_terminal'
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Allowed commands:"* ]]
}

@test "mkdir and rmdir operate within working directory" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TERMINAL_WORKDIR="$(mktemp -d)"; TOOL_QUERY="mkdir sandbox"; tool_terminal; TOOL_QUERY="rmdir sandbox"; tool_terminal; ls "${TERMINAL_WORKDIR}"'
	[ "$status" -eq 0 ]
	[[ -z "${output}" ]]
}

@test "mkdir errors without target" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="mkdir"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"mkdir requires a target directory"* ]]
}

@test "mv and cp require source and destination" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="mv source-only"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"mv requires a source and destination"* ]]

	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="cp"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"cp requires a source and destination"* ]]
}

@test "mv and cp work within the persistent directory" {
	run bash -lc '
                set -e
                source ./src/tools/terminal.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                echo "demo" >"${TERMINAL_WORKDIR}/original.txt"
                TOOL_QUERY="cp original.txt copy.txt"; tool_terminal
                TOOL_QUERY="mv copy.txt moved.txt"; tool_terminal
                TOOL_QUERY="cat moved.txt"; tool_terminal
        '
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == "demo" ]]
}

@test "touch adds files and rejects missing targets" {
	run bash -lc '
                set -e
                source ./src/tools/terminal.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                TOOL_QUERY="touch created.txt"; tool_terminal
                [ -f "${TERMINAL_WORKDIR}/created.txt" ]
        '
	[ "$status" -eq 0 ]

	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="touch"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"touch requires at least one target"* ]]
}

@test "rm defaults to interactive prompts" {
	run bash -lc '
                source ./src/tools/terminal.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                echo "to delete" >"${TERMINAL_WORKDIR}/temp.txt"
                printf "y\n" | TOOL_QUERY="rm temp.txt" tool_terminal
                [ ! -f "${TERMINAL_WORKDIR}/temp.txt" ]
        '
	[ "$status" -eq 0 ]
}

@test "rm emits error when no target provided" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="rm"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"rm requires a target"* ]]
}

@test "stat and wc validate targets" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="stat"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"stat requires a target"* ]]

	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="wc"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"wc requires at least one target"* ]]
}

@test "stat and wc operate relative to working directory" {
	run bash -lc '
                set -e
                source ./src/tools/terminal.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                printf "line one\nline two\n" >"${TERMINAL_WORKDIR}/data.txt"
                TOOL_QUERY="stat data.txt"; tool_terminal
                TOOL_QUERY="wc -l data.txt"; tool_terminal
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *"2 data.txt"* ]]
}

@test "du defaults to human-readable summary" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TERMINAL_WORKDIR="$(mktemp -d)"; TOOL_QUERY="du"; tool_terminal'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"." ]]
}

@test "base64 supports encode and decode" {
	run bash -lc '
                set -e
                source ./src/tools/terminal.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                printf "encode me" >"${TERMINAL_WORKDIR}/payload.txt"
                TOOL_QUERY="base64 encode payload.txt"; tool_terminal >"${TERMINAL_WORKDIR}/encoded.txt"
                TOOL_QUERY="base64 decode encoded.txt"; tool_terminal
        '
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == "encode me" ]]
}

@test "base64 validates modes and arguments" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="base64"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"base64 requires a mode"* ]]

	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; TOOL_QUERY="base64 transform file"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"base64 mode must be encode or decode"* ]]
}

@test "open warns on non-macOS hosts" {
	run bash -lc 'source ./src/tools/terminal.sh; VERBOSITY=0; IS_MACOS=false; TOOL_QUERY="open README.md"; tool_terminal'
	[ "$status" -eq 0 ]
	[[ "${output}" == *"macOS-only"* ]]
}
