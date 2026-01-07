#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "collect_web_fetch_allowlist extracts urls from web_search tool output metadata" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/loop.sh

history_entry=$(
	jq -nc \
		--arg url "https://www.steelers.com/schedule/" \
		'{
                  step: 1,
                  thought: "Use web_search to find schedule",
                  action: {tool: "web_search", args: {query: "steelers schedule"}},
                  observation: {output: ({"items":[{"url": $url}]} | tojson), error: "", exit_code: 0}
                }'
)

allowlist="$(collect_web_fetch_allowlist "${history_entry}" "" "" "")"
jq -e 'index("https://www.steelers.com/schedule/") != null' <<<"${allowlist}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
