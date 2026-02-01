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

# shellcheck source=src/lib/llm/schema.sh
source "${PLANNING_PROMPTING_DIR}/../llm/schema.sh"
# shellcheck source=src/lib/cli/output.sh
source "${PLANNING_PROMPTING_DIR}/../cli/output.sh"
# shellcheck source=src/lib/planning/normalization.sh
source "${PLANNING_PROMPTING_DIR}/normalization.sh"
# shellcheck source=src/lib/llm/templates.sh
source "${PLANNING_PROMPTING_DIR}/../llm/templates.sh"

build_planner_prompt() {
	# Builds a prompt for the high-level planner.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted tool descriptions (string)
	#   $3 - pre-computed search context (string)
	#   $4 - optional planner feedback or constraints (string)
	#   $5 - optional planner schema override (string)
	#   $6 - optional intent context (string)
	# Returns:
	#   The full prompt text (string).
	local user_query tool_lines search_context planner_schema current_date current_time current_weekday rendered
	local planner_feedback intent_context

	user_query="$1"
	tool_lines="$2"
	search_context="$3"
	planner_feedback="${4:-}"
	intent_context="${6:-}"

	if [[ -z "${planner_feedback}" ]]; then
		planner_feedback="None provided."
	fi
	if [[ -z "${intent_context}" ]]; then
		intent_context="None provided."
	fi

	# Get current date/time info
	current_date="$(date '+%Y-%m-%d')"
	current_time="$(date '+%H:%M:%S')"
	current_weekday="$(date '+%A')"

	# Load the planner schema, allowing callers to override with a compiled variant
	if [[ -n "${5:-}" ]]; then
		planner_schema="$5"
	else
		planner_schema="$(load_schema_text planner_plan)"
	fi

	# Render the prompt
	rendered="$(render_prompt_template "planner" \
		user_query "${user_query}" \
		tool_lines "${tool_lines}" \
		search_context "${search_context}" \
		planner_schema "${planner_schema}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}" \
		planner_feedback "${planner_feedback}" \
		intent_context "${intent_context}")" || return 1

	# Return the rendered prompt
	printf "%s" "${rendered}"
}

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
	build_planner_prompt "${user_query}" "${tool_lines}" "" "" "" ""
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
export -f build_planner_prompt
