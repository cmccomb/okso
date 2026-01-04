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
#   - python 3.8+
#
# Exit codes:
#   Functions return non-zero on invalid input.

PLANNING_NORMALIZATION_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${PLANNING_NORMALIZATION_DIR}/../core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${PLANNING_NORMALIZATION_DIR}/../../tools/registry.sh"

validate_plan_against_schemas() {
        # Validates a normalized plan against registered tool schemas.
        # Arguments:
        #   $1 - normalized planner plan JSON (array)
        #   $2 - JSON object mapping tool names to schemas
        # Returns:
        #   0 when valid, non-zero otherwise.
        local plan_json schema_map
        plan_json="$1"
        schema_map="$2"

        if [[ -z "${schema_map}" ]]; then
                log "WARN" "normalize_plan: tool schema map unavailable" "planner_tool_schemas_missing" >&2
                return 1
        fi

        python "${PLANNING_NORMALIZATION_DIR}/schema_validation.py" --plan-json "${plan_json}" --tool-schemas "${schema_map}"
}

normalize_plan() {
        # Normalize planner output into a clean plan array of objects. Structured
        # generation should already satisfy the schema; this function only enforces the
        # top-level array shape, presence of the primary fields, and per-tool argument
        # schemas.
	# Arguments:
	#   $1 - raw planner output (string; optional; defaults to stdin)
	# Returns:
	#   normalized plan JSON array on stdout; non-zero on failure.
        local raw normalized tool_schemas

	# Prefer an explicit argument when provided; fall back to stdin for callers
	# that stream planner output directly.
	raw="${1:-}"
	if [[ -z "${raw}" ]]; then
		raw="$(cat)"
	fi

	# Validate non-empty input
	if [[ -z "${raw}" ]]; then
		log "WARN" "normalize_plan: received empty planner output" "planner_output_empty" >&2
		return 1
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

        # Build the tool schema map for validation
        tool_schemas="$(tool_schema_map)"
        if ! jq -e 'type == "object"' <<<"${tool_schemas}" >/dev/null 2>&1; then
                log "WARN" "normalize_plan: tool schema map invalid" "planner_tool_schemas_invalid" >&2
                return 1
        fi

        # Validate args against per-tool schemas
        if ! validate_plan_against_schemas "${normalized}" "${tool_schemas}"; then
                log "WARN" "normalize_plan: plan failed per-tool schema validation" "planner_args_validation_failed" >&2
                return 1
        fi

	# Return normalized plan
	printf '%s' "${normalized}"
}

export -f normalize_plan
