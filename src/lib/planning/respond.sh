#!/usr/bin/env bash
# shellcheck shell=bash
#
# Direct-response helpers for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/respond.sh}/respond.sh"
#
# Environment variables:
#   LLAMA_AVAILABLE (bool): whether llama.cpp is available for inference.
#   VERBOSITY (int): log verbosity level.
#
# Dependencies:
#   - bash 3.2+
#
# Exit codes:
#   Functions print responses and return 0 on success.

PLANNING_RESPOND_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_RESPOND_DIR}/../core/logging.sh"
# shellcheck source=../cli/output.sh disable=SC1091
source "${PLANNING_RESPOND_DIR}/../cli/output.sh"
# shellcheck source=./prompts.sh disable=SC1091
source "${PLANNING_RESPOND_DIR}/prompts.sh"
# shellcheck source=./schema.sh disable=SC1091
source "${PLANNING_RESPOND_DIR}/schema.sh"
# shellcheck source=./context_budget.sh disable=SC1091
source "${PLANNING_RESPOND_DIR}/context_budget.sh"
# shellcheck source=./llama_client.sh disable=SC1091
source "${PLANNING_RESPOND_DIR}/llama_client.sh"

respond_text() {
	# Generates a final fallback response using the LLM for a given user query.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - number of tokens to generate (int)
	#   $3 - context (string, optional)
	local user_query context prompt number_of_tokens concise_schema_path concise_schema_text
	user_query="$1"
	number_of_tokens="$2"
	context="${3:-}"
	concise_schema_path="$(schema_path concise_response)"
	concise_schema_text="$(load_schema_text concise_response)"

	log "INFO" "Generating final fallback response" "${user_query}" >&2

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "INFO" "LLM unavailable; using deterministic response fallback" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
		log "ERROR" "Falling back to deterministic response" "${user_query}" >&2
		user_output_line "LLM unavailable. Request received: ${user_query}"
		return 0
	fi

	if [[ "${LLAMA_BIN}" == *"mock_llama_relevance.sh" ]]; then
		log "INFO" "Mock llama direct response path" "${user_query}" >&2
		user_output_line "Responding directly to: ${user_query}"
		return 0
	fi

	local context_for_prompt
	prompt="$(build_final_answer_fallback_prompt "${user_query}" "${context}")"
	context_for_prompt="$(apply_prompt_context_budget "${prompt}" "${context}" "${number_of_tokens}" "direct_response")"
	prompt="$(build_final_answer_fallback_prompt "${user_query}" "${context_for_prompt}")"
	log "INFO" "Invoking llama inference" "$(printf 'tokens=%s schema=%s' "${number_of_tokens}" "${concise_schema_path}")" >&2
	local response_text
	response_text="$(llama_infer "${prompt}" "" "${number_of_tokens}" "${concise_schema_text}" "${REACT_MODEL_REPO:-}" "${REACT_MODEL_FILE:-}" "${REACT_CACHE_FILE:-}")"
	user_output "${response_text}"
	log "INFO" "Direct response generation finished" "${user_query}" >&2
	return 0
}
