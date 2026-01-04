#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "execute_tool_with_query runs handlers without confirmation prompts" {
	run env -i HOME="$HOME" PATH="$PATH" VERBOSITY=2 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/dispatch.sh
demo_handler() { echo "ok"; }
tool_handler() { printf 'demo_handler'; }
export -f demo_handler tool_handler
execute_tool_with_query "demo" "ignored" "context line" "{}"
SCRIPT

	[ "$status" -eq 0 ]

	last_index=$((${#lines[@]} - 1))
	[[ "${lines[$last_index]}" == *'"output":"ok"'* ]]

	for line in "${lines[@]}"; do
		if [[ "${line}" == *"Execute tool"* ]] || [[ "${line}" == *"Requesting tool confirmation"* ]]; then
			false
		fi
	done
}
