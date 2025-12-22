#!/usr/bin/env bats
#
# Focused tests for the terminal tool's persistent terminal session.
#
# Usage: bats tests/tools/test_terminal.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "status default exposes allowed commands" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{}"; tool_terminal'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == Session:* ]]
	[[ "${lines[1]}" == Working\ directory:* ]]
	[[ "${lines[2]}" == Allowed\ commands:* ]]
	[[ "${lines[2]}" != *"open"* ]]
}

@test "cd updates persistent working directory" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TERMINAL_WORKDIR="$(pwd)"; TOOL_ARGS="{\"command\":\"cd\",\"args\":[\"tests\"]}"; tool_terminal; TOOL_ARGS="{\"command\":\"pwd\",\"args\":[]}"; tool_terminal'
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == *"/tests" ]]
}

@test "rejects commands outside allowed enum" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"launch\",\"args\":[\"rockets\"]}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"terminal command not permitted"* ]]
}

@test "mkdir and rmdir operate within working directory" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TERMINAL_WORKDIR="$(mktemp -d)"; TOOL_ARGS="{\"command\":\"mkdir\",\"args\":[\"sandbox\"]}"; tool_terminal; TOOL_ARGS="{\"command\":\"rmdir\",\"args\":[\"sandbox\"]}"; tool_terminal; ls "${TERMINAL_WORKDIR}"'
	[ "$status" -eq 0 ]
	[[ -z "${output}" ]]
}

@test "mkdir errors without target" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"mkdir\"}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"mkdir requires a target directory"* ]]
}

@test "mv and cp require source and destination" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"mv\",\"args\":[\"source-only\"]}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"mv requires a source and destination"* ]]

	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"cp\"}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"cp requires a source and destination"* ]]
}

@test "mv and cp work within the persistent directory" {
	run bash -lc '
                set -e
                source ./src/tools/terminal/index.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                echo "demo" >"${TERMINAL_WORKDIR}/original.txt"
                TOOL_ARGS='"'"'{"command":"cp","args":["original.txt","copy.txt"]}'"'"'; tool_terminal
                TOOL_ARGS='"'"'{"command":"mv","args":["copy.txt","moved.txt"]}'"'"'; tool_terminal
                TOOL_ARGS='"'"'{"command":"cat","args":["moved.txt"]}'"'"'; tool_terminal
        '
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == "demo" ]]
}

@test "touch adds files and rejects missing targets" {
	run bash -lc '
                set -e
                source ./src/tools/terminal/index.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                TOOL_ARGS='"'"'{"command":"touch","args":["created.txt"]}'"'"'; tool_terminal
                [ -f "${TERMINAL_WORKDIR}/created.txt" ]
        '
	[ "$status" -eq 0 ]

	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"touch\"}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"touch requires at least one target"* ]]
}

@test "rm defaults to interactive prompts" {
	run bash -lc '
                source ./src/tools/terminal/index.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                echo "to delete" >"${TERMINAL_WORKDIR}/temp.txt"
                printf "y\n" | TOOL_ARGS='"'"'{"command":"rm","args":["temp.txt"]}'"'"' tool_terminal
                [ ! -f "${TERMINAL_WORKDIR}/temp.txt" ]
        '
	[ "$status" -eq 0 ]
}

@test "rm emits error when no target provided" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"rm\"}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"rm requires a target"* ]]
}

@test "stat and wc validate targets" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"stat\"}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"stat requires a target"* ]]

	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"wc\"}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"wc requires at least one target"* ]]
}

@test "stat and wc operate relative to working directory" {
	run bash -lc '
                set -e
                source ./src/tools/terminal/index.sh
                VERBOSITY=0
                TERMINAL_WORKDIR="$(mktemp -d)"
                printf "line one\nline two\n" >"${TERMINAL_WORKDIR}/data.txt"
                TOOL_ARGS='"'"'{"command":"stat","args":["data.txt"]}'"'"'; tool_terminal
                TOOL_ARGS='"'"'{"command":"wc","args":["-l","data.txt"]}'"'"'; tool_terminal
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *"2 data.txt"* ]]
}

@test "du defaults to human-readable summary" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TERMINAL_WORKDIR="$(mktemp -d)"; TOOL_ARGS="{\"command\":\"du\"}"; tool_terminal'
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"." ]]
}

@test "date runs within the working directory" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TERMINAL_WORKDIR="$(mktemp -d)"; TOOL_ARGS="{\"command\":\"date\"}"; tool_terminal'
	[ "$status" -eq 0 ]
	[[ "${output}" == *":"* ]]
}

@test "base64 supports encode and decode" {
	run bash -lc '
                set -e
                source ./src/tools/terminal/index.sh
                VERBOSITY=0
                TOOL_ARGS='"'"'{"command":"base64","args":["encode","encode me"]}'"'"'; encoded="$(tool_terminal | tail -n 1)";
                TOOL_ARGS="{\"command\":\"base64\",\"args\":[\"decode\",\"$encoded\"]}"; tool_terminal
        '
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == "encode me" ]]
}

@test "base64 validates modes and arguments" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"base64\"}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"base64 requires a mode"* ]]

	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"base64\",\"args\":[\"transform\",\"file\"]}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"base64 mode must be encode or decode"* ]]
}

@test "terminal args normalize scalar inputs" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"ls\",\"args\":\".\"}"; tool_terminal'
	[ "$status" -eq 0 ]

	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"date\",\"args\":\".\"}"; tool_terminal'
	[ "$status" -eq 0 ]
}

@test "terminal operates under nounset" {
	run bash -lc 'set -euo pipefail; source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"status\",\"args\":[]}"; tool_terminal'

	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == Session:* ]]
}

@test "malformed TOOL_ARGS surface JSON errors" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; TOOL_ARGS="{\"command\":\"ls\",\"args\":}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"terminal args must be valid JSON"* ]]
}

@test "open is rejected on non-macOS hosts" {
	run bash -lc 'source ./src/tools/terminal/index.sh; VERBOSITY=0; IS_MACOS=false; TOOL_ARGS="{\"command\":\"open\",\"args\":[\"README.md\"]}"; tool_terminal'
	[ "$status" -eq 1 ]
	[[ "${output}" == *"terminal command not permitted"* ]]
}
