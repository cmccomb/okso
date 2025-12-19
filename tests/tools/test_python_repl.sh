#!/usr/bin/env bats
#
# Tests for the Python REPL tool sandbox behavior.
#
# Usage:
#   bats tests/tools/test_python_repl.sh
#
# Dependencies:
#   - bats
#   - bash 5+
#   - python 3+
#
# Exit codes:
#   Inherits Bats semantics; assertions verify interpreter behavior.

@test "executes code inside sandbox directory" {
	script=$(
		cat <<'SCRIPT'
set -e
cd "$(git rev-parse --show-toplevel)"
source ./src/tools/python_repl.sh
VERBOSITY=0
TOOL_ARGS=$(jq -nc --arg code 'import os; print(os.getcwd())' '{input:$code}')
tool_python_repl
SCRIPT
	)
	run bash -lc "${script}"
	[ "$status" -eq 0 ]
	sandbox_path=$(printf '%s\n' "${output}" | grep "Python REPL sandbox:" | head -n1 | awk '{print $4}')
	[[ -n "${sandbox_path}" ]]
	printf '%s\n' "${output}" | grep -F "${sandbox_path}" >/dev/null
}

@test "starts quietly without Python banner" {
	script=$(
		cat <<'SCRIPT'
cd "$(git rev-parse --show-toplevel)"
source ./src/tools/python_repl.sh
VERBOSITY=0
TOOL_ARGS=$(jq -nc --arg code 'print("ok")' '{input:$code}')
tool_python_repl
SCRIPT
	)
	run bash -lc "${script}"
	[ "$status" -eq 0 ]
	[[ "${output}" != *"Type \"help\""* ]]
	[[ ! "${output}" =~ ^Python\ [0-9] ]]
}

@test "returns non-zero on Python errors" {
	script=$(
		cat <<'SCRIPT'
cd "$(git rev-parse --show-toplevel)"
source ./src/tools/python_repl.sh
VERBOSITY=0
TOOL_ARGS=$(jq -nc --arg code 'raise RuntimeError("boom")' '{input:$code}')
tool_python_repl
SCRIPT
	)
	run bash -lc "${script}"
	[ "$status" -eq 1 ]
	[[ "${output}" == *"RuntimeError: boom"* ]]
}

@test "blocks writes outside the sandbox" {
	script=$(
		cat <<'SCRIPT'
cd "$(git rev-parse --show-toplevel)"
source ./src/tools/python_repl.sh
VERBOSITY=0
rm -f /tmp/python_repl_forbidden.txt
TOOL_ARGS=$(jq -nc --arg code 'open("/tmp/python_repl_forbidden.txt", "w").write("nope")' '{input:$code}')
tool_python_repl
exit_status=$?
test ! -e /tmp/python_repl_forbidden.txt || exit 3
exit ${exit_status}
SCRIPT
	)
	run bash -lc "${script}"
	[ "$status" -eq 1 ]
	[[ "${output}" == *"File writes restricted to sandbox"* ]]
}
