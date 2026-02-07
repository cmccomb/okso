#!/usr/bin/env bash
# shellcheck shell=bash
#
# Post-processing helpers for planner responses.
#
# Usage:
#   source "${BASH_SOURCE[0]%/postprocess.sh}/postprocess.sh"

emit_plan_json() {
	# Converts plan entries into a normalized JSON array.
	# Arguments:
	#   $1 - plan entries string
	# Returns:
	#   normalized plan JSON array (string)
	local plan_entries
	plan_entries="$1"

	printf '%s\n' "${plan_entries}" |
		sed '/^[[:space:]]*$/d' |
		jq -sc 'map(select(type=="object"))'
}

planner_fallback_plan() {
	# Returns a minimal safe plan when planner output is invalid.
	jq -nc '[{
		tool: "final_answer",
		args: {},
		thought: "Respond directly to the user."
	}]'
}

planner_extract_plan_array() {
	# Extracts a plan array from planner output objects or arrays.
	# Arguments:
	#   $1 - planner response payload (string)
	# Returns:
	#   JSON array on stdout.
	local payload extracted
	payload="${1:-[]}"

	if extracted="$(jq -c '
		if type == "array" then .
		elif type == "object" and (.plan | type == "array") then .plan
		elif type == "object" and (.plan | type == "string") then (try (.plan | fromjson) catch null)
		else null
		end
	' <<<"${payload}" 2>/dev/null)" && jq -e 'type == "array"' <<<"${extracted}" >/dev/null 2>&1; then
		printf '%s' "${extracted}"
		return 0
	fi

	planner_fallback_plan
}

derive_allowed_tools_from_plan() {
	# Derives the required tool list from a planner response.
	# Arguments:
	#   $1 - planner response JSON array
	# Returns:
	#   newline-delimited list of required tool names (string)
	local plan_json tool seen
	plan_json="${1:-[]}"

	plan_json="$(planner_extract_plan_array "${plan_json}")"
	plan_json="$(normalize_plan <<<"${plan_json}")" || return 1

	seen=""
	local -a required=()

	while IFS= read -r tool; do
		[[ -z "${tool}" ]] && continue
		if grep -Fxq "${tool}" <<<"${seen}"; then
			continue
		fi
		required+=("${tool}")
		seen+="${tool}"$'\n'
	done < <(jq -r '.[] | .tool // empty' <<<"${plan_json}" 2>/dev/null || true)

	if ! grep -Fxq "final_answer" <<<"${seen}"; then
		required+=("final_answer")
	fi

	printf '%s\n' "${required[@]}"
}

plan_json_to_entries() {
	# Converts planner output into normalized execution entries.
	# Arguments:
	#   $1 - planner response payload (string)
	# Returns:
	#   normalized plan entry array JSON on stdout.
	local plan_json
	plan_json="$1"

	plan_json="$(planner_extract_plan_array "${plan_json}")"
	plan_json="$(normalize_plan <<<"${plan_json}")" || return 1
	printf '%s' "${plan_json}"
}
