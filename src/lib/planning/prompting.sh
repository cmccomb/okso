#!/usr/bin/env bash
# shellcheck shell=bash
#
# Prompt and outline helpers for the okso planner.
#
# Usage:
#   source "${BASH_SOURCE[0]%/prompting.sh}/prompting.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation errors.

PLANNING_PROMPTING_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../formatting.sh disable=SC1091
source "${PLANNING_PROMPTING_DIR}/../formatting.sh"
# shellcheck source=./prompts.sh disable=SC1091
source "${PLANNING_PROMPTING_DIR}/prompts.sh"
# shellcheck source=./schema.sh disable=SC1091
source "${PLANNING_PROMPTING_DIR}/schema.sh"
# shellcheck source=./normalization.sh disable=SC1091
source "${PLANNING_PROMPTING_DIR}/normalization.sh"

build_planner_prompt_with_tools() {
        # Builds the planner prompt using available tool descriptions.
        # Arguments:
        #   $1 - user query (string)
        #   $2... - tool names (strings)
        local user_query tool_lines
        local -a tools=()
        user_query="$1"
        shift
        tools=("$@")

        if ((${#tools[@]} > 0)); then
                tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${tools[@]}")" format_tool_summary_line)"
        else
                tool_lines=""
        fi

        build_planner_prompt "${user_query}" "${tool_lines}"
}

plan_json_to_outline() {
        # Converts a JSON array of plan steps into a numbered outline string.
        # Arguments:
        #   $1 - plan JSON array (string)
        local plan_json plan_clean
        plan_json="${1:-[]}"

        if jq -e 'type == "array"' <<<"${plan_json}" >/dev/null 2>&1; then
                plan_clean="${plan_json}"
        else
                plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)" || return 1
        fi

        if [[ -z "${plan_clean}" ]]; then
                return 1
        fi

        jq -r 'to_entries | map("\(.key + 1). " + (if (.value.thought // "") != "" then (.value.thought // "") else "Use " + (.value.tool // "unknown") end)) | join("\n")' <<<"${plan_clean}"
}

export -f plan_json_to_outline
export -f build_planner_prompt_with_tools
