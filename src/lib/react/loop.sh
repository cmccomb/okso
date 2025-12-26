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
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - llama.cpp binaries for context arg infill
#
# Exit codes:
#   Functions return non-zero on validation or execution failures.

EXECUTOR_LIB_DIR=${EXECUTOR_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
REACT_LIB_DIR=${REACT_LIB_DIR:-${EXECUTOR_LIB_DIR}}

# shellcheck source=../formatting.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../formatting.sh"
# shellcheck source=../llm/llama_client.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../llm/llama_client.sh"
# shellcheck source=../exec/dispatch.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../exec/dispatch.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/logging.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/state.sh"
# shellcheck source=../tools/query.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../tools/query.sh"
# shellcheck source=../prompt/templates.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../prompt/templates.sh"
# shellcheck source=./schema.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/schema.sh"
# shellcheck source=./history.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/history.sh"

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
	# Applies planner-provided arg control metadata to the executor args using jq only.
	# Arguments:
	#   $1 - tool name
	#   $2 - executor args JSON
	#   $3 - planner plan entry JSON (optional)
	#   $4 - user query text (unused; kept for API stability)
	#   $5 - serialized history text (unused; kept for API stability)
	local tool args_json plan_entry_json user_query history_text args_obj plan_args plan_controls jq_filter
	tool="$1"
	args_json="$2"
	plan_entry_json="$3"
	user_query="$4"
	history_text="$5"

	args_obj="$(jq -ce 'if type=="object" then . else {} end' <<<"${args_json}" 2>/dev/null || printf '{}')"
	plan_args="$(jq -ce '.args // {} | if type=="object" then . else {} end' <<<"${plan_entry_json}" 2>/dev/null || printf '{}')"
	plan_controls="$(jq -ce '.args_control // {} | if type=="object" then . else {} end' <<<"${plan_entry_json}" 2>/dev/null || printf '{}')"

	jq_filter=$(
		cat <<'JQ'
reduce ($controls|to_entries[]) as $item (
  {args:$args,context:[],seeds:{}};
  if $item.value=="locked" then
    if $planned[$item.key]!=null then .args[$item.key]=$planned[$item.key] else . end
  elif $item.value=="context" then
    (if $planned[$item.key]!=null then $planned[$item.key] else .args[$item.key] end) as $seed
    | (if $seed!=null then .args[$item.key]=$seed else (.args|=del(.[$item.key])) end)
    | (if ($seed!=null and ($seed|type)=="string") then .seeds[$item.key]=$seed else . end)
    | (if (.context|index($item.key))==null then .context+=[ $item.key ] else . end)
  else . end
)
| . as $state
| $state.args
| (if ($state.context|length>0) then .+{__context_controlled:$state.context} else . end)
| (if ($state.seeds|length>0) then .+{__context_seeds:$state.seeds} else . end)
JQ
	)

	jq -c -n --argjson args "${args_obj}" --argjson planned "${plan_args}" --argjson controls "${plan_controls}" "${jq_filter}" 2>/dev/null
}

validate_planner_action() {
	# Validates a planner-provided action against allowed tools and schemas.
	# Arguments:
	#   $1 - raw action JSON
	#   $2 - newline-delimited allowed tools
	# Outputs validated JSON to stdout.
	local raw_action allowed_tools err_log action_json tool args_json args_control_json tool_schema
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
	args_control_json="$(jq -c '.args_control // {}' <<<"${action_json}" 2>/dev/null || printf '{}')"
	tool_schema="$(tool_args_schema "${tool}")"
	if [[ -n "${tool_schema}" ]] && ! jq -e --argjson schema "${tool_schema}" '.args|. as $args|$schema as $s|$args|=.' <<<"${action_json}" >/dev/null 2>&1; then
		log "WARN" "Unable to validate args schema; continuing" "${tool}" || true
	fi

	jq -c --argjson args "${args_json}" --argjson args_control "${args_control_json}" \
		'{tool:.tool,args:$args,args_control:$args_control,thought:(.thought//"Planner provided no commentary")}' <<<"${action_json}"
}

