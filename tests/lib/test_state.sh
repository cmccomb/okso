#!/usr/bin/env bats
#
# Tests for JSON-backed state helpers.
#
# Usage:
#   bats tests/lib/test_state.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper behaviour.

setup() {
	cd "$(git rev-parse --show-toplevel)" || exit 1
}

@test "json_state helpers persist values and history" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	prefix=state_case
	json_state_set_key "${prefix}" "foo" "bar"
	[[ "$(json_state_get_key "${prefix}" "foo")" == "bar" ]]
	json_state_increment_key "${prefix}" "counter" 2
	json_state_increment_key "${prefix}" "counter"
	[[ "$(json_state_get_key "${prefix}" "counter")" == "3" ]]
	json_state_append_history "${prefix}" "entry one"
	json_state_append_history "${prefix}" "entry two"
	history_json="$(json_state_get_key "${prefix}" "history")"
	jq -e '(. | length == 2) and (.[0] == "entry one") and (.[1] == "entry two")' <<<"${history_json}" >/dev/null
}

@test "json_state_get_document falls back on invalid JSON" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	prefix=invalid_state_case
	json_var=$(json_state_namespace_var "${prefix}")
	printf -v "${json_var}" "%s" "{invalid"
	output=$(json_state_get_document "${prefix}" '{"default":true}')
	[ "${output}" = '{"default":true}' ]
}

@test "json_state_sanitize_json normalizes or falls back" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	output=$(json_state_sanitize_json '{"b":2,"a":1}' '{}')
	jq -e '.a == 1 and .b == 2' <<<"${output}" >/dev/null
	output=$(json_state_sanitize_json '{invalid' '{"ok":true}')
	[ "${output}" = '{"ok":true}' ]
	run json_state_sanitize_json '{invalid' ''
	[ "${status}" -ne 0 ]
	[ -z "${output}" ]
}

@test "json_state_resolve_document uses cache when fallback omitted" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	prefix=resolve_cache_case
	json_state_write_cache "${prefix}" '{"cached":true}'
	unset "$(json_state_namespace_var "${prefix}")"
	output=$(json_state_resolve_document "${prefix}" "")
	[ "${output}" = '{"cached":true}' ]
}

@test "json_state_resolve_document prefers valid namespace data" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	prefix=resolve_var_case
	json_var=$(json_state_namespace_var "${prefix}")
	printf -v "${json_var}" "%s" '{"b":2,"a":1}'
	output=$(json_state_resolve_document "${prefix}" '{"fallback":true}')
	jq -e '.a == 1 and .b == 2' <<<"${output}" >/dev/null
}

@test "invalid documents are cached as sanitized fallbacks" {
	# shellcheck disable=SC1091
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
	[ "${first}" = '{"ok":true}' ]
	[ "${second}" = '{"ok":true}' ]
	[ "${!json_var}" = '{"ok":true}' ]
	[ "${cache_contents}" = '{"ok":true}' ]
}

@test "repaired fallback is reused after namespace reset" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	prefix=invalid_cache_reuse_case
	json_var=$(json_state_namespace_var "${prefix}")
	printf -v "${json_var}" "%s" "{invalid"
	json_state_get_document "${prefix}" '{"ok":true}' >/dev/null
	unset "${json_var}"
	output=$(json_state_get_document "${prefix}")
	[ "${output}" = '{"ok":true}' ]
}

@test "cache is used when namespace resets" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	prefix=cache_reuse_case
	json_state_set_document "${prefix}" '{"cached":true}'
	json_state_get_document "${prefix}" >/dev/null
	unset "$(json_state_namespace_var "${prefix}")"
	output=$(json_state_get_document "${prefix}")
	[ "${output}" = '{"cached":true}' ]
}

@test "history append gracefully repairs malformed JSON" {
	# shellcheck disable=SC1091
	source ./src/lib/core/json_state.sh
	prefix=broken_history
	json_var=$(json_state_namespace_var "${prefix}")
	printf -v "${json_var}" "%s" "{broken"
	json_state_append_history "${prefix}" "first"
	json_state_append_history "${prefix}" "second"
	history_json="$(json_state_get_key "${prefix}" "history")"
	jq -e '(. | length == 2) and (.[0] == "first") and (.[1] == "second")' <<<"${history_json}" >/dev/null
}
