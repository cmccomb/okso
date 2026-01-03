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

# shellcheck source=src/lib/formatting.sh
source "${PLANNING_PROMPTING_DIR}/../formatting.sh"
# shellcheck source=src/lib/prompt/build_planner.sh
source "${PLANNING_PROMPTING_DIR}/../prompt/build_planner.sh"
# shellcheck source=src/lib/schema/schema.sh
source "${PLANNING_PROMPTING_DIR}/../schema/schema.sh"
# shellcheck source=src/lib/planning/normalization.sh
source "${PLANNING_PROMPTING_DIR}/normalization.sh"

build_planner_prompt_with_tools() {
	# Builds the planner prompt using available tool descriptions.
	# Arguments:
	#   $1 - user query (string)
	#   $2... - tool names (strings)
	# Returns:
	#   planner prompt on stdout; non-zero on failure.
	local user_query tool_lines
	local -a tools=()
	user_query="$1"
	shift
	tools=("$@")

	# Format tool descriptions
	if ((${#tools[@]} > 0)); then
		tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${tools[@]}")" format_tool_line)"
	else
		tool_lines=""
	fi

	# Build the prompt
	build_planner_prompt "${user_query}" "${tool_lines}" ""
}

plan_json_to_outline() {
	# Converts a planner response into a human-readable outline string.
	# Arguments:
	#   $1 - planner response JSON array
	# Returns:
	#   outline string on stdout; non-zero on failure.

	local plan_json plan_clean
	plan_json="${1:-[]}"

	# Normalize the plan JSON
	plan_clean="$(normalize_plan <<<"${plan_json}")" || return 1

	# Convert to outline format
	jq -r 'to_entries | map("\(.key + 1). " + (if (.value.thought // "") != "" then (.value.thought // "") else "Use " + (.value.tool // "unknown") end)) | join("\n")' <<<"${plan_clean}"
}

export -f plan_json_to_outline
export -f build_planner_prompt_with_tools
