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
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on misuse or jq failures; callers should handle failures.

CORE_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${CORE_LIB_DIR}/logging.sh"

json_state_namespace_var() {
	# Generates the shell variable name for a given namespace.
	# Arguments:
	#   $1 - namespace prefix (string)
	# Returns:
	#   The variable name (string).
	printf '%s_json' "$1"
}

json_state_cache_path() {
	# Returns the absolute path to the persistent JSON cache file for a namespace.
	# Arguments:
	#   $1 - namespace prefix (string)
	# Returns:
	#   The file path (string).
	local prefix
	prefix="$1"

	if [[ -z "${JSON_STATE_CACHE_DIR:-}" ]]; then
		JSON_STATE_CACHE_DIR="${TMPDIR:-/tmp}/okso_json_state"
	fi

	if [[ "${JSON_STATE_CACHE_DIR_READY:-false}" != true ]]; then
		mkdir -p "${JSON_STATE_CACHE_DIR}" 2>/dev/null || true
		JSON_STATE_CACHE_DIR_READY=true
	fi

	printf '%s/%s.json' "${JSON_STATE_CACHE_DIR}" "${prefix}"
}

json_state_write_cache() {
	# Writes the JSON document to the persistent cache file for a namespace.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - JSON document (string)
	local cache_path
	cache_path=$(json_state_cache_path "$1")
	printf '%s' "$2" >"${cache_path}" 2>/dev/null || true
}

json_state_read_cache() {
	# Loads the cached JSON document for a namespace.
	# Arguments:
	#   $1 - namespace prefix (string)
	# Returns:
	#   Cached JSON (string) or empty string.
	local prefix cache_path cached_document
	prefix="$1"
	cache_path=$(json_state_cache_path "${prefix}")
	cached_document=""
	if [[ -f "${cache_path}" ]]; then
		cached_document=$(jq -c '.' <"${cache_path}" 2>/dev/null || printf '')
	fi
	printf '%s' "${cached_document}"
}

json_state_sanitize_json() {
	# Validates and normalizes JSON, returning a default when invalid.
	# Arguments:
	#   $1 - JSON document (string)
	#   $2 - default JSON document (string, optional)
	# Returns:
	#   Normalized JSON (string). Returns empty string when invalid and no default.
	local document fallback sanitized
	document="$1"
	fallback="${2:-}"

	if sanitized=$(printf '%s' "${document}" | jq -c '.' 2>/dev/null); then
		printf '%s' "${sanitized}"
		return 0
	fi

	if [[ -z "${fallback}" ]]; then
		return 1
	fi

	if sanitized=$(printf '%s' "${fallback}" | jq -c '.' 2>/dev/null); then
		printf '%s' "${sanitized}"
	else
		printf '{}'
	fi
}

json_state_resolve_document() {
	# Resolves the JSON document for a namespace without side effects.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - fallback JSON document (string, optional)
	# Returns:
	#   Resolved JSON document (string).
	local prefix fallback fallback_provided sanitized_fallback cache_document json_var document_value sanitized_document
	prefix="$1"
	fallback="${2:-}"
	fallback_provided=false
	if [[ -n "${fallback}" ]]; then
		fallback_provided=true
	fi

	json_var=$(json_state_namespace_var "${prefix}")

	# Hot path: trust already-loaded process state before touching the filesystem.
	if [[ -n "${!json_var+x}" ]]; then
		document_value="${!json_var}"
		if sanitized_document=$(json_state_sanitize_json "${document_value}" ""); then
			if [[ -n "${sanitized_document}" ]]; then
				printf '%s' "${sanitized_document}"
				return 0
			fi
		fi
	fi

	sanitized_fallback=$(json_state_sanitize_json "${fallback}" '{}')
	if [[ "${fallback_provided}" != true ]]; then
		# Only consult on-disk cache when caller did not explicitly request a fallback.
		cache_document=$(json_state_read_cache "${prefix}")
		if [[ -n "${cache_document}" ]]; then
			sanitized_fallback="${cache_document}"
		fi
	fi

	printf '%s' "${sanitized_fallback}"
}

