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
# Added: llm/template/schema/llama sources (previously in rephrasing.sh)
# shellcheck source=src/lib/llm/templates.sh
source "${PLANNING_SEARCH_DIR}/../llm/templates.sh"
# shellcheck source=src/lib/llm/schema.sh
source "${PLANNING_SEARCH_DIR}/../llm/schema.sh"
# shellcheck source=src/lib/llm/llama_client.sh
source "${PLANNING_SEARCH_DIR}/../llm/llama_client.sh"
# shellcheck source=src/lib/intent/intent.sh
source "${PLANNING_SEARCH_DIR}/../intent/intent.sh"

# Inlined rephrasing helpers (merged from rephrasing.sh)
render_rephrase_prompt() {
	# Renders the rephrasing prompt with the user query embedded.
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   rendered prompt on stdout; non-zero on failure.
	local user_query schema_json
	user_query="$1"

	# Load the schema for validation
	schema_json="$(load_schema_text pre_planner_search_terms 2>/dev/null || true)"

	# Render the prompt template
	render_prompt_template "pre_planner_search_terms" USER_QUERY "${user_query}" PLANNER_SEARCH_SCHEMA "${schema_json}"
}

planner_generate_search_queries() {
	# Generates up to three search queries for the planner search stage.
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   JSON array of 1-3 search queries (strings).
	local user_query prompt raw max_generation_tokens schema_json dry_sampling_args
	user_query="$1"

	# Determine max generation tokens
	max_generation_tokens=${REPHRASER_MAX_OUTPUT_TOKENS:-256}

	# Load the schema for validation
	schema_json="$(load_schema_text pre_planner_search_terms 2>/dev/null || true)"

	# Validate max generation tokens
	if ! [[ "${max_generation_tokens}" =~ ^[0-9]+$ ]] || ((max_generation_tokens < 1)); then
		max_generation_tokens=256
	fi

	dry_sampling_args="${SEARCH_REPHRASER_DRY_ARGS:---dry-multiplier 0.35 --dry-base 1.75 --dry-allowed-length 2 --dry-penalty-last-n 1024 --dry-sequence-breaker none}"

	# Check llama availability
	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "llama unavailable; using raw query for search" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
		jq -nc --arg query "${user_query}" '[ $query ]'
		return 0
	fi

	# Render the rephrase prompt
	prompt="$(render_rephrase_prompt "${user_query}")" || {
		log "ERROR" "Failed to render rephrase prompt" "pre_planner_search_terms_prompt_render_failed" >&2
		jq -nc --arg query "${user_query}" '[ $query ]'
		return 0
	}

	# Invoke the rephrase model
	if ! raw="$(LLAMA_TEMPERATURE=0.7 LLAMA_EXTRA_ARGS="${dry_sampling_args}" llama_infer "${prompt}" '' "${max_generation_tokens}" "${schema_json}" "${SEARCH_REPHRASER_MODEL_REPO:-}" "${SEARCH_REPHRASER_MODEL_FILE:-}" "${SEARCH_REPHRASER_CACHE_FILE:-}" "${prompt}")"; then
		log "WARN" "Rephrase model invocation failed; falling back to user query" "pre_planner_search_terms_infer_failed" >&2
		jq -nc --arg query "${user_query}" '[ $query ]'
		return 0
	fi

	log_pretty "INFO" "searches" "${raw}"

	printf '%s' "${raw}"
}

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
                def fmt(idx; item):
                        (idx | tostring)
                        + ". "
                        + (item.title // "Untitled")
                        + ": "
                        + (item.snippet // "")
                        + " ["
                        + (item.url // "")
                        + "]";
                if ((.items // []) | length == 0) then
                        "No search results were captured for this query."
                else
                        "Query: " + (.query // "") + "\n"
                        + ((.items // []) | to_entries | map(fmt(.key + 1; .value)) | join("\n"))
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
# Export merged rephrasing functions for backward compatibility
export -f planner_generate_search_queries
export -f render_rephrase_prompt
