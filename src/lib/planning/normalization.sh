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

# Normalize planner output into a clean plan array of objects. Structured
# generation should already satisfy the schema; this function only enforces the
# top-level array shape and presence of the primary fields.
normalize_planner_plan() {
	local raw normalized

	raw="$(cat)"

	if [[ -z "${raw}" ]]; then
		log "WARN" "normalize_planner_plan: received empty planner output" "planner_output_empty" >&2
		return 1
	fi

	if ! normalized=$(jq -c '
if (type == "array") then
map({
tool: (.tool // ""),
args: (if (.args // {} | type == "object") then .args else {} end),
thought: (.thought // "")
})
else
error("planner_output_invalid_shape")
end
' <<<"${raw}" 2>/dev/null); then
		log "WARN" "normalize_planner_plan: failed to parse planner output" "planner_output_parse_failed" >&2
		return 1
	fi

	printf '%s' "${normalized}"
}

# Backwards-compatible alias that preserves the previous entry point name while
# structured generation converges on the top-level array response.
normalize_planner_response() {
	normalize_planner_plan
}

# Extracts and minimally validates a plan array.
# Arguments:
#   $1 - planner response JSON (array)
extract_plan_array() {
	local payload
	payload="${1:-}"

	if [[ -z "${payload}" ]]; then
		log "WARN" "extract_plan_array: received empty planner output" "planner_output_empty" >&2
		return 1
	fi

	normalize_planner_plan <<<"${payload}"
}

export -f normalize_planner_plan
export -f normalize_planner_response
export -f extract_plan_array
