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
normalize_plan() {
	local raw normalized

	raw="$(cat)"

	if [[ -z "${raw}" ]]; then
		log "WARN" "normalize_plan: received empty planner output" "planner_output_empty" >&2
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
		log "WARN" "normalize_plan: failed to parse planner output" "planner_output_parse_failed" >&2
		return 1
	fi

	printf '%s' "${normalized}"
}

# Extracts and minimally validates a plan array.
# Arguments:
#   $1 - planner response JSON (array)
extract_plan_array() {
	local payload
	payload="${1:-}"

	normalize_plan <<<"${payload}"
}

export -f normalize_plan
export -f extract_plan_array
