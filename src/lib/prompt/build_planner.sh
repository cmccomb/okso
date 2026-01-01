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

build_planner_prompt_parts() {
        # Renders the planner prompt and splits it into prefix + suffix using the rendered date anchor.
        # Arguments:
        #   $1 - user query (string)
        #   $2 - formatted tool descriptions (string)
        #   $3 - pre-computed search context (string)
        #   $4 - variable name to receive the prefix (string)
        #   $5 - variable name to receive the suffix (string)
        # Returns:
        #   0 on success after setting the prefix/suffix variables.
        local user_query tool_lines search_context prefix_var suffix_var planner_schema current_date current_time current_weekday rendered anchor
        local rendered_prefix="" rendered_suffix=""
        user_query="$1"
        tool_lines="$2"
        search_context="$3"
        prefix_var="$4"
        suffix_var="$5"
        planner_schema="$(load_schema_text planner_plan)"
        current_date="$(current_date_local)"
        current_time="$(current_time_local)"
        current_weekday="$(current_weekday_local)"

        rendered="$(render_prompt_template "planner" \
                user_query "${user_query}" \
                tool_lines "${tool_lines}" \
                search_context "${search_context}" \
                planner_schema "${planner_schema}" \
                current_date "${current_date}" \
                current_time "${current_time}" \
                current_weekday "${current_weekday}")" || return 1

        anchor="${current_date}"

        if [[ "${rendered}" == *"${anchor}"* ]]; then
                rendered_prefix="${rendered%%"${anchor}"*}"
                rendered_suffix="${rendered:${#rendered_prefix}}"
        else
                rendered_prefix="${rendered}"
                rendered_suffix=""
        fi

        printf -v "${prefix_var}" '%s' "${rendered_prefix}"
        printf -v "${suffix_var}" '%s' "${rendered_suffix}"
}

build_planner_prompt_static_prefix() {
        # Returns the planner prompt prefix that precedes runtime fields.
        # Arguments:
        #   $1 - user query (string)
        #   $2 - formatted tool descriptions (string)
        #   $3 - pre-computed search context (string)
        # Returns:
        #   The rendered prompt prefix (string).
        local prefix="" suffix=""
        build_planner_prompt_parts "$1" "$2" "$3" prefix suffix || return 1
        printf '%s' "${prefix}"
}

build_planner_prompt_dynamic_suffix() {
        # Builds the runtime portion of the planner prompt.
        # Arguments:
        #   $1 - user query (string)
        #   $2 - formatted tool descriptions (string)
        #   $3 - pre-computed search context (string)
        # Returns:
        #   The dynamic suffix for the planner prompt (string).
        local prefix="" suffix=""
        build_planner_prompt_parts "$1" "$2" "$3" prefix suffix || return 1
        printf '%s' "${suffix}"
}

build_planner_prompt() {
        # Builds a prompt for the high-level planner.
        # Arguments:
        #   $1 - user query (string)
        #   $2 - formatted tool descriptions (string)
        #   $3 - pre-computed search context (string)
        # Returns:
        #   The full prompt text (string).
        local prefix="" suffix=""
        build_planner_prompt_parts "$1" "$2" "$3" prefix suffix || return 1
        printf '%s%s' "${prefix}" "${suffix}"
}

export -f build_planner_prompt
export -f build_planner_prompt_static_prefix
export -f build_planner_prompt_dynamic_suffix
