#!/usr/bin/env bash
# shellcheck shell=bash
#
# Planner prompt builders.
#
# Usage:
#   source "${BASH_SOURCE[0]%/build_planner.sh}/build_planner.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions print prompts and return 0 on success.

PROMPT_BUILD_PLANNER_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./templates.sh disable=SC1091
source "${PROMPT_BUILD_PLANNER_DIR}/templates.sh"
# shellcheck source=../schema/schema.sh disable=SC1091
source "${PROMPT_BUILD_PLANNER_DIR}/../schema/schema.sh"
# shellcheck source=../time/time.sh disable=SC1091
source "${PROMPT_BUILD_PLANNER_DIR}/../time/time.sh"

load_planner_examples() {
	# Loads example planner traces for inclusion in the planner prompt.
	# Returns:
	#   The examples content (string), or an empty string when unavailable.
	local examples_path
	examples_path="${PROMPTS_DIR}/planner_examples.txt"

	if [[ -s "${examples_path}" ]]; then
		cat "${examples_path}"
		return 0
	fi

	if [[ -e "${examples_path}" ]]; then
		return 0
	fi

	log "WARN" "Planner examples missing; continuing without examples" "${examples_path}" || true
	return 0
}

build_planner_prompt_static_prefix() {
	# Returns the deterministic planner prompt prefix that excludes runtime fields.
	local template anchor
	template="$(load_prompt_template "planner")" || return 1
	anchor="\${current_date}"

	if [[ "${template}" != *"${anchor}"* ]]; then
		printf '%s' "${template}"
		return 0
	fi

	printf '%s' "${template%%"${anchor}"*}"
}

build_planner_prompt_dynamic_suffix() {
	# Builds the runtime portion of the planner prompt.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted tool descriptions (string)
	#   $3 - pre-computed search context (string)
	# Returns:
	#   The dynamic suffix for the planner prompt (string).
	local user_query tool_lines search_context planner_examples planner_schema current_date current_time current_weekday rendered prefix
	user_query="$1"
	tool_lines="$2"
	search_context="$3"
	planner_examples="$(load_planner_examples)"
	planner_schema="$(load_schema_text planner_plan)"
	current_date="$(current_date_local)"
	current_time="$(current_time_local)"
	current_weekday="$(current_weekday_local)"

	rendered="$(render_prompt_template "planner" \
		user_query "${user_query}" \
		tool_lines "${tool_lines}" \
		search_context "${search_context}" \
		planner_examples "${planner_examples}" \
		planner_schema "${planner_schema}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}")"
	prefix="$(build_planner_prompt_static_prefix)" || return 1
	printf '%s' "${rendered#"${prefix}"}"
}

build_planner_prompt() {
	# Builds a prompt for the high-level planner.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted tool descriptions (string)
	#   $3 - pre-computed search context (string)
	# Returns:
	#   The full prompt text (string).
	local prefix suffix
	prefix="$(build_planner_prompt_static_prefix)" || return 1
	suffix="$(build_planner_prompt_dynamic_suffix "$1" "$2" "$3")" || return 1
	printf '%s%s' "${prefix}" "${suffix}"
}

export -f build_planner_prompt
export -f build_planner_prompt_static_prefix
export -f build_planner_prompt_dynamic_suffix
