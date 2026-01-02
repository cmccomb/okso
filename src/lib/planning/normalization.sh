#!/usr/bin/env bash
# shellcheck shell=bash
#
# Normalization helpers for planner outputs.
#
# Usage:
#   source "${BASH_SOURCE[0]%/normalization.sh}/normalization.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on invalid input.

PLANNING_NORMALIZATION_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_NORMALIZATION_DIR}/../core/logging.sh"

# Normalize planner output into a clean PlannerPlan JSON array of objects. Minimal
# guards remain to weed out empty llama responses while letting schema validation
# occur inside llama.cpp.
normalize_planner_plan() {
	local raw normalized

	raw="$(cat)"

	if [[ -z "${raw}" ]]; then
		log "WARN" "normalize_planner_plan: received empty planner output" "planner_output_empty" >&2
		return 1
	fi

	if ! normalized=$(jq -c '
                        if (type == "array") then
                                map(
                                        . as $step |
                                        {
                                                tool: ($step.tool // ""),
                                                args: (if ($step.args // {} | type == "object") then
                                                                (if ($step.args.code != null) then
                                                                        ($step.args + {input: $step.args.code} | del(.code))
                                                                else
                                                                        ($step.args // {})
                                                                end)
                                                        else
                                                                {}
                                                        end),
                                                thought: ($step.thought // "")
                                        }
                                )
                        else
                                .
                        end
                ' <<<"${raw}" 2>/dev/null); then
		log "WARN" "normalize_planner_plan: failed to parse planner output" "planner_output_parse_failed" >&2
		return 1
	fi

	printf '%s' "${normalized}"
}

# Normalizes any planner output into a canonical object that the scoring and
# execution layers understand.
normalize_planner_response() {
	local raw candidate normalized plan_json plan_clean
	raw="$(cat)"

	if [[ -z "${raw}" ]]; then
		log "WARN" "normalize_planner_response: received empty planner output" "planner_output_empty" >&2
		return 1
	fi

	if ! candidate=$(jq -c '.' <<<"${raw}" 2>/dev/null); then
		log "WARN" "normalize_planner_response: failed to parse llama output" "planner_output_parse_failed" >&2
		return 1
	fi

	if jq -e 'type == "array"' <<<"${candidate}" >/dev/null 2>&1; then
		normalized="$(jq -c '{plan: .}' <<<"${candidate}" 2>/dev/null || printf '{}')"
	else
		normalized="${candidate}"
	fi

	plan_json=$(jq -c '
                        if (.plan | type == "string") then
                                (try (.plan | fromjson) catch [])
                        else
                                (.plan // [])
                        end
                ' <<<"${normalized}" 2>/dev/null || printf '[]')

	plan_clean="$(normalize_planner_plan <<<"${plan_json}")" || {
		log "WARN" "normalize_planner_response: unable to normalize plan array" "${raw}" >&2
		return 1
	}

	jq --argjson plan "${plan_clean}" '.plan = $plan' <<<"${normalized}" 2>/dev/null || printf '%s' "${normalized}"
}

extract_plan_array() {
	# Extracts the plan array from a planner response or legacy array.
	# Arguments:
	#   $1 - planner response JSON (object or legacy plan array)
	local payload plan_json normalized_response
	payload="${1:-[]}"

	if jq -e '.plan | type == "array"' <<<"${payload}" >/dev/null 2>&1; then
		plan_json="$(jq -c '.plan' <<<"${payload}")"
	elif jq -e 'type == "array"' <<<"${payload}" >/dev/null 2>&1; then
		plan_json="${payload}"
	else
		normalized_response="$(normalize_planner_response <<<"${payload}")" || return 1
		plan_json="$(jq -c '.plan' <<<"${normalized_response}")"
	fi

	printf '%s' "${plan_json}"
}

export -f normalize_planner_plan
export -f normalize_planner_response
export -f extract_plan_array
