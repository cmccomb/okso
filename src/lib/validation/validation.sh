#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final answer validation module for iterative replanning.
#
# This module validates whether a final answer satisfies the original user query
# by using the 8B model to check answer-query alignment. If validation fails,
# the system can optionally trigger replanning.
#
# Usage:
#   source "${BASH_SOURCE[0]%/validation.sh}/validation.sh"
#
# Functions:
#   validate_final_answer_against_query() - Check if final answer satisfies query
#   build_validation_prompt() - Build the validation prompt
#
# Environment variables:
#   LLAMA_AVAILABLE (bool): Whether llama.cpp is available
#   VALIDATOR_MODEL_REPO (string): Hugging Face repo for 8B validator model
#   VALIDATOR_MODEL_FILE (string): Model file for validator
#   VALIDATOR_CACHE_FILE (string): Cache file for validator inference
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - llama.cpp binaries
#   - prompt/templates.sh for template rendering

VALIDATION_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VALIDATION_PARENT_DIR=$(cd -- "${VALIDATION_LIB_DIR}/.." && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${VALIDATION_PARENT_DIR}/core/logging.sh"
# shellcheck source=../llm/llama_client.sh disable=SC1091
source "${VALIDATION_PARENT_DIR}/llm/llama_client.sh"
# shellcheck source=../schema/schema.sh disable=SC1091
source "${VALIDATION_PARENT_DIR}/schema/schema.sh"
# shellcheck source=../prompt/templates.sh disable=SC1091
source "${VALIDATION_PARENT_DIR}/prompt/templates.sh"

build_validation_prompt() {
	# Builds a prompt for validating a final answer against the original query.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - final answer text (string)
	#   $3 - execution trace/history (string, optional)
	# Returns:
	#   The validation prompt text
	local user_query final_answer trace
	user_query="$1"
	final_answer="$2"
	trace="${3:-}"

	# Load prompt template from prompts/final_answer_validation.txt and render substitutions
	render_prompt_template "final_answer_validation" \
		user_query "${user_query}" \
		final_answer "${final_answer}" \
		trace "${trace}"
}

validate_final_answer_against_query() {
	# Validates whether a final answer satisfies the original user query.
	# Uses the 8B model to perform validation.
	#
	# Arguments:
	#   $1 - user query (string)
	#   $2 - final answer text (string)
	#   $3 - execution trace/history (string, optional)
	#   $4 - output variable name for validation result (optional)
	#
	# Returns:
	#   0 if answer is validated as satisfied, 1 if not, 2 if validation failed
	#   The validation result JSON is written to the specified output variable
	#   or stdout if no variable name provided.
	#
	# Output JSON structure:
	#   {
	#     "satisfied": boolean,
	#     "reasoning": string,
	#   }

	local user_query final_answer trace output_var
	user_query="$1"
	final_answer="$2"
	trace="${3:-}"
	output_var="${4:-}"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "LLM unavailable; skipping final answer validation" || true
		return 2
	fi

	local validation_prompt response
	validation_prompt="$(build_validation_prompt "${user_query}" "${final_answer}" "${trace}")"

	local schema_text
	schema_text="$(load_schema_text "final_answer_validation")" || {
		log "ERROR" "Failed to load validation schema text" || true
		return 2
	}

	log "INFO" "Validating final answer against query" || true

	# Use 8B model for validation (default to executor model if validator not specified)
	local validator_model_repo validator_model_file validator_cache_file
	validator_model_repo="${VALIDATOR_MODEL_REPO:-${EXECUTOR_MODEL_REPO:-}}"
	validator_model_file="${VALIDATOR_MODEL_FILE:-${EXECUTOR_MODEL_FILE:-}}"
	validator_cache_file="${VALIDATOR_CACHE_FILE:-${EXECUTOR_CACHE_FILE:-}}"

        response="$(llama_infer "${validation_prompt}" "" 512 "${schema_text}" "${validator_model_repo}" "${validator_model_file}" "${validator_cache_file}")"

        if [[ -z "${response}" ]]; then
                log "ERROR" "Validation inference returned empty response" || true
                return 2
        fi

        # Log the validation result
        local satisfied reasoning
        satisfied="$(jq -r '.satisfied' <<<"${response}")"
        reasoning="$(jq -r '.reasoning' <<<"${response}")"

	log "INFO" "Validation result" "$(printf 'satisfied=%s, %s' "${satisfied}" "${reasoning}")" || true

	# Output result
	if [[ -n "${output_var}" ]]; then
		printf -v "${output_var}" '%s' "${response}"
	else
		printf '%s' "${response}"
	fi

	# Return based on satisfaction
	if [[ "${satisfied}" == "true" ]]; then
		return 0
	else
		return 1
	fi
}

export -f validate_final_answer_against_query
export -f build_validation_prompt
