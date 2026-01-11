#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "summarize_executor_history preserves web_fetch fields from enriched observation output" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/history.sh

payload="$(cat ./tests/fixtures/web_fetch_enriched_observation.json)"

history_entry=$(
	jq -nc \
		--arg output "${payload}" \
		'{
                  step: 1,
                  thought: "Fetch docs",
                  action: {tool: "web_fetch", args: {url: "https://example.com/docs"}},
                  observation: {output: $output, error: "", exit_code: 0}
                }'
)

summarized="$(summarize_executor_history "${history_entry}")"

jq -e '.observation.url != null and (.observation.body_markdown != null or .observation.body_snippet != null)' <<<"${summarized}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
