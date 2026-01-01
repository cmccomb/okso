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

# shellcheck source=../prompt/templates.sh disable=SC1091
source "${PLANNING_REPHRASING_DIR}/../prompt/templates.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_REPHRASING_DIR}/../core/logging.sh"
# shellcheck source=../schema/schema.sh disable=SC1091
source "${PLANNING_REPHRASING_DIR}/../schema/schema.sh"
# shellcheck source=../llm/llama_client.sh disable=SC1091
source "${PLANNING_REPHRASING_DIR}/../llm/llama_client.sh"

render_rephrase_prompt() {
        # Renders the rephrasing prompt with the user query embedded.
        # Arguments:
        #   $1 - user query (string)
	local user_query schema_json
	user_query="$1"

	schema_json="$(load_schema_text planner_search_queries 2>/dev/null || true)"

        render_prompt_template "planner_rephrase" USER_QUERY "${user_query}" PLANNER_SEARCH_SCHEMA "${schema_json}"
}

planner_generate_search_queries() {
        # Generates up to three search queries for the planner search stage.
        # Arguments:
        #   $1 - user query (string)
        # Returns:
	#   JSON array of 1-3 search queries (strings).
        local user_query prompt raw max_generation_tokens schema_json
	user_query="$1"
	max_generation_tokens=${REPHRASER_MAX_OUTPUT_TOKENS:-256}

	schema_json="$(load_schema_text planner_search_queries 2>/dev/null || true)"

	if ! [[ "${max_generation_tokens}" =~ ^[0-9]+$ ]] || ((max_generation_tokens < 1)); then
		max_generation_tokens=256
	fi

        if [[ "${LLAMA_AVAILABLE}" != true ]]; then
                log "WARN" "llama unavailable; using raw query for search" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
                jq -nc --arg query "${user_query}" '[ $query ]'
                return 0
        fi

	prompt="$(render_rephrase_prompt "${user_query}")" || {
		log "ERROR" "Failed to render rephrase prompt" "planner_rephrase_prompt_render_failed" >&2
                jq -nc --arg query "${user_query}" '[ $query ]'
                return 0
        }

        if ! raw="$(LLAMA_TEMPERATURE=0 llama_infer "${prompt}" '' "${max_generation_tokens}" "${schema_json}" "${SEARCH_REPHRASER_MODEL_REPO:-}" "${SEARCH_REPHRASER_MODEL_FILE:-}" "${SEARCH_REPHRASER_CACHE_FILE:-}" "${prompt}")"; then
                log "WARN" "Rephrase model invocation failed; falling back to user query" "planner_rephrase_infer_failed" >&2
                jq -nc --arg query "${user_query}" '[ $query ]'
                return 0
        fi

        if [[ -z "${raw}" ]]; then
                log "WARN" "Rephrase model returned empty output" "planner_rephrase_empty" >&2
                jq -nc --arg query "${user_query}" '[ $query ]'
                return 0
        fi

        log_pretty "INFO" "searches" "${raw}"

        printf '%s' "${raw}"
}

export -f planner_generate_search_queries
export -f render_rephrase_prompt