json_state_get_document() {
	# Retrieves the JSON document for a namespace with optional fallback.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - fallback JSON document (string, optional; defaults to '{}')
	# Behavior:
	#   Returns the fallback when the namespaced variable is unset or contains
	#   invalid JSON, preventing downstream jq errors. When invalid in-memory
	#   JSON is repaired, persists the sanitized value to cache.
	local prefix fallback json_var fallback_provided resolved_document output_var
	local prior_document prior_has_value prior_is_valid
	prefix="$1"
	json_var=$(json_state_namespace_var "${prefix}")
	prior_document=""
	prior_has_value=false
	prior_is_valid=false
	if [[ -n "${!json_var+x}" ]]; then
		prior_has_value=true
		prior_document="${!json_var}"
		if json_state_sanitize_json "${prior_document}" "" >/dev/null 2>&1; then
			prior_is_valid=true
		fi
	fi

	if [[ $# -ge 3 && -n "${3}" ]]; then
		# Optional pass-by-name output keeps callers from reparsing stdout.
		output_var="$3"
	else
		output_var=""
	fi
	if [[ $# -ge 2 && -n "${2}" ]]; then
		fallback_provided=true
		fallback="$2"
	else
		fallback_provided=false
		fallback="{}"
	fi

	if [[ "${fallback_provided}" != true ]]; then
		# Empty fallback means resolve_document may prefer persisted cache content.
		fallback=""
	fi
	resolved_document=$(json_state_resolve_document "${prefix}" "${fallback}")
	printf -v "${json_var}" '%s' "${resolved_document}"

	# Persist repaired fallbacks so subsequent calls can recover from
	# malformed in-memory state even if the namespace is later unset.
	if [[ "${prior_has_value}" != true || "${prior_is_valid}" != true ]]; then
		json_state_write_cache "${prefix}" "${resolved_document}"
	fi

	if [[ -n "${output_var}" ]]; then
		printf -v "${output_var}" '%s' "${resolved_document}"
	fi

	printf '%s' "${resolved_document}"
}

json_state_set_document() {
	# Sets the JSON document for a namespace after validating JSON.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - JSON document (string)
	local prefix document json_var sanitized
	prefix="$1"
	document="$2"

	# Validate and store the document
	json_var=$(json_state_namespace_var "${prefix}")

	# Validate JSON
	if ! sanitized=$(printf '%s' "${document}" | jq -c '.' 2>/dev/null); then
		log "ERROR" "json_state_set_document: invalid JSON" "namespace=${prefix}" || true
		return 1
	fi

	# Store sanitized JSON
	printf -v "${json_var}" '%s' "${sanitized}"
	json_state_write_cache "${prefix}" "${sanitized}"
}

json_state_set_key() {
	# Sets a logical key in the JSON document.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - key (string)
	#   $3 - value (string)
	local prefix key value base_json updated
	prefix="$1"
	key="$2"
	value="$3"

	# Fetch current document
	json_state_get_document "${prefix}" '{}' base_json >/dev/null

	# Set the key
	if ! updated=$(jq -c --arg key "${key}" --arg value "${value}" '.[$key] = $value' <<<"${base_json}" 2>/dev/null); then
		log "ERROR" "json_state_set_key: failed to set value" "namespace=${prefix} key=${key}" || true
		return 1
	fi

	# Save updated document
	json_state_set_document "${prefix}" "${updated}"
}

json_state_get_key() {
	# Fetches a logical key from the JSON document.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - key (string)
	local prefix key document
	prefix="$1"
	key="$2"

	# Fetch current document
	json_state_get_document "${prefix}" '{}' document >/dev/null

	# Extract and return the key's value
	jq -r --arg key "${key}" '.[$key] // ""' <<<"${document}"
}

json_state_increment_key() {
	# Increments a numeric key in the JSON document.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - key (string)
	#   $3 - increment amount (int, optional; defaults to 1)
	local prefix key increment base_json updated
	prefix="$1"
	key="$2"
	increment="${3:-1}"

	# Fetch current document
	json_state_get_document "${prefix}" '{}' base_json >/dev/null

	# Increment the key
	if ! updated=$(jq -c --arg key "${key}" --argjson inc "${increment}" '.[$key] = ((try (.[$key]|tonumber) catch 0) + $inc)' <<<"${base_json}" 2>/dev/null); then
		log "ERROR" "json_state_increment_key: failed to increment" "namespace=${prefix} key=${key}" || true
		return 1
	fi

	# Save updated document
	json_state_set_document "${prefix}" "${updated}"
}

json_state_append_history() {
	# Appends an entry to the history array in the JSON document.
	# Arguments:
	#   $1 - namespace prefix (string)
	#   $2 - history entry (string)
	local prefix entry base_json updated
	prefix="$1"
	entry="$2"

	# Fetch current document
	json_state_get_document "${prefix}" '{}' base_json >/dev/null

	# Append to history array
	if ! updated=$(jq -c --arg entry "${entry}" '(.history //= []) | .history += [$entry]' <<<"${base_json}" 2>/dev/null); then
		log "ERROR" "json_state_append_history: failed to append history" "namespace=${prefix}" || true
		return 1
	fi

	# Save updated document
	json_state_set_document "${prefix}" "${updated}"
}