validate_required_args_present() {
	# Ensures required args are present, optionally allowing context-controlled gaps.
	# Arguments:
	#   $1 - args JSON
	#   $2 - args schema JSON
	#   $3 - JSON array of context-controlled keys
	#   $4 - allow missing context fields flag (bool; default true)
	local args_json schema_json context_fields_json allow_context_missing
	args_json="$1"
	schema_json="$2"
	context_fields_json="$3"
	allow_context_missing=${4:-true}

	if ! command -v python3 >/dev/null 2>&1; then
		log "WARN" "python3 unavailable; skipping required arg validation" "${schema_json}" || true
		return 0
	fi

	python3 - "${args_json}" "${schema_json}" "${context_fields_json}" "${allow_context_missing}" <<'PY'
import json
import sys

args_raw, schema_raw, context_raw, allow_missing = sys.argv[1:]
try:
    args = json.loads(args_raw or "{}")
except Exception:  # noqa: BLE001
    sys.stderr.write("Args JSON invalid\n")
    sys.exit(1)

schema = json.loads(schema_raw or "{}")
context_fields = json.loads(context_raw or "[]")
allow_context = allow_missing.lower() == "true"
required = [k for k in schema.get("required", []) if isinstance(k, str)]

missing = []
for key in required:
    if key in args:
        continue
    if allow_context and key in context_fields:
        continue
    missing.append(key)

if missing:
    sys.stderr.write(f"Missing required args: {', '.join(sorted(missing))}\n")
    sys.exit(1)
PY
}

fill_missing_args_with_llm() {
	# Fills planner-marked context arguments via a single LLM round-trip when possible.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	#   $3 - user query
	#   $4 - plan outline
	#   $5 - planner thought
	#   $6 - history text
	#   $7 - JSON array of context-controlled fields
	local tool args_json user_query plan_outline planner_thought schema prompt response context_fields_json
	tool="$1"
	args_json="$2"
	user_query="$3"
	plan_outline="$4"
	planner_thought="$5"
	history_text="$6"
	context_fields_json="$7"
	schema="$(tool_args_schema "${tool}")"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "LLM unavailable; context args remain unchanged" "${tool}" || true
		printf '%s' "${args_json}"
		return 0
	fi

	if ! prompt="$(render_prompt_template "executor" \
		tool "${tool}" \
		user_query "${user_query}" \
		plan_outline "${plan_outline}" \
		planner_thought "${planner_thought}" \
		args_json "${args_json}" \
		args_schema "${schema}" \
		context_fields "${context_fields_json}" \
		history_text "${history_text}")"; then
		log "WARN" "Failed to render executor prompt" "${tool}" || true
		printf '%s' "${args_json}"
		return 0
	fi

	log_pretty "INFO" "prompt" "${prompt}"

	response="$(llama_infer "${prompt}" "" 256 "${schema}" "${REACT_MODEL_REPO:-}" "${REACT_MODEL_FILE:-}" "${REACT_CACHE_FILE:-}")"
	if jq -e 'type == "object"' <<<"${response}" >/dev/null 2>&1; then
		jq -c '.' <<<"${response}"
		return 0
	fi

	log "WARN" "LLM returned non-object args; preserving original" "${response}" || true
	printf '%s' "${args_json}"
}

extract_context_controls() {
	# Extracts context metadata and cleaned args from a resolved args JSON blob.
	# Arguments:
	#   $1 - resolved args JSON
	# Returns:
	#   JSON object with keys: args, context_fields, context_seed_lines
	local resolved_json
	resolved_json="$1"

	jq -ce '
                def ensure_array(x): if (x|type) == "array" then x else [] end;
                def ensure_object(x): if (x|type) == "object" then x else {} end;

                {
                        args: (. | del(.__context_controlled) | del(.__context_seeds)),
                        context_fields: ensure_array(.__context_controlled),
                        context_seed_lines: (ensure_object(.__context_seeds) | to_entries | map("\(.key): \(.value)"))
                }
        ' <<<"${resolved_json}"
}

