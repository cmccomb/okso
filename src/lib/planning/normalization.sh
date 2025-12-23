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

parse_planner_payload() {
	local raw pattern allowed_types
	raw="${1:-}"
	pattern="${2:-}"
	allowed_types="${3:-}"

	RAW_INPUT="${raw}" PAYLOAD_REGEX="${pattern}" ALLOWED_TYPES="${allowed_types}" python3 - <<'PYTHON'
import json
import os
import re
import sys
from typing import Any

raw_input = os.environ.get("RAW_INPUT", "")
payload_regex = os.environ.get("PAYLOAD_REGEX", "")
allowed_type_names = [name for name in os.environ.get("ALLOWED_TYPES", "").split(",") if name]

TYPE_MAPPING = {"array": list, "object": dict}


def is_allowed(value: Any) -> bool:
    if not allowed_type_names:
        return True
    return any(isinstance(value, TYPE_MAPPING[name]) for name in allowed_type_names if name in TYPE_MAPPING)


def try_parse(text: str) -> Any | None:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


candidate = try_parse(raw_input)
if candidate is None or not is_allowed(candidate):
    if payload_regex:
        match = re.search(payload_regex, raw_input, flags=re.S)
        if match:
            candidate = try_parse(match.group(0))

if candidate is None or not is_allowed(candidate):
    sys.exit(1)

json.dump(candidate, sys.stdout)
PYTHON
}

# Normalize noisy planner output into a clean PlannerPlan JSON array of objects.
# Reads from stdin, writes clean JSON array to stdout. This sits between the raw
# llama.cpp stream and the scoring/execution layers so downstream components can
# rely on a consistent schema regardless of how the model formats responses.
normalize_planner_plan() {
	local raw plan_candidate normalized

	raw="$(cat)"

	if ! require_python3_available "planner output normalization"; then
		log "ERROR" "normalize_planner_plan: python3 unavailable" "${raw}" >&2
		return 1
	fi

	plan_candidate="$(
		parse_planner_payload "${raw}" "\\[[\\s\\S]*?\\]" "array"
	)" || plan_candidate=""

	if [[ -n "${plan_candidate:-}" ]]; then
		normalized=$(jq -ec '
                        def with_canonical_args($args):
                                if ($args // {}) | type != "object" then
                                        {}
                                elif ($args | has("input")) then
                                        $args
                                elif ($args | has("code")) then
                                        ($args + {input: $args.code} | del(.code))
                                else
                                        $args
                                end;

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
                                map({tool: .tool, args: with_canonical_args(.args), thought: (.thought // "")})
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

normalize_planner_response() {
	# Normalizes any planner output into a canonical object that the
	# scoring and execution layers understand. The helper tolerates both
	# legacy plan arrays and modern objects that may represent either a
	# structured plan or a "quickdraw" direct answer, ensuring downstream
	# tooling always receives the final_answer stub.
	local raw candidate normalized plan_clean
	raw="$(cat)"

	if ! require_python3_available "planner output normalization"; then
		log "ERROR" "normalize_planner_response: python3 unavailable" "${raw}" >&2
		return 1
	fi

	candidate="$(
		parse_planner_payload "${raw}" "\\{[\\s\\S]*\\}|\\[[\\s\\S]*\\]" "object,array"
	)" || candidate=""

	if [[ -z "${candidate:-}" ]]; then
		log "ERROR" "normalize_planner_response: unable to parse planner output" "${raw}" >&2
		return 1
	fi

	normalized=$(jq -ec '
                def clamp_confidence:
                        if . == null then null
                        elif . < 0 then 0
                        elif . > 1 then 1
                        else . end;

                def normalize_plan($plan):
                        ($plan | tostring | fromjson) as $raw_plan
                        | ($raw_plan | tostring | fromjson) // $raw_plan;

                if type == "array" then
                        {mode: "plan", plan: (normalize_plan(.) | . + [{tool:"final_answer",thought:"Summarize the result for the user.",args:{}}]), quickdraw: null}
                elif (type == "object") and (.mode // "") == "quickdraw" then
                        {mode: "quickdraw", plan: [], quickdraw: {
                                final_answer: (.final_answer // .quickdraw.final_answer // ""),
                                rationale: (.rationale // .quickdraw.rationale // ""),
                                confidence: ((.confidence // .quickdraw.confidence // null) | clamp_confidence)
                        }} | select(.quickdraw.final_answer != "" and .quickdraw.rationale != "")
                elif (type == "object") and (.mode // "") == "plan" then
                        {mode: "plan", plan: (normalize_plan(.plan) | . + [{tool:"final_answer",thought:"Summarize the result for the user.",args:{}}]), quickdraw: null}
                else
                        error("unrecognized planner response shape")
                end
                ' <<<"${candidate}" 2>/dev/null || true)

	if [[ -z "${normalized}" ]]; then
		log "ERROR" "normalize_planner_response: unable to parse planner output" "${raw}" >&2
		return 1
	fi

	if jq -e '.mode == "plan"' <<<"${normalized}" >/dev/null 2>&1; then
		plan_clean="$(jq -ce '.plan' <<<"${normalized}" | normalize_planner_plan)" || {
			log "ERROR" "normalize_planner_response: unable to parse planner output" "${raw}" >&2
			return 1
		}

		normalized="$(jq --argjson plan "${plan_clean}" '.plan = $plan' <<<"${normalized}" 2>/dev/null || true)"
	fi

	printf '%s' "${normalized}"
}

extract_plan_array() {
	# Extracts the plan array from a planner response or legacy array.
	# Arguments:
	#   $1 - planner response JSON (object or legacy plan array)
	local payload plan_json
	payload="${1:-[]}"

	if jq -e '.mode == "quickdraw"' <<<"${payload}" >/dev/null 2>&1; then
		return 10
	fi

	if jq -e '.mode == "plan" and (.plan | type == "array")' <<<"${payload}" >/dev/null 2>&1; then
		plan_json="$(jq -c '.plan' <<<"${payload}")"
	elif jq -e 'type == "array"' <<<"${payload}" >/dev/null 2>&1; then
		plan_json="${payload}"
	else
		plan_json="$(printf '%s' "${payload}" | normalize_planner_plan)" || return 1
	fi

	printf '%s' "${plan_json}"
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
export -f normalize_planner_response
export -f extract_plan_array
export -f append_final_answer_step
