#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "should_prompt_for_tool prompts when confirmation is forced" {
	run env -i HOME="$HOME" PATH="$PATH" APPROVE_ALL=true FORCE_CONFIRM=true bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/dispatch.sh
if should_prompt_for_tool; then
        echo "prompt"
else
        echo "skip"
fi
SCRIPT

	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[ "${lines[$last_index]}" = "prompt" ]
}

@test "should_prompt_for_tool skips when approvals are granted without force" {
	run env -i HOME="$HOME" PATH="$PATH" APPROVE_ALL=true FORCE_CONFIRM=false bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/dispatch.sh
if should_prompt_for_tool; then
        echo "prompt"
else
        echo "skip"
fi
SCRIPT

	[ "$status" -eq 0 ]
	last_index=$((${#lines[@]} - 1))
	[ "${lines[$last_index]}" = "skip" ]
}
