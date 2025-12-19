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

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./logging.sh disable=SC1091
source "${LIB_DIR}/logging.sh"

json_state_namespace_var() {
	# Arguments:
	#   $1 - namespace prefix (string)
	printf '%s_json' "$1"
}

json_state_cache_path() {
	# Arguments:
	#   $1 - namespace prefix (string)
	local prefix cache_dir
	prefix="$1"
	cache_dir="${TMPDIR:-/tmp}/okso_json_state"
	mkdir -p "${cache_dir}" 2>/dev/null || true
	printf '%s/%s.json' "${cache_dir}" "${prefix}"
}

json_state_write_cache() {
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - JSON document (string)
	local cache_path
	cache_path=$(json_state_cache_path "$1")
	printf '%s' "$2" >"${cache_path}" 2>/dev/null || true
}

json_state_get_document() {
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - fallback JSON document (string, optional; defaults to '{}')
	# Behavior:
	#   Returns the fallback when the namespaced variable is unset or contains
	#   invalid JSON, preventing downstream jq errors.
	local prefix fallback json_var document_value sanitized_fallback cache_path cache_document fallback_provided sanitized_document resolved_document output_var
	prefix="$1"
	output_var="${3:-}"
	if [[ $# -ge 2 && -n "${2}" ]]; then
		fallback_provided=true
		fallback="$2"
	else
		fallback_provided=false
		fallback="{}"
	fi

	sanitized_fallback=$(printf '%s' "${fallback}" | jq -c '.' 2>/dev/null || printf '{}')
	cache_path=$(json_state_cache_path "${prefix}")
	cache_document=""
	if [[ -f "${cache_path}" ]]; then
		cache_document=$(jq -c '.' <"${cache_path}" 2>/dev/null || printf '')
	fi
	if [[ "${fallback_provided}" != true && -n "${cache_document}" ]]; then
		sanitized_fallback="${cache_document}"
	fi
	json_var=$(json_state_namespace_var "${prefix}")
	if [[ -z "${!json_var+x}" ]]; then
		resolved_document="${sanitized_fallback}"
		printf -v "${json_var}" '%s' "${resolved_document}"
		json_state_write_cache "${prefix}" "${resolved_document}"
	else
		document_value="${!json_var}"
		if sanitized_document=$(printf '%s' "${document_value}" | jq -c '.' 2>/dev/null); then
			resolved_document="${sanitized_document}"
			printf -v "${json_var}" '%s' "${resolved_document}"
			json_state_write_cache "${prefix}" "${resolved_document}"
		else
			resolved_document="${sanitized_fallback}"
			printf -v "${json_var}" '%s' "${resolved_document}"
			json_state_write_cache "${prefix}" "${resolved_document}"
		fi
	fi

	if [[ -n "${output_var}" ]]; then
		printf -v "${output_var}" '%s' "${resolved_document}"
	fi

	printf '%s' "${resolved_document}"
}

json_state_set_document() {
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - JSON document (string)
	local prefix document json_var sanitized
	prefix="$1"
	document="$2"
	json_var=$(json_state_namespace_var "${prefix}")

        if ! sanitized=$(printf '%s' "${document}" | jq -c '.' 2>/dev/null); then
                log "ERROR" "json_state_set_document: invalid JSON" "namespace=${prefix}" || true
                return 1
        fi

	printf -v "${json_var}" '%s' "${sanitized}"
	json_state_write_cache "${prefix}" "${sanitized}"
}

json_state_set_key() {
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - key (string)
	#   $3 - value (string)
	local prefix key value base_json updated
	prefix="$1"
	key="$2"
	value="$3"

	json_state_get_document "${prefix}" '{}' base_json >/dev/null
        if ! updated=$(jq -c --arg key "${key}" --arg value "${value}" '.[$key] = $value' <<<"${base_json}" 2>/dev/null); then
                log "ERROR" "json_state_set_key: failed to set value" "namespace=${prefix} key=${key}" || true
                return 1
        fi

	json_state_set_document "${prefix}" "${updated}"
}

json_state_get_key() {
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - key (string)
	local prefix key document
	prefix="$1"
	key="$2"
	json_state_get_document "${prefix}" '{}' document >/dev/null
	jq -r --arg key "${key}" '.[$key] // ""' <<<"${document}"
}

json_state_increment_key() {
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - key (string)
	#   $3 - increment amount (int, optional; defaults to 1)
	local prefix key increment base_json updated
	prefix="$1"
	key="$2"
	increment="${3:-1}"
	json_state_get_document "${prefix}" '{}' base_json >/dev/null
        if ! updated=$(jq -c --arg key "${key}" --argjson inc "${increment}" '.[$key] = ((try (.[$key]|tonumber) catch 0) + $inc)' <<<"${base_json}" 2>/dev/null); then
                log "ERROR" "json_state_increment_key: failed to increment" "namespace=${prefix} key=${key}" || true
                return 1
        fi
	json_state_set_document "${prefix}" "${updated}"
}

json_state_append_history() {
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - history entry (string)
	local prefix entry base_json updated
	prefix="$1"
	entry="$2"
	json_state_get_document "${prefix}" '{}' base_json >/dev/null
        if ! updated=$(jq -c --arg entry "${entry}" '(.history //= []) | .history += [$entry]' <<<"${base_json}" 2>/dev/null); then
                log "ERROR" "json_state_append_history: failed to append history" "namespace=${prefix}" || true
                return 1
        fi
	json_state_set_document "${prefix}" "${updated}"
}
