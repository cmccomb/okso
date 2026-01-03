#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "select_response_strategy uses user query from settings" {
	run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail

source ./src/lib/runtime.sh

apply_settings_to_globals() {
        USER_QUERY=""
}

json_state_get_key() {
        local prefix key
        prefix="$1"
        key="$2"
        if [[ "${prefix}" == "settings_ns" && "${key}" == "user_query" ]]; then
                printf 'state-query'
        fi
}

executor_loop() {
        printf 'user:%s\n' "$1"
        printf 'tools:%s\n' "$2"
        printf 'entries:%s\n' "$3"
        printf 'outline:%s\n' "$4"
}

select_response_strategy "settings_ns" "tool-a" "[{\"step\":1}]" "outline text" "{}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "user:state-query" ]
	[ "${lines[1]}" = "tools:tool-a" ]
	[ "${lines[2]}" = "entries:[{\"step\":1}]" ]
	[ "${lines[3]}" = "outline:outline text" ]
}
