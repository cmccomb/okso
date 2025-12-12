#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared JSON-backed state helpers used by okso runtime and state modules.
#
# Usage:
#   source "${BASH_SOURCE[0]%/json_state.sh}/json_state.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 5+
#   - jq
#
# Exit codes:
#   Functions return non-zero on misuse or jq failures; callers should handle failures.

json_state_namespace_var() {
        # Arguments:
        #   $1 - namespace prefix (string)
        printf '%s_json' "$1"
}

json_state_get_document() {
        # Arguments:
        #   $1 - namespace prefix (string)
        #   $2 - fallback JSON document (string, optional; defaults to '{}')
        local prefix fallback json_var
        prefix="$1"
        fallback="${2:-{}}"
        json_var=$(json_state_namespace_var "${prefix}")
        if [[ -z "${!json_var+x}" ]]; then
                printf '%s' "${fallback}"
        else
                printf '%s' "${!json_var}"
        fi
}

json_state_set_document() {
        # Arguments:
        #   $1 - namespace prefix (string)
        #   $2 - JSON document (string)
        local prefix document json_var sanitized
        prefix="$1"
        document="$2"
        json_var=$(json_state_namespace_var "${prefix}")
        sanitized=$(printf '%s' "${document}" | jq -c '.') || return 1
        printf -v "${json_var}" '%s' "${sanitized}"
}

json_state_set_key() {
        # Arguments:
        #   $1 - namespace prefix (string)
        #   $2 - key (string)
        #   $3 - value (string)
        local prefix key value updated
        prefix="$1"
        key="$2"
        value="$3"
        updated=$(jq -c --arg key "${key}" --arg value "${value}" '.[$key] = $value' <<<"$(json_state_get_document "${prefix}")")
        json_state_set_document "${prefix}" "${updated}"
}

json_state_get_key() {
        # Arguments:
        #   $1 - namespace prefix (string)
        #   $2 - key (string)
        local prefix key
        prefix="$1"
        key="$2"
        jq -r --arg key "${key}" '.[$key] // ""' <<<"$(json_state_get_document "${prefix}")"
}

json_state_increment_key() {
        # Arguments:
        #   $1 - namespace prefix (string)
        #   $2 - key (string)
        #   $3 - increment amount (int, optional; defaults to 1)
        local prefix key increment updated
        prefix="$1"
        key="$2"
        increment="${3:-1}"
        updated=$(jq -c --arg key "${key}" --argjson inc "${increment}" '.[$key] = ((try (.[$key]|tonumber) catch 0) + $inc)' <<<"$(json_state_get_document "${prefix}")")
        json_state_set_document "${prefix}" "${updated}"
}

json_state_append_history() {
        # Arguments:
        #   $1 - namespace prefix (string)
        #   $2 - history entry (string)
        local prefix entry updated
        prefix="$1"
        entry="$2"
        updated=$(jq -c --arg entry "${entry}" '(.history //= []) | .history += [$entry]' <<<"$(json_state_get_document "${prefix}")")
        json_state_set_document "${prefix}" "${updated}"
}