resolve_action_args() {
	# Applies planner controls, validates required args, fills context fields, and normalizes the final JSON.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	#   $3 - planner plan entry JSON
	#   $4 - user query
	#   $5 - serialized history text
	#   $6 - plan outline
	#   $7 - planner thought
	local tool args_json plan_entry_json user_query history_text plan_outline planner_thought
	local resolved_args context_fields_json context_seed_lines history_for_prompt schema
	tool="$1"
	args_json="$2"
	plan_entry_json="$3"
	user_query="$4"
	history_text="$5"
	plan_outline="$6"
	planner_thought="$7"

	resolved_args="$(apply_plan_arg_controls "${tool}" "${args_json}" "${plan_entry_json}" "${user_query}" "${history_text}")"

	if ! context_metadata="$(extract_context_controls "${resolved_args}")"; then
		printf 'Invalid args JSON after planner controls\n' >&2
		return 1
	fi

	context_fields_json="$(jq -c '.context_fields' <<<"${context_metadata}")"
	context_seed_lines="$(jq -r '.context_seed_lines[]?' <<<"${context_metadata}")"
	resolved_args="$(jq -c '.args' <<<"${context_metadata}")"

	schema="$(tool_args_schema "${tool}")"
	if [[ -n "${schema}" ]]; then
		if ! validate_required_args_present "${resolved_args}" "${schema}" "${context_fields_json}" true; then
			return 1
		fi
	fi

	if [[ "${context_fields_json}" == "[]" ]]; then
		normalize_args_json "${resolved_args}"
		return 0
	fi

	history_for_prompt="${history_text}"
	if [[ -n "${context_seed_lines}" ]]; then
		history_for_prompt+=$'\n'
		history_for_prompt+="Context arg seeds:"
		history_for_prompt+=$'\n'
		history_for_prompt+="${context_seed_lines}"
	fi

	resolved_args="$(fill_missing_args_with_llm "${tool}" "${resolved_args}" "${user_query}" "${plan_outline}" "${planner_thought}" "${history_for_prompt}" "${context_fields_json}")"

	if [[ -n "${schema}" ]]; then
		if ! validate_required_args_present "${resolved_args}" "${schema}" "${context_fields_json}" false; then
			return 1
		fi
	fi

	normalize_args_json "${resolved_args}"
}

execute_planned_action() {
	# Executes a validated action with retries for arg infill failures.
	# Arguments:
	#   $1 - state prefix
	#   $2 - step index
	#   $3 - validated action JSON
	local state_prefix step_index action_json tool args_json thought args_after_controls
	local observation context history_text
	state_prefix="$1"
	step_index="$2"
	action_json="$3"

	tool="$(jq -r '.tool' <<<"${action_json}")"
	args_json="$(jq -c '.args' <<<"${action_json}")"
	thought="$(jq -r '.thought' <<<"${action_json}")"

	history_text="$(state_get_history_lines "${state_prefix}")"
	if ! args_after_controls="$(resolve_action_args "${tool}" "${args_json}" "${action_json}" "$(state_get "${state_prefix}" "user_query")" "${history_text}" "$(state_get "${state_prefix}" "plan_outline")" "${thought}")"; then
		log "ERROR" "Argument resolution failed" "${tool}" || true
		return 1
	fi

	context="$(format_action_context "${thought}" "${tool}" "${args_after_controls}")"
	observation="$(execute_tool_with_query "${tool}" "$(extract_tool_query "${tool}" "${args_after_controls}")" "${context}" "${args_after_controls}")"

	record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${args_after_controls}" "${observation}" "${step_index}"

	if [[ "${tool}" == "final_answer" ]]; then
		state_set "${state_prefix}" "final_answer_action" "${observation}"
		state_set "${state_prefix}" "final_answer" "${observation}"
	fi
}

executor_loop() {
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
	state_prefix="executor_state"

	initialize_executor_state "${state_prefix}" "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
	max_steps=${MAX_STEPS:-6}

	if [[ -z "${plan_entries}" ]]; then
		log "ERROR" "No planner actions provided" "${user_query}" >&2
		state_set "${state_prefix}" "final_answer" "Planner did not provide any executable steps."
		finalize_react_result "${state_prefix}"
		return 1
	fi

	step_index=0
	normalize_plan_json() {
		local raw="$1" normalized

		if printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
			printf '%s' "$raw"
			return 0
		fi

		normalized=$(printf '%s' "$raw" | sed 's/\\"/"/g; s/\\\\\\\\/\\\\/g')
		printf '%s' "$normalized" | jq -e . >/dev/null 2>&1 || return 1
		printf '%s' "$normalized"
	}

	plan_json=$(normalize_plan_json "${plan_entries}") || {
		log "ERROR" "Plan JSON invalid/unparseable" "${plan_entries}" >&2
		exit 1
	}

	while IFS= read -r plan_entry || [[ -n "$plan_entry" ]]; do
		((++step_index))
		if ((step_index > max_steps)); then
			log "WARN" "Exceeded max steps" "${max_steps}"
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
	done < <(jq -c '.[]' <<<"$plan_json")

	finalize_executor_result "${state_prefix}"
}

react_loop() {
	# Compatibility shim preserving the legacy ReAct entry point.
	executor_loop "$@"
}

export -f executor_loop
export -f react_loop
export -f apply_plan_arg_controls
export -f validate_planner_action
export -f validate_required_args_present
export -f fill_missing_args_with_llm
export -f execute_planned_action
export -f resolve_action_args
