#!/usr/bin/env bash
# shellcheck shell=bash
#
# Final-answer prompt builders.
#
# Usage:
#   source "${BASH_SOURCE[0]%/build_final_answer.sh}/build_final_answer.sh"
#
# Dependencies:
#   - bash 3.2+
#
# Exit codes:
#   Functions print prompts and return 0 on success.

PROMPT_BUILD_FINAL_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./templates.sh disable=SC1091
source "${PROMPT_BUILD_FINAL_DIR}/templates.sh"
# shellcheck source=../schema/schema.sh disable=SC1091
source "${PROMPT_BUILD_FINAL_DIR}/../schema/schema.sh"
# shellcheck source=../runtime/time.sh disable=SC1091
source "${PROMPT_BUILD_FINAL_DIR}/../runtime/time.sh"

build_final_answer_fallback_prompt() {
	# Builds a prompt for summarizing a final answer from prior agent context.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - context (string, optional)
	# Returns:
	#   The full prompt text (string).
	local user_query context final_fallback_schema current_date current_time current_weekday
	user_query="$1"
	context="${2:-}"
	final_fallback_schema="$(load_schema_text concise_response)"
	current_date="$(current_date_utc)"
	current_time="$(current_time_utc)"
	current_weekday="$(current_weekday_utc)"

	render_prompt_template "final_answer_fallback" \
		user_query "${user_query}" \
		context "${context}" \
		final_fallback_schema "${final_fallback_schema}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}"
}

export -f build_final_answer_fallback_prompt
