#!/usr/bin/env bash
# shellcheck shell=bash
#
# Prompt context budgeting helpers for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/context_budget.sh}/context_budget.sh"
#
# Environment variables:
#   PROMPT_TOKEN_BUDGET (int): total prompt + completion token cap (default: 4096).
#   SUMMARY_LINE_CHAR_LIMIT (int): maximum characters to preserve per context line when summarizing (default: 240).
#
# Dependencies:
#   - bash 3.2+
#
# Exit codes:
#   Functions print derived strings and return 0 on success.

LLM_CONTEXT_BUDGET_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Initialize default values for optional environment variables
PROMPT_TOKEN_BUDGET=${PROMPT_TOKEN_BUDGET:-4096}

# Default character limit per line when summarizing context blocks
SUMMARY_LINE_CHAR_LIMIT=${SUMMARY_LINE_CHAR_LIMIT:-240}

# shellcheck source=../core/logging.sh disable=SC1091
source "${LLM_CONTEXT_BUDGET_DIR}/../core/logging.sh"
# shellcheck source=./tokens.sh disable=SC1091
source "${LLM_CONTEXT_BUDGET_DIR}/tokens.sh"

estimate_total_tokens() {
	# Estimates the total tokens for a prompt plus desired completion.
	# Arguments:
	#   $1 - prompt text (string)
	#   $2 - max completion tokens (int)
	# Returns:
	#   Estimated total tokens (int)
	local prompt_text completion_tokens prompt_tokens
	prompt_text="$1"
	completion_tokens=${2:-0}

	# Estimate prompt tokens
	prompt_tokens=$(estimate_token_count "${prompt_text}")

	# Return total tokens
	echo $((prompt_tokens + completion_tokens))
}

truncate_for_summary() {
	# Produces a condensed, single-line summary for oversized content.
	# Arguments:
	#   $1 - content to summarize (string)
	#   $2 - character limit (int)
	# Returns:
	#   Summarized content (string)
	local content limit cleaned
	content="$1"
	limit="$2"

	# Replace newlines and carriage returns with spaces
	cleaned="${content//$'\n'/ }"
	cleaned="${cleaned//$'\r'/ }"

	# Collapse multiple spaces
	while [[ "${cleaned}" == *"  "* ]]; do
		cleaned="${cleaned//  / }"
	done

	# If within limit, return as-is
	if ((${#cleaned} <= limit)); then
		printf '%s' "${cleaned}"
		return 0
	fi

	# Truncate and indicate original length
	printf '%s… (truncated, original %s chars)' "${cleaned:0:limit}" "${#cleaned}"
}

summarize_context_block() {
	# Summarizes oversized context lines, with special handling for web_fetch content.
	# Arguments:
	#   $1 - raw context text (string)
	#   $2 - character limit per line (int, optional)
	# Returns:
	#   Summarized context text (string)
	local context_text line_char_limit
	context_text="$1"
	line_char_limit=${2:-${SUMMARY_LINE_CHAR_LIMIT}}
	local -a summarized_lines=()

	# Process each line
	while IFS= read -r line || [[ -n "${line}" ]]; do
		local prefixless leading_spaces
		leading_spaces="${line%%[![:space:]]*}"
		prefixless="${line#"${leading_spaces}"}"
		# Preserve empty lines and short content.
		if [[ -z "${prefixless}" ]]; then
			summarized_lines+=("${line}")
			continue
		fi

		# Special handling for web_fetch content lines.
		local trimmed
		if [[ "${prefixless}" =~ ^Content: ]]; then
			trimmed="$(truncate_for_summary "${prefixless#Content: }" "${line_char_limit}")"
			summarized_lines+=("${leading_spaces}Content summary: ${trimmed}")
			continue
		fi

		# Summarize lines exceeding the character limit.
		if ((${#prefixless} > line_char_limit)); then
			trimmed="$(truncate_for_summary "${prefixless}" "${line_char_limit}")"
			summarized_lines+=("${leading_spaces}${trimmed}")
			continue
		fi

		# Preserve lines within the limit.
		summarized_lines+=("${line}")
	done <<<"${context_text}"

	# Output summarized lines
	printf '%s\n' "${summarized_lines[@]}"
}

apply_prompt_context_budget() {
	# Returns context text, summarizing when the prompt would exceed the token cap.
	# Arguments:
	#   $1 - full prompt text containing the context (string)
	#   $2 - context text to potentially summarize (string)
	#   $3 - max completion tokens expected (int)
	#   $4 - context label for logging (string)
	# Returns:
	#   Context text, summarized if needed (string)

	local prompt_text context_text max_completion_tokens context_label
	prompt_text="$1"
	context_text="$2"
	max_completion_tokens=${3:-0}
	context_label="$4"

	# Estimate total tokens for prompt + completion
	local estimated_total
	estimated_total=$(estimate_total_tokens "${prompt_text}" "${max_completion_tokens}")
	if ((estimated_total <= PROMPT_TOKEN_BUDGET)); then
		printf '%s' "${context_text}"
		return 0
	fi

	# Summarize context to fit within budget
	local summarized_context context_tokens summarized_tokens adjusted_total prompt_tokens base_prompt_tokens
	summarized_context="$(summarize_context_block "${context_text}" "${SUMMARY_LINE_CHAR_LIMIT}")"
	prompt_tokens=$((estimated_total - max_completion_tokens))
	context_tokens=$(estimate_token_count "${context_text}")
	summarized_tokens=$(estimate_token_count "${summarized_context}")
	base_prompt_tokens=$((prompt_tokens - context_tokens))
	((base_prompt_tokens < 0)) && base_prompt_tokens=0
	adjusted_total=$((base_prompt_tokens + summarized_tokens + max_completion_tokens))

	# Further adjust if still over budget
	if ((adjusted_total > PROMPT_TOKEN_BUDGET)); then
		local remaining_budget max_characters_for_context
		remaining_budget=$((PROMPT_TOKEN_BUDGET - base_prompt_tokens - max_completion_tokens))
		((remaining_budget < 0)) && remaining_budget=0

		# If no budget remains, clear context; otherwise, truncate summarized context further
		if ((remaining_budget == 0)); then
			summarized_context=""
			summarized_tokens=0
			adjusted_total=$((base_prompt_tokens + max_completion_tokens))
		else
			max_characters_for_context=$((remaining_budget * 4))
			summarized_context="$(truncate_for_summary "${summarized_context}" "${max_characters_for_context}")"
			summarized_tokens=$(estimate_token_count "${summarized_context}")
			adjusted_total=$((base_prompt_tokens + summarized_tokens + max_completion_tokens))
		fi
	fi

	# Log the summarization action
	log "INFO" "Summarizing context to respect prompt budget" \
		"$(printf 'label=%s before=%s after=%s budget=%s' "${context_label}" "${estimated_total}" "${adjusted_total}" "${PROMPT_TOKEN_BUDGET}")"

	# Return the summarized context
	printf '%s' "${summarized_context}"
}
