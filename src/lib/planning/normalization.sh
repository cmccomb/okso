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

PLANNER_PARAMETERLESS_TOOLS=(
	calendar_list
	mail_list_inbox
	mail_list_unread
	notes_list
	react_fallback
	reminders_list
)

parse_planner_payload() {
	local raw allowed_types
	raw="${1:-}"
	allowed_types="${3:-}"

	RAW_INPUT="${raw}" ALLOWED_TYPES="${allowed_types}" python3 - <<'PYTHON'
import json
import os
import sys
from typing import Any

raw_input = os.environ.get("RAW_INPUT", "")
allowed_type_names = [name for name in os.environ.get("ALLOWED_TYPES", "").split(",") if name]

TYPE_MAPPING = {"array": list, "object": dict}


def is_allowed(value: Any) -> bool:
    if not allowed_type_names:
        return True
    return any(isinstance(value, TYPE_MAPPING[name]) for name in allowed_type_names if name in TYPE_MAPPING)


try:
    candidate = json.loads(raw_input)
except json.JSONDecodeError:
    sys.exit(1)

if not is_allowed(candidate):
    sys.exit(1)

json.dump(candidate, sys.stdout)
PYTHON
}

# Normalize noisy planner output into a clean PlannerPlan JSON array of objects.
# Reads from stdin, writes clean JSON array to stdout. This sits between the raw
# llama.cpp stream and the scoring/execution layers so downstream components can
# rely on a consistent schema regardless of how the model formats responses.
normalize_planner_plan() {
	local raw plan_candidate normalized parameterless_json normalized_error_file normalized_error_message

	raw="$(cat)"

	parameterless_json=$(jq -nc --argjson tools "$(printf '%s\n' "${PLANNER_PARAMETERLESS_TOOLS[@]}" | jq -R . | jq -sc '.')" '{tools:$tools}')

	if ! require_python3_available "planner output normalization"; then
		log "ERROR" "normalize_planner_plan: python3 unavailable" "${raw}" >&2
		return 1
	fi

	if ! plan_candidate="$(
		parse_planner_payload "${raw}" "" "array"
	)"; then
		log "ERROR" "normalize_planner_plan: expected planner output to be a JSON array" "${raw}" >&2
		return 1
	fi

	normalized_error_file="$(mktemp)"
	normalized=$(jq -ec --argjson parameterless "${parameterless_json}" '
                        def canonical_args($args):
                                if ($args | type) != "object" then
                                        error("args must be an object")
                                elif ($args | has("input")) then
                                        $args
                                elif ($args | has("code")) then
                                        ($args + {input: $args.code} | del(.code))
                                else
                                        $args
                                end;

                        def canonical_controls($controls):
                                if ($controls | type) != "object" then
                                        {}
                                else
                                        $controls
                                        | to_entries
                                        | map(select(.value == "context" or .value == "locked"))
                                        | from_entries
                                end;

                        def thought_valid($thought):
                                ($thought | type == "string") and ($thought | length) > 0;

                        def requires_args($tool):
                                ($parameterless.tools | index($tool)) == null;

                        def args_match_controls($args; $controls):
                                ($controls // {}) as $controls_safe
                                | ($controls_safe | keys | sort) as $control_keys
                                | ($args | keys | sort) as $arg_keys
                                | $control_keys == $arg_keys;

                        if type != "array" then
                                error("plan must be an array")
                        elif length == 0 then
                                error("plan must contain at least one step")
                        elif any(.[]; (type != "object")
                                or (["tool", "args", "thought"] - (keys) | length > 0)
                                or (.tool | type != "string")
                                or (.args | type != "object")
                                or (thought_valid(.thought) | not)
                                or ((.args_control | type) as $t | ($t != "object" and $t != "null"))) then
                                error("plan contains invalid steps")
                        else
                                map({
                                        tool: .tool,
                                        args: canonical_args(.args),
                                        args_control: canonical_controls(.args_control),
                                        thought: .thought
                                })
                                | (if any(.[]; (requires_args(.tool)) and ((.args | length) == 0)) then
                                        error("steps missing required args")
                                   else . end)
                                | (if any(.[]; (.args_control // {} | length) > 0 and (args_match_controls(.args; .args_control) | not)) then
                                        error("args_control must mirror args keys")
                                   else . end)
                        end
                        ' <<<"${plan_candidate}" 2>"${normalized_error_file}" || true)
	normalized_error_message="$(<"${normalized_error_file}" 2>/dev/null || printf '')"
	rm -f "${normalized_error_file}" 2>/dev/null || true

	if [[ -n "${normalized}" && "${normalized}" != "[]" ]]; then
		printf '%s' "${normalized}"
		return 0
	fi

	if [[ -z "${normalized_error_message}" ]]; then
		normalized_error_message="planner output must be a non-empty JSON array of steps"
	fi

	log "ERROR" "normalize_planner_plan: ${normalized_error_message}" "${raw}" >&2
	return 1
}

normalize_planner_response() {
	# Normalizes any planner output into a canonical object that the
	# scoring and execution layers understand. The helper expects either a
	# bare plan array or a canonical object containing the plan array and
	# rejects log-wrapped or legacy mode-prefixed payloads.
	local raw candidate normalized plan_clean normalized_error_file normalized_error_message
	raw="$(cat)"

	if ! require_python3_available "planner output normalization"; then
		log "ERROR" "normalize_planner_response: python3 unavailable" "${raw}" >&2
		return 1
	fi

	if ! candidate="$(
		parse_planner_payload "${raw}" "" "object,array"
	)"; then
		log "ERROR" "normalize_planner_response: expected a bare JSON array or object with a plan array" "${raw}" >&2
		return 1
	fi

	if jq -e 'type == "object" and (.mode != null)' <<<"${candidate}" >/dev/null 2>&1; then
		log "ERROR" "normalize_planner_response: planner payload must omit legacy mode wrappers" "${raw}" >&2
		return 1
	fi

	if ! jq -e 'type == "array" or (type == "object" and (.plan | (type == "array" or type == "string")))' <<<"${candidate}" >/dev/null 2>&1; then
		log "ERROR" "normalize_planner_response: planner payload must include a plan array" "${raw}" >&2
		return 1
	fi

	normalized_error_file="$(mktemp)"
	normalized=$(jq -ec '
  def normalize_plan($plan):
    if ($plan | type) == "string" then
      ($plan | fromjson)
    else
      $plan
    end;

  if (type == "array") then
    {plan: (normalize_plan(.))}
  elif (type == "object") then
    if (.mode != null) then
      error("planner payload must omit legacy mode wrappers")
    elif (.plan | (type == "array" or type == "string")) then
      {plan: (normalize_plan(.plan))}
    else
      error("planner payload must include a plan array")
    end
  else
    error("planner payload must be a plan array or object containing one")
  end
' <<<"${candidate}" 2>"${normalized_error_file}" || true)

	normalized_error_message="$(<"${normalized_error_file}" 2>/dev/null || printf '')"
	rm -f "${normalized_error_file}" 2>/dev/null || true

	if [[ -z "${normalized}" ]]; then
		if [[ -z "${normalized_error_message}" ]]; then
			normalized_error_message="planner payload did not match expected schema"
		fi
		log "ERROR" "normalize_planner_response: ${normalized_error_message}" "${raw}" >&2
		return 1
	fi

	plan_clean="$(jq -ce '.plan' <<<"${normalized}" | normalize_planner_plan)" || {
		log "ERROR" "normalize_planner_response: unable to parse plan array" "${raw}" >&2
		return 1
	}

	plan_clean="$(append_final_answer_step "${plan_clean}")" || {
		log "ERROR" "normalize_planner_response: unable to ensure final_answer step" "${raw}" >&2
		return 1
	}

	normalized="$(jq --argjson plan "${plan_clean}" '.plan = $plan' <<<"${normalized}" 2>/dev/null || true)"

	printf '%s' "${normalized}"
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

	updated_plan="$(jq -c '. + [{tool:"final_answer",thought:"Summarize the result for the user.",args:{input:"Summarize the result."}}]' <<<"${plan_clean}" 2>/dev/null || printf '%s' "${plan_json}")"
	printf '%s' "${updated_plan}"
}

export -f normalize_planner_plan
export -f normalize_planner_response
export -f extract_plan_array
export -f append_final_answer_step
