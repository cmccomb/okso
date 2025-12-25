#!/usr/bin/env bash
# shellcheck shell=bash
#
# Deterministic execution loop for planner-driven tool invocations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/loop.sh}/loop.sh"
#
# Environment variables:
#   CANONICAL_TEXT_ARG_KEY (string): key for single-string tool arguments; default: "input".
#   MAX_STEPS (int): maximum number of executor actions; default: 6.
#   MISSING_VALUE_TOKEN (string): sentinel for missing values; default: "__MISSING__".
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - llama.cpp binaries for optional arg infill
#
# Exit codes:
#   Functions return non-zero on validation or execution failures.

REACT_LIB_DIR=${REACT_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
MISSING_VALUE_TOKEN=${MISSING_VALUE_TOKEN:-"__MISSING__"}

# shellcheck source=../formatting.sh disable=SC1091
source "${REACT_LIB_DIR}/../formatting.sh"
# shellcheck source=../llm/llama_client.sh disable=SC1091
source "${REACT_LIB_DIR}/../llm/llama_client.sh"
# shellcheck source=../exec/dispatch.sh disable=SC1091
source "${REACT_LIB_DIR}/../exec/dispatch.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/logging.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/state.sh"
# shellcheck source=./schema.sh disable=SC1091
source "${REACT_LIB_DIR}/schema.sh"
# shellcheck source=./history.sh disable=SC1091
source "${REACT_LIB_DIR}/history.sh"

normalize_args_json() {
	# Normalizes argument JSON into canonical form.
	# Arguments:
	#   $1 - args JSON string
	# Returns:
	#   Canonical JSON string with sorted keys.
	local args_json normalized
	args_json="$1"
	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi
	normalized="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"
	printf '%s' "${normalized}"
}

format_action_context() {
	# Arguments:
	#   $1 - thought text
	#   $2 - tool name
	#   $3 - args JSON
	local thought tool args_json args_pretty
	thought="$1"
	tool="$2"
	args_json="$3"
	args_pretty="$(jq -c '.' <<<"${args_json}" 2>/dev/null || printf '%s' "${args_json}")"
	printf 'Thought: %s\nTool: %s\nArgs: %s' "${thought}" "${tool}" "${args_pretty}"
}

apply_plan_arg_controls() {
	# Applies planner-provided arg control metadata to the executor args.
	# Arguments:
	#   $1 - tool name
	#   $2 - executor args JSON
	#   $3 - planner plan entry JSON (optional)
	#   $4 - user query text
	#   $5 - missing value token
	local tool args_json plan_entry_json user_query missing_token tool_schema
	tool="$1"
	args_json="$2"
	plan_entry_json="$3"
	user_query="$4"
	missing_token="$5"
	tool_schema="$(tool_args_schema "${tool}")"

	if ! command -v python3 >/dev/null 2>&1; then
		log "WARN" "python3 unavailable; skipping arg control application" "${tool}" || true
		printf '%s' "${args_json}"
		return 0
	fi

	python3 - "${args_json}" "${plan_entry_json}" "${user_query}" "${missing_token}" "${tool_schema}" <<'PY'
import json
import sys
from typing import Any


def as_object(payload: str, default: dict[str, Any]) -> dict[str, Any]:
    try:
        value = json.loads(payload)
        if isinstance(value, dict):
            return value
    except Exception:  # noqa: BLE001
        pass
    return default.copy()


args_raw, plan_raw, user_query, missing_token, schema_raw = sys.argv[1:]
args = as_object(args_raw, {})
plan_entry = as_object(plan_raw, {})
planned_args = as_object(json.dumps(plan_entry.get("args", {})), {})
arg_controls = as_object(json.dumps(plan_entry.get("args_control", {})), {})
schema = as_object(schema_raw, {})
properties = schema.get("properties") if isinstance(schema, dict) else {}


def expected_type(key: str) -> str | None:
    if isinstance(properties, dict):
        prop = properties.get(key)
        if isinstance(prop, dict):
            value_type = prop.get("type")
            if isinstance(value_type, str):
                return value_type
    return None


for arg_name, strategy in arg_controls.items():
    if strategy not in {"context", "locked"}:
        continue

    planned_value = planned_args.get(arg_name)

    if strategy == "locked":
        if planned_value is not None and planned_value != missing_token:
            args[arg_name] = planned_value
        continue

    current_value = args.get(arg_name)
    if current_value is not None and current_value != missing_token:
        continue

    candidate: Any | None = None
    value_type = expected_type(arg_name)
    if value_type == "string":
        candidate = user_query
    elif planned_value != missing_token:
        candidate = planned_value

    if candidate is not None:
        args[arg_name] = candidate

print(json.dumps(args, separators=(',', ':')))
PY
}

validate_planner_action() {
	# Validates a planner-provided action against allowed tools and schemas.
	# Arguments:
	#   $1 - raw action JSON
	#   $2 - newline-delimited allowed tools
	# Outputs validated JSON to stdout.
	local raw_action allowed_tools err_log action_json tool args_json tool_schema
	raw_action="$1"
	allowed_tools="$2"
	err_log=$(mktemp)

	if ! action_json=$(jq -ce '.' <<<"${raw_action}" 2>"${err_log}"); then
		printf 'Invalid JSON: %s\n' "$(<"${err_log}")" >&2
		rm -f "${err_log}"
		return 1
	fi
	rm -f "${err_log}"

	tool="$(jq -r '.tool // empty' <<<"${action_json}" 2>/dev/null || printf '')"
	if [[ -z "${tool}" ]]; then
		printf 'Missing tool name\n' >&2
		return 1
	fi

	if [[ -n "${allowed_tools}" ]] && ! grep -Fxq "${tool}" <<<"${allowed_tools}"; then
		printf 'Tool "%s" not permitted\n' "${tool}" >&2
		return 1
	fi

	args_json="$(jq -c '.args // {}' <<<"${action_json}" 2>/dev/null || printf '{}')"
	tool_schema="$(tool_args_schema "${tool}")"
	if [[ -n "${tool_schema}" ]] && ! jq -e --argjson schema "${tool_schema}" '.args|. as $args|$schema as $s|$args|=.' <<<"${action_json}" >/dev/null 2>&1; then
		log "WARN" "Unable to validate args schema; continuing" "${tool}" || true
	fi

	jq -c --argjson args "${args_json}" '{tool:.tool,args:$args,thought:(.thought//"Planner provided no commentary")}' <<<"${action_json}"
}

missing_arg_keys() {
	# Emits names of args containing the missing token.
	# Arguments:
	#   $1 - args JSON
	local args_json
	args_json="$1"
	jq -r --arg missing "${MISSING_VALUE_TOKEN}" 'paths(scalars) as $p | select(getpath($p) == $missing) | ($p|map(tostring)|join("."))' <<<"${args_json}" 2>/dev/null || true
}

fill_missing_args_with_llm() {
	# Fills missing arguments via a single LLM round-trip when possible.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	#   $3 - user query
	#   $4 - plan outline
	#   $5 - planner thought
	local tool args_json user_query plan_outline planner_thought schema prompt response
	tool="$1"
	args_json="$2"
	user_query="$3"
	plan_outline="$4"
	planner_thought="$5"
	schema="$(tool_args_schema "${tool}")"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "LLM unavailable; missing args remain" "${tool}" || true
		printf '%s' "${args_json}"
		return 0
	fi

	prompt=$(
		cat <<'PROMPT'
You are completing missing fields for a tool call.
Return ONLY a JSON object for the tool args with all "__MISSING__" tokens replaced.
PROMPT
	)
	prompt+=$'\nTool: '"${tool}"
	prompt+=$'\nUser request: '"${user_query}"
	if [[ -n "${plan_outline}" ]]; then
		prompt+=$'\nPlan outline: '"${plan_outline}"
	fi
	prompt+=$'\nPlanner notes: '"${planner_thought}"
	prompt+=$'\nCurrent args JSON: '"${args_json}"
	if [[ -n "${schema}" ]]; then
		prompt+=$'\nArgs schema: '"${schema}"
	fi

	response="$(llama_infer "${prompt}" "" 256 "" "${REACT_MODEL_REPO:-}" "${REACT_MODEL_FILE:-}" "${REACT_CACHE_FILE:-}")"
	if jq -e 'type == "object"' <<<"${response}" >/dev/null 2>&1; then
		jq -c '.' <<<"${response}"
		return 0
	fi

	log "WARN" "LLM returned non-object args; preserving original" "${response}" || true
	printf '%s' "${args_json}"
}

execute_planned_action() {
	# Executes a validated action with retries for arg infill failures.
	# Arguments:
	#   $1 - state prefix
	#   $2 - step index
	#   $3 - validated action JSON
	local state_prefix step_index action_json tool args_json thought
	local args_after_controls missing_keys attempt observation context
	state_prefix="$1"
	step_index="$2"
	action_json="$3"

	tool="$(jq -r '.tool' <<<"${action_json}")"
	args_json="$(jq -c '.args' <<<"${action_json}")"
	thought="$(jq -r '.thought' <<<"${action_json}")"

	args_after_controls="$(apply_plan_arg_controls "${tool}" "${args_json}" "${action_json}" "$(state_get "${state_prefix}" "user_query")" "${MISSING_VALUE_TOKEN}")"
	args_after_controls="$(normalize_args_json "${args_after_controls}")"

	for attempt in 1 2; do
		missing_keys="$(missing_arg_keys "${args_after_controls}")"
		if [[ -z "${missing_keys}" ]]; then
			break
		fi
		log "INFO" "Filling missing args" "$(printf 'tool=%s attempt=%s missing=%s' "${tool}" "${attempt}" "${missing_keys}")"
		args_after_controls="$(fill_missing_args_with_llm "${tool}" "${args_after_controls}" "$(state_get "${state_prefix}" "user_query")" "$(state_get "${state_prefix}" "plan_outline")" "${thought}")"
		args_after_controls="$(normalize_args_json "${args_after_controls}")"
	done

	context="$(format_action_context "${thought}" "${tool}" "${args_after_controls}")"
	observation="$(execute_tool_with_query "${tool}" "$(extract_tool_query "${tool}" "${args_after_controls}")" "${context}" "${args_after_controls}")"

	record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${args_after_controls}" "${observation}" "${step_index}"

	if [[ "${tool}" == "final_answer" ]]; then
		state_set "${state_prefix}" "final_answer_action" "${observation}"
		state_set "${state_prefix}" "final_answer" "${observation}"
	fi
}

react_loop() {
	# Executes planner actions deterministically.
	# Arguments:
	#   $1 - user query
	#   $2 - allowed tools (newline delimited)
	#   $3 - planner plan entries (newline-delimited JSON)
	#   $4 - plan outline text
	local user_query allowed_tools plan_entries plan_outline state_prefix max_steps plan_entry step_index validated_action observation
	user_query="$1"
	allowed_tools="$2"
	plan_entries="$3"
	plan_outline="$4"
	state_prefix="react_state"

	initialize_react_state "${state_prefix}" "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
	max_steps=${MAX_STEPS:-6}

	if [[ -z "${plan_entries}" ]]; then
		log "ERROR" "No planner actions provided" "${user_query}" >&2
		state_set "${state_prefix}" "final_answer" "Planner did not provide any executable steps."
		finalize_react_result "${state_prefix}"
		return 1
	fi

	step_index=0
	while IFS= read -r plan_entry && [[ -n "${plan_entry}" ]]; do
		((step_index++))
		if ((step_index > max_steps)); then
			log "WARN" "Exceeded max steps" "${max_steps}" || true
			break
		fi

		if ! validated_action=$(validate_planner_action "${plan_entry}" "${allowed_tools}" 2>&1); then
			log "ERROR" "Planner action invalid" "$(printf 'step=%s error=%s' "${step_index}" "${validated_action}")" >&2
			observation=$(jq -nc --arg error "${validated_action}" '{output:"",error:$error,exit_code:1}')
			record_tool_execution "${state_prefix}" "planner_validation" "Validation failed" "${plan_entry}" "${observation}" "${step_index}"
			state_set "${state_prefix}" "final_answer" "Planner produced an invalid action at step ${step_index}: ${validated_action}"
			break
		fi

		execute_planned_action "${state_prefix}" "${step_index}" "${validated_action}"

		if [[ -n "$(state_get "${state_prefix}" "final_answer")" ]]; then
			break
		fi
	done <<<"${plan_entries}"

	finalize_react_result "${state_prefix}"
}

export -f react_loop
export -f apply_plan_arg_controls
export -f validate_planner_action
export -f fill_missing_args_with_llm
export -f execute_planned_action
