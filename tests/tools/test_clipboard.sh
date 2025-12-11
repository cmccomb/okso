#!/usr/bin/env bats
#
# Focused tests for clipboard copy/paste helpers.
#
# Usage: bats tests/tools/test_clipboard.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

setup() {
	export VERBOSITY=0
}

@test "clipboard_copy uses pbcopy on macOS" {
	run bash -lc '
                tmp_dir=$(mktemp -d)
                cat >"${tmp_dir}/pbcopy" <<"SCRIPT"
#!/usr/bin/env bash
cat >"${CLIPBOARD_MOCK}"
SCRIPT
                chmod +x "${tmp_dir}/pbcopy"
                export CLIPBOARD_MOCK="${tmp_dir}/clipboard"
                export PATH="${tmp_dir}:${PATH}"
                source ./src/tools/clipboard.sh
                IS_MACOS=true
                TOOL_QUERY="hello world"
                tool_clipboard_copy
                cat "${CLIPBOARD_MOCK}"
        '
	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[ "${lines[$last_index]}" = "hello world" ]
}

@test "clipboard_paste uses pbpaste on macOS" {
	run bash -lc '
                tmp_dir=$(mktemp -d)
                cat >"${tmp_dir}/pbpaste" <<"SCRIPT"
#!/usr/bin/env bash
cat "${CLIPBOARD_MOCK}"
SCRIPT
                chmod +x "${tmp_dir}/pbpaste"
                printf "clipboard contents" >"${tmp_dir}/clipboard"
                export CLIPBOARD_MOCK="${tmp_dir}/clipboard"
                export PATH="${tmp_dir}:${PATH}"
                source ./src/tools/clipboard.sh
                IS_MACOS=true
                TOOL_QUERY="ignored"
                tool_clipboard_paste
        '
	[ "$status" -eq 0 ]
	[ "${output}" = "clipboard contents" ]
}

@test "clipboard tools warn and no-op on non-macOS" {
	run bash -lc '
                source ./src/tools/clipboard.sh
                VERBOSITY=1
                IS_MACOS=false
                TOOL_QUERY="data"
                tool_clipboard_copy
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Clipboard operations require macOS"* ]]
}

@test "clipboard tools emit errors when pbcopy/pbpaste are missing" {
	run bash -lc '
                source ./src/tools/clipboard.sh
                IS_MACOS=true
                TOOL_QUERY="data"
                tool_clipboard_copy
        '
	[ "$status" -eq 1 ]
	[[ "${output}" == *"pbcopy missing"* ]]

	run bash -lc '
                source ./src/tools/clipboard.sh
                IS_MACOS=true
                TOOL_QUERY="data"
                tool_clipboard_paste
        '
	[ "$status" -eq 1 ]
	[[ "${output}" == *"pbpaste missing"* ]]
}
