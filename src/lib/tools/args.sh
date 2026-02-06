#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared TOOL_ARGS parsing helpers for tool handlers.
#
# Usage:
#   source "${BASH_SOURCE[0]%/args.sh}/args.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions return non-zero on invalid TOOL_ARGS payloads.

TOOLS_ARGS_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${TOOLS_ARGS_LIB_DIR}/../core/logging.sh"

tool_args_parse_with_jq() {
	# Parses TOOL_ARGS with a provided jq filter and consistent error handling.
	# Arguments:
	#   $1 - jq filter (string)
	#   $2 - context label for error logs (string, optional)
	# Returns:
	#   Filter output on stdout.
	local jq_filter context_label args_json parsed
	jq_filter="$1"
	context_label="${2:-tool}"
	args_json="${TOOL_ARGS:-}"

	if [[ -z "${args_json}" ]]; then
		args_json='{}'
	fi

	if ! parsed="$(jq -cer "${jq_filter}" <<<"${args_json}" 2>&1)"; then
		log "ERROR" "Invalid ${context_label} arguments" "${parsed}" >&2
		return 1
	fi

	printf '%s' "${parsed}"
}

tool_args_parse_object() {
	# Ensures TOOL_ARGS is a JSON object.
	# Arguments:
	#   $1 - context label for error logs (string, optional)
	# Returns:
	#   Parsed object JSON on stdout.
	local context_label
	context_label="${1:-tool}"

	tool_args_parse_with_jq \
		'if type == "object" then . else error("args must be object") end' \
		"${context_label}"
}

tool_args_parse_strict_single_string() {
	# Parses a required string field (with optional aliases) and rejects extras.
	# Arguments:
	#   $1 - required canonical key (string; e.g., "input")
	#   $2 - comma-delimited alias keys (string, optional)
	#   $3 - context label for error logs (string, optional)
	# Returns:
	#   Extracted string value on stdout.
	local key aliases_csv context_label args_json parsed
	key="$1"
	aliases_csv="${2:-}"
	context_label="${3:-tool}"
	args_json="${TOOL_ARGS:-}"

	if [[ -z "${args_json}" ]]; then
		args_json='{}'
	fi

	if ! parsed="$(jq -cer \
		--arg key "${key}" \
		--arg aliases_csv "${aliases_csv}" \
		'
                def alias_keys:
                        ($aliases_csv
                                | split(",")
                                | map(gsub("^\\s+|\\s+$"; ""))
                                | map(select(length > 0)));

                . as $obj
                | if type != "object" then error("args must be object") else . end
                | ([$key] + alias_keys) as $keys
                | ([ $keys[] | ($obj[.] // empty) ]
                        | map(select(type == "string" and length > 0))
                        | .[0] // empty) as $value
                | if ($value | length) == 0 then error("missing " + $key) else . end
                | if ([keys[] | select(($keys | index(.)) == null)] | length) != 0 then
                        error("unexpected properties")
                  else
                        $value
                  end
        ' <<<"${args_json}" 2>&1)"; then
		log "ERROR" "Invalid ${context_label} arguments" "${parsed}" >&2
		return 1
	fi

	printf '%s' "${parsed}"
}

export -f tool_args_parse_with_jq
export -f tool_args_parse_object
export -f tool_args_parse_strict_single_string
