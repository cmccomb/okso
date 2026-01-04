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

# shellcheck source=src/lib/prompt/templates.sh
source "${PROMPT_BUILD_PLANNER_DIR}/templates.sh"
# shellcheck source=src/lib/schema/schema.sh
source "${PROMPT_BUILD_PLANNER_DIR}/../schema/schema.sh"

build_planner_prompt() {
        # Builds a prompt for the high-level planner.
        # Arguments:
        #   $1 - user query (string)
        #   $2 - formatted tool descriptions (string)
        #   $3 - pre-computed search context (string)
        #   $4 - optional planner feedback or constraints (string)
        # Returns:
        #   The full prompt text (string).
        local user_query tool_lines search_context planner_schema current_date current_time current_weekday rendered
        local planner_feedback

        user_query="$1"
        tool_lines="$2"
        search_context="$3"
        planner_feedback="$4"

        if [[ -z "${planner_feedback}" ]]; then
                planner_feedback="None provided."
        fi

	# Get current date/time info
	current_date="$(date '+%Y-%m-%d')"
	current_time="$(date '+%H:%M:%S')"
	current_weekday="$(date '+%A')"

	# Load the planner schema
	planner_schema="$(load_schema_text planner_plan)"

	# Render the prompt
	rendered="$(render_prompt_template "planner" \
		user_query "${user_query}" \
		tool_lines "${tool_lines}" \
		search_context "${search_context}" \
                planner_schema "${planner_schema}" \
                current_date "${current_date}" \
                current_time "${current_time}" \
                current_weekday "${current_weekday}" \
                planner_feedback "${planner_feedback}")" || return 1

	# Return the rendered prompt
	printf "%s" "${rendered}"
}

export -f build_planner_prompt
