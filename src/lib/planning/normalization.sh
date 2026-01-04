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

# shellcheck source=src/lib/core/logging.sh
source "${PLANNING_NORMALIZATION_DIR}/../core/logging.sh"

normalize_plan() {
	# Normalize planner output into a clean plan array of objects. Structured
	# generation should already satisfy the schema; this function only enforces the
	# top-level array shape and presence of the primary fields.
	# Arguments:
	#   $1 - raw planner output (string; optional; defaults to stdin)
	# Returns:
	#   normalized plan JSON array on stdout; non-zero on failure.
	local raw normalized

	# Prefer an explicit argument when provided; fall back to stdin for callers
	# that stream planner output directly.
	raw="${1:-}"
	if [[ -z "${raw}" ]]; then
		raw="$(cat)"
	fi

	# Normalize and validate shape
	if ! normalized=$(jq -c '
if (type == "array") then
map({
tool: (if (.tool // null | type) == "string" then .tool else error("planner_tool_missing") end),
args: (if (.args | type) == "object" then .args else error("planner_args_invalid_type") end),
thought: (if (.thought // null | type) == "string" then .thought else error("planner_thought_missing") end)
})
else
error("planner_output_invalid_shape")
end
' <<<"${raw}" 2>/dev/null); then
		log "WARN" "normalize_plan: failed to parse planner output" "planner_output_parse_failed" >&2
		return 1
	fi

	# Return normalized plan
	printf '%s' "${normalized}"
}

export -f normalize_plan
