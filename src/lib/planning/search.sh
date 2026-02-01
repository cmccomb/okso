#!/usr/bin/env bash
# shellcheck shell=bash
#
# Search helpers for planner pre-search context formatting and execution.
#
# Usage:
#   source "${BASH_SOURCE[0]%/search.sh}/search.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on failure.

PLANNING_SEARCH_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${PLANNING_SEARCH_DIR}/../core/logging.sh"
# shellcheck source=src/lib/planning/rephrasing.sh
source "${PLANNING_SEARCH_DIR}/rephrasing.sh"
# shellcheck source=src/lib/planning/intent.sh
source "${PLANNING_SEARCH_DIR}/intent.sh"

planner_format_search_context() {
	# Formats web search JSON into readable prompt text.
	# Arguments:
	#   $1 - raw search payload (JSON string)
	local raw_context formatted
	raw_context="$1"

	# Fallback when no context is available
	if [[ -z "${raw_context}" ]]; then
		printf '%s' "Search context unavailable."
		return 0
	fi

	# Format the search results
	if ! formatted=$(jq -r '
                def fmt(idx; item): "\(idx). \(item.title // \"Untitled\"): \(item.snippet // \"\") [\(item.url // \"\")";
                if (.items | length == 0) then
                        "No search results were captured for this query."
                else
                        "Query: \(.query // \"")\n" +
                        ((.items // []) | to_entries | map(fmt(.key + 1; .value)) | join("\n"))
                end
        ' <<<"${raw_context}" 2>/dev/null); then
		log "ERROR" "Failed to format search context" "planner_search_context_parse_error" >&2
		printf '%s' "Search context unavailable."
		return 0
	fi

	# Return the formatted context
	printf '%s' "${formatted}"
}

planner_fetch_search_context() {
	# Executes deterministic web searches for rephrased queries before planning.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - intent JSON payload (string, optional)
	# Returns:
	#   Formatted search context (string). Fallbacks are empty but non-fatal.
	local user_query intent_json tool_args raw_context queries_json formatted_context
	local -a formatted_sections=()
	user_query="$1"
	intent_json="${2:-}"

	if ! intent_requires_search "${intent_json}"; then
		log "INFO" "Pre-planner search skipped for intent" "${intent_json}" >&2
		printf '%s' ""
		return 0
	fi

	# Derive search queries
	if ! queries_json="$(planner_generate_search_queries "${user_query}")"; then
		log "WARN" "Failed to derive search queries; defaulting to raw query" "pre_planner_search_terms_failed" >&2
		queries_json="$(jq -nc --arg query "${user_query}" '[ $query ]' 2>/dev/null || printf '["%s"]' "${user_query}")"
	fi

	# Execute searches and format context
	local index=0
	while IFS= read -r search_query; do
		((index++))
		if [[ -z "${search_query}" ]]; then
			continue
		fi

		# Prepare tool arguments
		tool_args=$(jq -nc --arg query "${search_query}" '{query:$query, num:5}' 2>/dev/null)

		# Execute the search tool
		if [[ -z "${tool_args}" ]]; then
			log "WARN" "Failed to encode search args" "planner_search_args_encoding_failed" >&2
			raw_context=$(jq -nc --arg query "${search_query}" '{query:$query,items:[]}' 2>/dev/null)
		elif ! raw_context=$(TOOL_ARGS="${tool_args}" tool_web_search 2>/dev/null); then
			log "WARN" "Pre-plan search failed" "planner_preplan_search_failed" >&2
			raw_context=$(jq -nc --arg query "${search_query}" '{query:$query,items:[]}' 2>/dev/null)
		fi

		# Format the search context
		formatted_context=$(planner_format_search_context "${raw_context}")
		formatted_sections+=("Search ${index}: ${formatted_context}")
	done < <(jq -r '.[]' <<<"${queries_json}" 2>/dev/null)

	# Return the combined search context
	printf '%s' "$(printf '%s\n' "${formatted_sections[@]}" | sed '/^[[:space:]]*$/d' | paste -sd $'\n\n' -)"
}

export -f planner_format_search_context
export -f planner_fetch_search_context
