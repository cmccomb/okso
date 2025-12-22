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
	# Returns:
	#   The dynamic suffix for the planner prompt (string).
	local user_query tool_lines planner_schema current_date current_time current_weekday rendered prefix web_search_constraints web_search_cap
	user_query="$1"
	tool_lines="$2"
	planner_schema="$(load_schema_text planner_plan)"
	current_date="$(current_date_local)"
	current_time="$(current_time_local)"
	current_weekday="$(current_weekday_local)"
	web_search_cap="${PLANNER_WEB_SEARCH_BUDGET_CAP:-2}"

	if [[ -z "${web_search_cap}" || ! "${web_search_cap}" =~ ^[0-9]+$ ]]; then
		web_search_cap=2
	fi

	rendered="$(render_prompt_template "planner" \
		user_query "${user_query}" \
		tool_lines "${tool_lines}" \
		planner_schema "${planner_schema}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}")"
	# Ensure the rendered prompt always includes the deterministic, budgeted web_search guidance
	# (acceptance criteria demand that planners limit searches and only use them to shape the plan).
	read -r -d '' web_search_constraints <<EOF || true
# Web search discipline (rationale: keeps planning deterministic and cost-bounded while still allowing lightweight fact checks)
Use web_search only when the user request cannot be planned without fresh context or public facts.
Cap web_search to at most ${web_search_cap} short, targeted queries.
You may not include more than ${web_search_cap} web_search steps in the plan; opt for fewer when possible.
Plans requesting more than ${web_search_cap} searches will be rejected; keep searches concise or note why none are needed.
Summarize results deterministically and solely to shape the plan; do not execute tasks or actions based on the search output.
EOF
	if [[ "${rendered}" != *"${web_search_constraints}"* ]]; then
		rendered="${rendered}"$'\n'"${web_search_constraints}"
	fi
	prefix="$(build_planner_prompt_static_prefix)" || return 1
	printf '%s' "${rendered#"${prefix}"}"
}

build_planner_prompt() {
	# Builds a prompt for the high-level planner.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted tool descriptions (string)
	# Returns:
	#   The full prompt text (string).
	local prefix suffix
	prefix="$(build_planner_prompt_static_prefix)" || return 1
	suffix="$(build_planner_prompt_dynamic_suffix "$1" "$2")" || return 1
	printf '%s%s' "${prefix}" "${suffix}"
}

export -f build_planner_prompt
export -f build_planner_prompt_static_prefix
export -f build_planner_prompt_dynamic_suffix
