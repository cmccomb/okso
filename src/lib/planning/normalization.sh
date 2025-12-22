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
# shellcheck source=../dependency_guards/dependency_guards.sh disable=SC1091
source "${PLANNING_NORMALIZATION_DIR}/../dependency_guards/dependency_guards.sh"

# Normalize noisy planner output into a clean PlannerPlan JSON array of objects.
# Reads from stdin, writes clean JSON array to stdout.
normalize_planner_plan() {
	local raw plan_candidate normalized

	raw="$(cat)"

	if ! require_python3_available "planner output normalization"; then
		log "ERROR" "normalize_planner_plan: python3 unavailable" "${raw}" >&2
		return 1
	fi

	plan_candidate=$(
		RAW_INPUT="${raw}" python3 - <<'PYTHON'
import json
import os
import re
import sys

raw_input = os.environ.get("RAW_INPUT", "")


def try_parse(text: str) -> list | None:
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, list) else None


candidate = try_parse(raw_input)
if candidate is None:
    match = re.search(r"\[[\s\S]*?\]", raw_input)
    if match:
        candidate = try_parse(match.group(0))

if candidate is None:
    sys.exit(1)

json.dump(candidate, sys.stdout)

PYTHON

	) || plan_candidate=""

	if [[ -n "${plan_candidate:-}" ]]; then
		normalized=$(jq -ec '
                        def valid_step:
                                (.tool | type == "string")
                                and (.tool | length) > 0
                                and ((.args | type == "object") or (.args == null))
                                and ((.thought | type == "string") or (.thought == null));

                        if type != "array" then
                                error("plan must be an array")
                        elif any(.[]; (type != "object") or (valid_step | not)) then
                                error("plan contains invalid steps")
                        else
                                map({tool: .tool, args: (.args // {}), thought: (.thought // "")})
                        end
                        ' <<<"${plan_candidate}" 2>/dev/null || true)
		if [[ -n "${normalized}" && "${normalized}" != "[]" ]]; then
			printf '%s' "${normalized}"
			return 0
		fi
	fi

	log "ERROR" "normalize_planner_plan: unable to parse planner output" "${raw}" >&2
	return 1
}

append_final_answer_step() {
	# Ensures the plan includes a final step with the final_answer tool.
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json plan_clean has_final updated_plan
	plan_json="${1:-[]}"

	plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)" || return 1

	has_final="$(jq -r 'map((.tool // "") | ascii_downcase == "final_answer") | any' <<<"${plan_clean}" 2>/dev/null || echo false)"
	if [[ "${has_final}" == "true" ]]; then
		printf '%s' "${plan_clean}"
		return 0
	fi

	updated_plan="$(jq -c '. + [{tool:"final_answer",thought:"Summarize the result for the user.",args:{}}]' <<<"${plan_clean}" 2>/dev/null || printf '%s' "${plan_json}")"
	printf '%s' "${updated_plan}"
}

export -f normalize_planner_plan
export -f append_final_answer_step
