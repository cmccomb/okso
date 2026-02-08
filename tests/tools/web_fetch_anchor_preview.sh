#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for web_fetch_anchor_preview.sh.

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034 # TD-001: dynamic globals are intentionally consumed across sourced modules and tests.
	chpwd_functions=()
}

@test "web_fetch_anchor_preview finds token window when snippet includes dates and ellipses" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/tools/web/web_fetch.sh

body_markdown="$(cat ./tests/fixtures/web_fetch_body.md)"
snippet="Sep 24, 2025 … Pittsburgh is a city in Pennsylvania …"
snippet_limit=200

result="$(web_fetch_anchor_preview "${body_markdown}" "" "${snippet}" "${snippet_limit}")"
matched="$(jq -r '.matched' <<<"${result}")"
preview="$(jq -r '.snippet' <<<"${result}")"

[[ "${matched}" == "true" ]]
[[ "${preview}" == *"Pittsburgh is a city in Pennsylvania"* ]]
SCRIPT

	[ "$status" -eq 0 ]
}
