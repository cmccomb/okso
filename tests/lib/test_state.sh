#!/usr/bin/env bats
#
# Tests for JSON-backed state helpers.
#
# Usage:
#   bats tests/lib/test_state.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper behaviour.

@test "state helpers persist values and history" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/state.sh
                prefix=state_case
                state_set "${prefix}" "foo" "bar"
                [[ "$(state_get "${prefix}" "foo")" == "bar" ]]
                state_increment "${prefix}" "counter" 2
                state_increment "${prefix}" "counter"
                [[ "$(state_get "${prefix}" "counter")" == "3" ]]
                state_append_history "${prefix}" "entry one"
                state_append_history "${prefix}" "entry two"
                [[ "$(state_get "${prefix}" "history")" == $'"'"'entry one\nentry two'"'"' ]]
        '
	[ "$status" -eq 0 ]
}

@test "json_state_get_document falls back on invalid JSON" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/json_state.sh
                prefix=invalid_state_case
                json_var=$(json_state_namespace_var "${prefix}")
                printf -v "${json_var}" "%s" "{invalid"
                json_state_get_document "${prefix}" "{\"default\":true}" result >/dev/null
                printf "%s" "${result}"
        '
	[ "$status" -eq 0 ]
	[ "$output" = '{"default":true}' ]
}

@test "invalid documents are cached as sanitized fallbacks" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/json_state.sh
                prefix=invalid_cached_state_case
                json_var=$(json_state_namespace_var "${prefix}")
                printf -v "${json_var}" "%s" "{invalid"
                json_state_get_document "${prefix}" "{\"ok\":true}" first >/dev/null
                json_state_get_document "${prefix}" '{}' second >/dev/null
                printf "%s|%s|%s" "${first}" "${second}" "${!json_var}"
        '
	[ "$status" -eq 0 ]
	[ "$output" = '{"ok":true}|{"ok":true}|{"ok":true}' ]
}

@test "invalid fallback is sanitized and persisted" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/json_state.sh
                prefix=invalid_fallback_case
                cache_path=$(json_state_cache_path "${prefix}")
                json_state_write_cache "${prefix}" '{"cached":true}'
                json_var=$(json_state_namespace_var "${prefix}")
                printf -v "${json_var}" "%s" "{invalid"
                fallback="{\"not\":true"
                json_state_get_document "${prefix}" "${fallback}" result >/dev/null
                printf "%s|%s|%s" "${result}" "${!json_var}" "$(cat "${cache_path}")"
        '
	[ "$status" -eq 0 ]
	[ "$output" = '{}|{}|{}' ]
}

@test "fallback overrides existing cache when parsing fails" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/json_state.sh
                prefix=fallback_overrides_cache_case
                cache_path=$(json_state_cache_path "${prefix}")
                json_state_write_cache "${prefix}" '{"cached":true}'
                json_var=$(json_state_namespace_var "${prefix}")
                printf -v "${json_var}" "%s" "{invalid"
                fallback="{\"fallback\":true}"
                json_state_get_document "${prefix}" "${fallback}" result >/dev/null
                printf "%s|%s|%s" "${result}" "${!json_var}" "$(cat "${cache_path}")"
        '
	[ "$status" -eq 0 ]
	[ "$output" = '{"fallback":true}|{"fallback":true}|{"fallback":true}' ]
}

@test "json_state_get_document sets output variable on fallback" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                source ./src/lib/json_state.sh
                prefix=output_var_fallback_case
                json_var=$(json_state_namespace_var "${prefix}")
                printf -v "${json_var}" "%s" "{invalid"
                json_state_get_document "${prefix}" "{\"fallback\":true}" resolved >/dev/null
                printf "%s|%s" "${resolved}" "${!json_var}"
        '
	[ "$status" -eq 0 ]
	[ "$output" = '{"fallback":true}|{"fallback":true}' ]
}
