#!/usr/bin/env bats
#
# Tests for JSON-backed state helpers.
#
# Usage:
#   bats tests/lib/test_state.sh
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper behaviour.

setup() {
	cd "$(git rev-parse --show-toplevel)" || exit 1
}

@test "state helpers persist values and history" {
	source ./src/lib/core/state.sh
	prefix=state_case
	state_set "${prefix}" "foo" "bar"
	[[ "$(state_get "${prefix}" "foo")" == "bar" ]]
	state_increment "${prefix}" "counter" 2
	state_increment "${prefix}" "counter"
	[[ "$(state_get "${prefix}" "counter")" == "3" ]]
	state_append_history "${prefix}" "entry one"
	state_append_history "${prefix}" "entry two"
	history_json="$(state_get "${prefix}" "history")"
	jq -e '(. | length == 2) and (.[0] == "entry one") and (.[1] == "entry two")' <<<"${history_json}" >/dev/null
}

@test "json_state_get_document falls back on invalid JSON" {
	source ./src/lib/core/json_state.sh
	prefix=invalid_state_case
	json_var=$(json_state_namespace_var "${prefix}")
	printf -v "${json_var}" "%s" "{invalid"
	output=$(json_state_get_document "${prefix}" '{"default":true}')
	[ "${output}" = '{"default":true}' ]
}

@test "invalid documents are cached as sanitized fallbacks" {
	source ./src/lib/core/json_state.sh
	prefix=invalid_cached_state_case
	json_var=$(json_state_namespace_var "${prefix}")
	printf -v "${json_var}" "%s" "{invalid"
	first=""
	second=""
	json_state_get_document "${prefix}" '{"ok":true}' first >/dev/null
	json_state_get_document "${prefix}" '{}' second >/dev/null
	cache_path=$(json_state_cache_path "${prefix}")
	cache_contents=$(cat "${cache_path}")
	printf '%s|%s|%s|%s' "${first}" "${second}" "${!json_var}" "${cache_contents}" >output
	[ "$(cat output)" = '{"ok":true}|{"ok":true}|{"ok":true}|{"ok":true}' ]
}

@test "cache is used when namespace resets" {
	source ./src/lib/core/json_state.sh
	prefix=cache_reuse_case
	json_state_set_document "${prefix}" '{"cached":true}'
	json_state_get_document "${prefix}" >/dev/null
	unset "$(json_state_namespace_var "${prefix}")"
	output=$(json_state_get_document "${prefix}")
	[ "${output}" = '{"cached":true}' ]
}

@test "history append gracefully repairs malformed JSON" {
	source ./src/lib/core/state.sh
	prefix=broken_history
	json_var=$(state_namespace_json_var "${prefix}")
	printf -v "${json_var}" "%s" "{broken"
	state_append_history "${prefix}" "first"
	state_append_history "${prefix}" "second"
	history_json="$(state_get "${prefix}" "history")"
	jq -e '(. | length == 2) and (.[0] == "first") and (.[1] == "second")' <<<"${history_json}" >/dev/null
}
