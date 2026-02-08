#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for search.sh.

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034 # TD-001: dynamic globals are intentionally consumed across sourced modules and tests.
	chpwd_functions=()
	# shellcheck disable=SC2155 # TD-003: test setup keeps declaration-plus-assignment for concise fixtures.
	export REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "planner_format_search_context renders empty search results" {
	run env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" REPO_ROOT="${REPO_ROOT}" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "${REPO_ROOT}"
source ./src/lib/planning/search.sh
raw_context='{"query":"what day is it in japan right now","items":[]}'
planner_format_search_context "${raw_context}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "$output" = "No search results were captured for this query." ]
}

@test "planner_format_search_context renders query and formatted items" {
	run env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" REPO_ROOT="${REPO_ROOT}" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "${REPO_ROOT}"
source ./src/lib/planning/search.sh
raw_context='{"query":"example query","items":[{"title":"Title","url":"https://example.com","snippet":"Snippet"}]}'
planner_format_search_context "${raw_context}"
SCRIPT

	[ "$status" -eq 0 ]
	expected_output=$'Query: example query\n1. Title: Snippet [https://example.com]'
	[ "$output" = "${expected_output}" ]
}
