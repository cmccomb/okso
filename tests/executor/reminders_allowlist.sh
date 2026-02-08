#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for reminders_allowlist.sh.

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034 # TD-001: dynamic globals are intentionally consumed across sourced modules and tests.
	chpwd_functions=()
}

@test "collect_reminders_allowlist preserves commas in single reminder titles" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/loop.sh

history_entry=$(
	jq -nc \
		--arg title "Call Bob, review budget" \
		'{
                  step: 1,
                  thought: "List reminders",
                  action: {tool: "reminders_list", args: {}},
                  observation: $title
                }'
)

allowlist="$(collect_reminders_allowlist "${history_entry}")"
jq -e --arg title "Call Bob, review budget" 'index($title) != null' <<<"${allowlist}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "collect_reminders_allowlist splits newline-delimited reminders" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/loop.sh

history_entry=$(
	jq -nc \
		--arg output $'Buy milk\nWalk dog' \
		'{
                  step: 1,
                  thought: "List reminders",
                  action: {tool: "reminders_list", args: {}},
                  observation: $output
                }'
)

allowlist="$(collect_reminders_allowlist "${history_entry}")"
jq -e 'index("Buy milk") != null and index("Walk dog") != null' <<<"${allowlist}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
