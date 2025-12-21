#!/usr/bin/env bash
# shellcheck shell=bash
#
# ReAct prompt builders.
#
# Usage:
#   source "${BASH_SOURCE[0]%/build_react.sh}/build_react.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions print prompts and return 0 on success.

PROMPT_BUILD_REACT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./templates.sh disable=SC1091
source "${PROMPT_BUILD_REACT_DIR}/templates.sh"
# shellcheck source=../runtime/time.sh disable=SC1091
source "${PROMPT_BUILD_REACT_DIR}/../runtime/time.sh"

build_react_prompt_static_prefix() {
	# Returns the deterministic ReAct prompt prefix that excludes runtime fields.
	local template anchor
	template="$(load_prompt_template "react")" || return 1
	anchor="\${current_date}"

	if [[ "${template}" != *"${anchor}"* ]]; then
		printf '%s' "${template}"
		return 0
	fi

	printf '%s' "${template%%"${anchor}"*}"
}

build_react_prompt_dynamic_suffix() {
	# Builds the runtime portion of the ReAct execution prompt.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted allowed tool descriptions (string)
	#   $3 - high-level plan outline (string)
	#   $4 - prior interaction history (string)
	#   $5 - JSON schema describing allowed ReAct actions (string)
	#   $6 - current plan step guidance (string)
	# Returns:
	#   The dynamic suffix for the ReAct prompt (string).
	local user_query allowed_tools plan_outline history react_schema plan_step current_date current_time current_weekday
	local rendered prefix
	user_query="$1"
	allowed_tools="$2"
	plan_outline="$3"
	history="$4"
	react_schema="$5"
	plan_step="$6"
	current_date="$(current_date_utc)"
	current_time="$(current_time_utc)"
	current_weekday="$(current_weekday_utc)"

	rendered="$(render_prompt_template "react" \
		user_query "${user_query}" \
		allowed_tools "${allowed_tools}" \
		plan_outline "${plan_outline}" \
		history "${history}" \
		react_schema "${react_schema}" \
		plan_step "${plan_step}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}")"
	prefix="$(build_react_prompt_static_prefix)" || return 1
	printf '%s' "${rendered#"${prefix}"}"
}

build_react_prompt() {
	# Builds a prompt for the ReAct execution loop.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted allowed tool descriptions (string)
	#   $3 - high-level plan outline (string)
	#   $4 - prior interaction history (string)
	#   $5 - JSON schema describing allowed ReAct actions (string)
	#   $6 - current plan step guidance (string)
	# Returns:
	#   The full prompt text (string).
	local prefix suffix
	prefix="$(build_react_prompt_static_prefix)" || return 1
	suffix="$(build_react_prompt_dynamic_suffix "$1" "$2" "$3" "$4" "$5" "$6")" || return 1
	printf '%s%s' "${prefix}" "${suffix}"
}

export -f build_react_prompt
export -f build_react_prompt_static_prefix
export -f build_react_prompt_dynamic_suffix
