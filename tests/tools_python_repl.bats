#!/usr/bin/env bats
#
# Tests for the Python REPL tool sandbox behavior.
#
# Usage:
#   bats tests/tools_python_repl.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#   - python 3+
#
# Exit codes:
#   Inherits Bats semantics; assertions verify interpreter behavior.

@test "executes code inside sandbox directory" {
        run bash -lc '
                set -e
                source ./src/tools/python_repl.sh
                VERBOSITY=0
                TOOL_QUERY=$'"'"'import os; print(os.getcwd())'"'"'
                tool_python_repl
        '
        [ "$status" -eq 0 ]
        sandbox_path=$(printf '%s\n' "${output}" | grep "Python REPL sandbox:" | head -n1 | awk '{print $4}')
        [[ -n "${sandbox_path}" ]]
        printf '%s\n' "${output}" | grep -F "${sandbox_path}" >/dev/null
}

@test "returns non-zero on Python errors" {
        run bash -lc '
                source ./src/tools/python_repl.sh
                VERBOSITY=0
                TOOL_QUERY=$'"'"'raise RuntimeError("boom")'"'"'
                tool_python_repl
        '
        [ "$status" -eq 1 ]
        [[ "${output}" == *"RuntimeError: boom"* ]]
}

@test "blocks writes outside the sandbox" {
        run bash -lc '
                source ./src/tools/python_repl.sh
                VERBOSITY=0
                rm -f /tmp/python_repl_forbidden.txt
                TOOL_QUERY=$'"'"'open("/tmp/python_repl_forbidden.txt", "w").write("nope")'"'"'
                tool_python_repl
                exit_status=$?
                test ! -e /tmp/python_repl_forbidden.txt || exit 3
                exit "${exit_status}"
        '
        [ "$status" -eq 1 ]
        [[ "${output}" == *"File writes restricted to sandbox"* ]]
}
