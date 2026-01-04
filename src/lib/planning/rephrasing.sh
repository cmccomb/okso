#!/usr/bin/env bash
# shellcheck shell=bash
#
# Query rephrasing helpers for planner search seeding.
#
# Usage:
#   source "${BASH_SOURCE[0]%/rephrasing.sh}/rephrasing.sh"
#
# Environment variables:
#   SEARCH_REPHRASER_MODEL_REPO (string): HF repo for search rephrasing llama calls.
#   SEARCH_REPHRASER_MODEL_FILE (string): model file for search rephrasing llama calls.
#   SEARCH_REPHRASER_CACHE_FILE (string): prompt cache file for search rephrasing llama.cpp calls.
#   SEARCH_REPHRASER_DRY_ARGS (string): llama.cpp DRY sampling args for rephrasing calls; defaults to recommended settings.
#   LLAMA_AVAILABLE (bool): whether llama.cpp can run locally.
#   REPHRASER_MAX_OUTPUT_TOKENS (int >=1): llama.cpp generation budget for query rephrasing; defaults to 256.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation errors.

PLANNING_REPHRASING_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/prompt/templates.sh
source "${PLANNING_REPHRASING_DIR}/../prompt/templates.sh"
# shellcheck source=src/lib/core/logging.sh
source "${PLANNING_REPHRASING_DIR}/../core/logging.sh"
# shellcheck source=src/lib/schema/schema.sh
source "${PLANNING_REPHRASING_DIR}/../schema/schema.sh"
# shellcheck source=src/lib/llm/llama_client.sh
source "${PLANNING_REPHRASING_DIR}/../llm/llama_client.sh"

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

export -f planner_generate_search_queries
export -f render_rephrase_prompt
