#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final answer evaluation module for iterative replanning.
#
# This module evaluates whether a final answer satisfies the original user query
# and either returns an evaluator-produced final answer or requests replanning
# based on the execution trace.
#
# Usage:
#   source "${BASH_SOURCE[0]%/validation.sh}/validation.sh"
#
# Functions:
#   evaluate_final_answer_against_query() - Evaluate final answer against query
#   build_evaluation_prompt() - Build the evaluation prompt
#
# Environment variables:
#   LLAMA_AVAILABLE (bool): Whether llama.cpp is available
#   VALIDATOR_MODEL_REPO (string): Hugging Face repo for 8B validator model
#   VALIDATOR_MODEL_FILE (string): Model file for validator
#   VALIDATOR_CACHE_FILE (string): Cache file for validator inference
#   VALIDATION_MAX_TOKENS (int): Max tokens for evaluator response (default: 2048)
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - llama.cpp binaries
#   - llm/templates.sh for template rendering

VALIDATION_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VALIDATION_PARENT_DIR=$(cd -- "${VALIDATION_LIB_DIR}/.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${VALIDATION_PARENT_DIR}/core/logging.sh"
# shellcheck source=src/lib/llm/llama_client.sh
source "${VALIDATION_PARENT_DIR}/llm/llama_client.sh"
# shellcheck source=src/lib/llm/schema.sh
source "${VALIDATION_PARENT_DIR}/llm/schema.sh"
# shellcheck source=src/lib/llm/context_budget.sh
source "${VALIDATION_PARENT_DIR}/llm/context_budget.sh"
# shellcheck source=src/lib/llm/templates.sh
source "${VALIDATION_PARENT_DIR}/llm/templates.sh"

build_evaluation_prompt() {
	# Builds a prompt for evaluating a final answer against the original query.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - execution trace/history (string, optional)
	# Returns:
	#   The validation prompt text
	local user_query trace
	user_query="$1"
	trace="${2:-}"

	# Load prompt template from prompts/final_answer_evaluation.md and render substitutions
	render_prompt_template "final_answer_evaluation" \
		user_query "${user_query}" \
		trace "${trace}" \
		evaluation_schema "$(load_schema_text "final_answer_evaluation")"
}

evaluate_final_answer_against_query() {
	# Evaluates whether a final answer satisfies the original user query.
	# Uses the 8B model to perform evaluation.
	#
	# Arguments:
	#   $1 - user query (string)
	#   $2 - execution trace/history (string, optional)
	#   $3 - output variable name for validation result (optional)
	#
	# Returns:
	#   0 if evaluation succeeded, 2 if evaluation failed
	#   The evaluation result JSON is written to the specified output variable
	#   or stdout if no variable name provided.
	#
	# Output JSON structure:
	#   {
	#     "evaluation_type": "FINAL | REPLAN",
	#     "reasoning": string,
	#     "output": string
	#   }

	local user_query trace output_var
	user_query="$1"
	trace="${2:-}"
	output_var="${3:-}"

	# Check llama availability
	if [[ "${LLAMA_AVAILABLE:-false}" != true ]]; then
		log "WARN" "LLM unavailable; skipping final answer evaluation" || true
		return 2
	fi

	# Build the evaluation prompt
	local evaluation_prompt response response_json prompt_safe_trace prompt_raw
	prompt_raw="$(build_evaluation_prompt "${user_query}" "${trace}")"

	# Load the evaluation schema
	local schema_text
	schema_text="$(load_schema_text "final_answer_evaluation")" || {
		log "ERROR" "Failed to load evaluation schema text" || true
		return 2
	}
	log "INFO" "Evaluating final answer against query" || true

	# Use 8B model for validation (default to executor model if validator not specified)
	local validator_model_repo validator_model_file validator_cache_file
	validator_model_repo="${VALIDATOR_MODEL_REPO:-${EXECUTOR_MODEL_REPO:-}}"
	validator_model_file="${VALIDATOR_MODEL_FILE:-${EXECUTOR_MODEL_FILE:-}}"
	validator_cache_file="${VALIDATOR_CACHE_FILE:-${EXECUTOR_CACHE_FILE:-}}"

	# Invoke the evaluator model
	local validation_max_tokens
	validation_max_tokens="${VALIDATION_MAX_TOKENS:-2048}"

	prompt_safe_trace="$(apply_prompt_context_budget "${prompt_raw}" "${trace}" "${validation_max_tokens}" "validation_trace")"
	evaluation_prompt="$(build_evaluation_prompt "${user_query}" "${prompt_safe_trace}")"

	if ! response="$(llama_infer "${evaluation_prompt}" "" "${validation_max_tokens}" "${schema_text}" "${validator_model_repo}" "${validator_model_file}" "${validator_cache_file}")"; then
		log "ERROR" "Evaluator model invocation failed" || true
		return 2
	fi

	if ! response_json="$(jq -ce '
                if type != "object" then
                        empty
                elif (.evaluation_type | type) != "string" then
                        empty
                elif (.reasoning | type) != "string" then
                        empty
                elif (.output | type) != "string" then
                        empty
                else
                        .
                end
        ' <<<"${response}" 2>/dev/null)"; then
		log "ERROR" "Evaluator returned invalid JSON" "$(printf 'response=%s' "${response}")" || true
		return 2
	fi

	# Log the evaluation result
	local evaluation_type reasoning
	evaluation_type="$(jq -r '.evaluation_type' <<<"${response_json}")"
	reasoning="$(jq -r '.reasoning' <<<"${response_json}")"
	log "INFO" "Evaluation result" "$(printf 'type=%s, %s' "${evaluation_type}" "${reasoning}")" || true

	# Output result
	if [[ -n "${output_var}" ]]; then
		printf -v "${output_var}" '%s' "${response_json}"
	else
		printf '%s' "${response_json}"
	fi
}

export -f evaluate_final_answer_against_query
export -f build_evaluation_prompt
