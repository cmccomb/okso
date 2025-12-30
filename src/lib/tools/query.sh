#!/usr/bin/env bash
# shellcheck shell=bash
#
# Query extraction helpers for tool invocations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/query.sh}/query.sh"
#
# Environment variables:
#   CANONICAL_TEXT_ARG_KEY (string): preferred key for single-string args; default: "input".
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - ../tools/registry.sh
#
# Exit codes:
#   Functions return non-zero on misuse.

TOOLS_QUERY_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${TOOLS_QUERY_LIB_DIR}/../core/logging.sh"
# shellcheck source=../../tools/registry.sh disable=SC1091
source "${TOOLS_QUERY_LIB_DIR}/../../tools/registry.sh"

extract_tool_query() {
	# Derives a human-readable query string for a tool invocation.
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - args JSON string (object or string)
	local args_json text_key query
	args_json="${2:-"{}"}"
	text_key="$(canonical_text_arg_key)"

	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi

	query="$(jq -r \
		--arg key "${text_key}" \
		'if type == "object" then
                        if (.[$key] // "" | type) == "string" then .[$key]
                        elif (.query // "" | type) == "string" then .query
                        elif (.input // "" | type) == "string" then .input
                        else ""
                        end
                elif type == "string" then
                        .
                else
                        ""
                end' <<<"${args_json}" 2>/dev/null || printf '')"

	printf '%s' "${query}"
}

export -f extract_tool_query
