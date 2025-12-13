#!/usr/bin/env bats
#
# Focused tests for the file_search tool and its platform fallbacks.
#
# Usage: bats tests/tools/test_file_search.sh
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "uses mdfind on macOS when available" {
        run bash -lc '
                set -e
                stub_dir="$(mktemp -d)"
                cat >"${stub_dir}/mdfind" <<"STUB"
#!/usr/bin/env bash
printf "mdfind:%s\n" "$*"
STUB
                chmod +x "${stub_dir}/mdfind"

                PATH="${stub_dir}:${PATH}"
                VERBOSITY=0
                IS_MACOS=true
                TOOL_QUERY="needle"
                source ./src/tools/file_search.sh
                tool_file_search
        '

        [ "$status" -eq 0 ]
        [[ "${lines[0]}" == mdfind:*"-onlyin"*"needle" ]]
}

@test "falls back to fd when Spotlight is unavailable" {
        run bash -lc '
                set -e
                stub_dir="$(mktemp -d)"
                cat >"${stub_dir}/fd" <<"STUB"
#!/usr/bin/env bash
printf "fd:%s\n" "$*"
STUB
                chmod +x "${stub_dir}/fd"

                PATH="${stub_dir}:${PATH}"
                VERBOSITY=0
                IS_MACOS=false
                TOOL_QUERY="query"
                source ./src/tools/file_search.sh
                tool_file_search
        '

        [ "$status" -eq 0 ]
        [[ "${lines[0]}" == fd:*"--max-depth"*"query"*"." ]]
}
