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
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - llama.cpp binaries for context arg infill
#
# Exit codes:
#   Functions return non-zero on validation or execution failures.

EXECUTOR_LIB_DIR=${EXECUTOR_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=../formatting.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../formatting.sh"
# shellcheck source=../llm/llama_client.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../llm/llama_client.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/logging.sh"
# shellcheck source=../core/json_state.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/json_state.sh"
# shellcheck source=../tools/query.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../tools/query.sh"
# shellcheck source=../prompt/templates.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../prompt/templates.sh"
# shellcheck source=./history.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/history.sh"
# shellcheck source=./dispatch.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/dispatch.sh"

normalize_args_json() {
	# Normalizes argument JSON into canonical form.
	# Arguments:
	#   $1 - args JSON string
	# Returns:
	#   Canonical JSON string with sorted keys.
	local args_json normalized
	args_json="$1"

	# Ensure args_json is at least an empty object
	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi

	# Normalize with sorted keys
	normalized="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"

	# Return normalized JSON
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
	# Pretty-print args JSON if possible
	args_pretty="$(jq -c '.' <<<"${args_json}" 2>/dev/null || printf '%s' "${args_json}")"

	# Return formatted context
	printf 'Thought: %s\nTool: %s\nArgs: %s' "${thought}" "${tool}" "${args_pretty}"
}

apply_plan_arg_controls() {
	# Applies planner-provided arg values and infers context-controlled fields from empty seeds.
	# Arguments:
	#   $1 - tool name
	#   $2 - executor args JSON
	#   $3 - planner plan entry JSON (optional)
	#   $4 - user query text (unused; kept for API stability)
	#   $5 - serialized history text (unused; kept for API stability)
	local tool args_json plan_entry_json user_query history_text args_obj plan_args jq_filter
	tool="$1"
	args_json="$2"
	plan_entry_json="$3"
	user_query="$4"
	history_text="$5"

	# Parse args and plan args as objects, defaulting to empty objects
	args_obj="$(jq -ce 'if type=="object" then . else {} end' <<<"${args_json}" 2>/dev/null || printf '{}')"
	plan_args="$(jq -ce '.args // {} | if type=="object" then . else {} end' <<<"${plan_entry_json}" 2>/dev/null || printf '{}')"

	# Infer context-controlled fields: any field with empty string seed is context-controlled
	jq_filter=$(
		cat <<'JQ'
# Planner provides plan args; executor starts with empty args
# For each planner arg:
#   - If it's an empty string "", mark it as context-controlled (executor fills)
#   - Otherwise use the planner value as-is
$planned as $p
| reduce ($p|to_entries[]) as $item (
    {args:$args, context:[], seeds:{}};
    .args[$item.key] = $item.value
    | if ($item.value == "") then
        (.context += [$item.key])
      else
        (if ($item.value | type) == "string" then .seeds[$item.key] = $item.value else . end)
      end
  )
| . as $state
| $state.args
| (if ($state.context|length>0) then .+{__context_controlled:$state.context} else . end)
| (if ($state.seeds|length>0) then .+{__context_seeds:$state.seeds} else . end)
JQ
	)

	# Apply the jq filter to merge args and mark context-controlled fields
	jq -c -n --argjson args "${args_obj}" --argjson planned "${plan_args}" "${jq_filter}" 2>/dev/null
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

	response="$(llama_infer "${prompt}" "" 256 "${schema}" "${EXECUTOR_MODEL_REPO:-}" "${EXECUTOR_MODEL_FILE:-}")"
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
	# Applies planner controls, fills context fields, and normalizes the final JSON.
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
	if ! args_after_controls="$(resolve_action_args "${tool}" "${args_json}" "${action_json}" "$(json_state_get_key "${state_prefix}" "user_query")" "${history_text}" "$(json_state_get_key "${state_prefix}" "plan_outline")" "${thought}")"; then
		log "ERROR" "Argument resolution failed" "${tool}" || true
		return 1
	fi

	context="$(format_action_context "${thought}" "${tool}" "${args_after_controls}")"
	observation="$(execute_tool_with_query "${tool}" "$(extract_tool_query "${tool}" "${args_after_controls}")" "${context}" "${args_after_controls}")"

	record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${args_after_controls}" "${observation}" "${step_index}"

	if [[ "${tool}" == "final_answer" ]]; then
		json_state_set_key "${state_prefix}" "final_answer_action" "${observation}"
		json_state_set_key "${state_prefix}" "final_answer" "${observation}"
	fi
}

executor_loop() {
	# Executes planner actions deterministically.
	# Arguments:
	#   $1 - user query
	#   $2 - allowed tools (newline delimited)
	#   $3 - planner plan entries as JSON array
	#   $4 - plan outline text
	local user_query allowed_tools plan_entries plan_outline state_prefix plan_entry step_index
	user_query="$1"
	allowed_tools="$2"
	plan_entries="$3"
	plan_outline="$4"
	state_prefix="executor_state"

	initialize_executor_state "${state_prefix}" "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"

	if [[ -z "${plan_entries}" ]]; then
		log "ERROR" "No planner actions provided" "${user_query}" >&2
		json_state_set_key "${state_prefix}" "final_answer" "Planner did not provide any executable steps."
		finalize_executor_result "${state_prefix}"
		return 1
	fi

	step_index=0

	if ! jq -e 'type == "array" and (length > 0)' <<<"${plan_entries}" >/dev/null 2>&1; then
		log "ERROR" "Planner returned no actionable steps" "${plan_entries}" >&2
		json_state_set_key "${state_prefix}" "final_answer" "Planner did not provide any executable steps."
		finalize_executor_result "${state_prefix}"
		return 1
	fi

	while IFS= read -r plan_entry || [[ -n "$plan_entry" ]]; do
		((++step_index))

		execute_planned_action "${state_prefix}" "${step_index}" "${plan_entry}"

		if [[ -n "$(json_state_get_key "${state_prefix}" "final_answer")" ]]; then
			break
		fi
	done < <(jq -c '.[]' <<<"${plan_entries}")

	finalize_executor_result "${state_prefix}"
}

export -f executor_loop
export -f apply_plan_arg_controls
export -f fill_missing_args_with_llm
export -f execute_planned_action
export -f resolve_action_args
