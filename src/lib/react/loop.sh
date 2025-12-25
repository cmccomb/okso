#!/usr/bin/env bash
# shellcheck shell=bash
#
# Execution loop for ReAct planning.
#
# Usage:
#   source "${BASH_SOURCE[0]%/loop.sh}/loop.sh"
#
# Environment variables:
#   CANONICAL_TEXT_ARG_KEY (string): key for single-string tool arguments; default: "input".
#   REACT_RETRY_BUFFER (int): extra attempts beyond plan length; default: 2.
#   REACT_REPLAN_FAILURE_THRESHOLD (int): number of failures between replans; default: 2.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on invalid actions or tool execution failures.

REACT_LIB_DIR=${REACT_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
REACT_REPLAN_TOOL="${REACT_REPLAN_TOOL:-react_replan}"

# shellcheck source=../formatting.sh disable=SC1091
source "${REACT_LIB_DIR}/../formatting.sh"
# shellcheck source=../prompt/build_react.sh disable=SC1091
source "${REACT_LIB_DIR}/../prompt/build_react.sh"
# shellcheck source=../llm/llama_client.sh disable=SC1091
source "${REACT_LIB_DIR}/../llm/llama_client.sh"
# shellcheck source=../exec/dispatch.sh disable=SC1091
source "${REACT_LIB_DIR}/../exec/dispatch.sh"
# shellcheck source=./observation_summary.sh disable=SC1091
source "${REACT_LIB_DIR}/observation_summary.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/logging.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/state.sh"
# shellcheck source=./schema.sh disable=SC1091
source "${REACT_LIB_DIR}/schema.sh"
# shellcheck source=./history.sh disable=SC1091
source "${REACT_LIB_DIR}/history.sh"
# shellcheck source=../llm/context_budget.sh disable=SC1091
source "${REACT_LIB_DIR}/../llm/context_budget.sh"

extract_tool_query() {
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	# Returns a human-readable summary derived from structured args.
	local tool args_json text_key
	tool="$1"
	args_json="$2"
	text_key="${CANONICAL_TEXT_ARG_KEY:-input}"
	case "${tool}" in
	terminal)
		jq -r '(.command // "") as $cmd | ($cmd + " " + ((.args // []) | map(tostring) | join(" ")))|rtrimstr(" ")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	notes_create | notes_append)
		jq -r '[(.title // ""), (.body // "")] | map(select(length>0)) | join("\n")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	reminders_create)
		jq -r '[(.title // ""), (.time // ""), (.notes // "")] | map(select(length>0)) | join("\n")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	notes_read | reminders_complete)
		jq -r '(.title // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	calendar_create)
		jq -r '[(.title // ""), (.start_time // ""), (.location // "")] | map(select(length>0)) | join("\n")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	python_repl)
		jq -r '(.code // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	notes_search | calendar_search | mail_search)
		jq -r --arg key "${text_key}" '.[$key] // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	web_search)
		jq -r '.query // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	mail_draft | mail_send)
		jq -r '(.envelope // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	final_answer)
		jq -r --arg key "${text_key}" '.[$key] // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	notes_list | reminders_list | calendar_list | mail_list_inbox | mail_list_unread)
		printf ''
		;;
	*)
		jq -r --arg key "${text_key}" '.[$key] // .query // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	esac
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
	if ! normalized="$(jq -cS '.' <<<"${args_json}" 2>/dev/null)"; then
		normalized="{}"
	fi
	printf '%s' "${normalized}"
}

planned_step_required_args() {
	# Arguments:
	#   $1 - plan entry JSON (string)
	printf '{}'
}

planned_step_optional_args() {
	# Arguments:
	#   $1 - plan entry JSON (string)
	printf '{}'
}

planned_step_effective_args() {
	# Extracts args from a planned step.
	# Arguments:
	#   $1 - plan entry JSON (string)
	local plan_entry
	plan_entry="$1"
	jq -c '(.args // {})' <<<"${plan_entry}" 2>/dev/null || printf '{}'
}

build_executor_action_schema() {
	# Builds a JSON schema for executor mode, constraining args to planner guidance.
	# Arguments:
	#   $1 - planner args JSON (string)
	local planner_args_json
	planner_args_json="$1"

	if ! require_python3_available "Executor schema generation"; then
		log "ERROR" "Unable to build executor action schema; python3 missing" "${planner_args_json}" >&2
		return 1
	fi

	python3 - "${planner_args_json}" <<'PY'
import json
import sys
import tempfile

planner_args = json.loads(sys.argv[1] or "{}")

def build_properties(source):
    properties = {}
    for key, value in source.items():
        properties[key] = {"const": value, "description": "Required by the planner"}
    return properties

required_properties = build_properties(planner_args)

schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "ReactExecutorArgs",
    "description": "Args-only response for executing a planned tool call.",
    "type": "object",
    "additionalProperties": False,
    "required": ["args"],
    "properties": {
        "thought": {
            "type": "string",
            "description": "Brief execution reasoning (one sentence).",
        },
        "args": {
            "type": "object",
            "additionalProperties": True,
            "required": list(planner_args.keys()),
            "properties": required_properties,
        },
    },
}

tmp = tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".executor.schema.json", encoding="utf-8")
json.dump(schema, tmp)
tmp.close()
print(tmp.name)
PY
}

validate_executor_action() {
	# Validates llama executor output against planner-required args.
	# Arguments:
	#   $1 - raw action JSON
	#   $2 - planner args JSON (string)
	local raw_action planner_args_json action_json args_json required_key expected_value
	raw_action="$1"
	planner_args_json="$2"

	if ! action_json=$(jq -ce '.' <<<"${raw_action}" 2>/dev/null); then
		printf 'Invalid executor JSON' >&2
		return 1
	fi

	if ! jq -e '.args | type == "object"' <<<"${action_json}" >/dev/null 2>&1; then
		printf 'args must be an object' >&2
		return 1
	fi

	args_json="$(jq -c '.args' <<<"${action_json}")"

	while IFS= read -r required_key; do
		expected_value=$(jq -c --arg key "${required_key}" '.[$key]' <<<"${planner_args_json}")
		if ! jq -e --arg key "${required_key}" 'has($key)' <<<"${args_json}" >/dev/null; then
			printf 'Missing required arg: %s' "${required_key}" >&2
			return 1
		fi
		if ! jq -e --arg key "${required_key}" --argjson expected "${expected_value}" '.[$key] == $expected' <<<"${args_json}" >/dev/null 2>&1; then
			printf 'Required arg mismatch: %s' "${required_key}" >&2
			return 1
		fi
	done < <(jq -r 'keys[]?' <<<"${planner_args_json}")

	printf '%s' "${action_json}"
}

normalize_action() {
	# Builds a normalized action object for comparison and storage.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	# Returns:
	#   Canonical action JSON string.
	local tool args_json normalized_args
	tool="$1"
	args_json="$2"
	normalized_args="$(normalize_args_json "${args_json}")"
	jq -ncS --arg tool "${tool}" --argjson args "${normalized_args}" '{tool:$tool,args:$args}'
}

_select_action_from_llama() {
	# Selects an action via llama.cpp, validates it, and writes into the provided variable name.
	# Arguments:
	#   $1 - state prefix
	#   $2 - output variable name for validated JSON
	local state_name output_name allowed_tools react_schema_path react_schema_text react_prompt raw_action validated_action validation_error_file validation_error
	local history plan_step_guidance plan_index planned_entry tool planned_thought planned_args_json planned_required_args planned_optional_args invoke_llama allowed_tool_lines allowed_tool_descriptions summarized_history
	state_name="$1"
	output_name="$2"

	plan_index="$(state_get "${state_name}" "plan_index")"
	plan_index=${plan_index:-0}
	planned_entry=$(printf '%s\n' "$(state_get "${state_name}" "plan_entries")" | sed -n "$((plan_index + 1))p")
	tool=""
	planned_thought="Following planned step"
	planned_args_json="{}"
	planned_required_args="{}"
	planned_optional_args="{}"
	plan_step_guidance="Planner provided no additional steps; choose the best next action."
	if [[ -n "${planned_entry}" ]]; then
		tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
		planned_thought="$(printf '%s' "${planned_entry}" | jq -r '.thought // "Following planned step"' 2>/dev/null || printf '')"
		planned_required_args="$(planned_step_required_args "${planned_entry}")"
		planned_optional_args="$(planned_step_optional_args "${planned_entry}")"
		planned_args_json="$(planned_step_effective_args "${planned_entry}")"
		plan_step_guidance="$(
			jq -rn \
				--arg step "$((plan_index + 1))" \
				--arg tool "${tool:-}" \
				--arg thought "${planned_thought}" \
				--argjson required "${planned_required_args}" \
				--argjson optional "${planned_optional_args}" \
				'"Step \($step) suggested by the planner:\n- tool: \($tool // "(unspecified)")\n- thought: \($thought // "")\n- required_args (do not change): \($required|@json)\n- optional_args (you may refine or fill): \($optional|@json)"'
		)"
	fi

	local rejection_hint
	rejection_hint="$(state_get "${state_name}" "action_rejection_hint")"
	if [[ -n "${rejection_hint}" ]]; then
		plan_step_guidance+=$'\n\nDuplicate action was rejected previously. Please propose a different tool or new arguments.\n'
		plan_step_guidance+="Reason: ${rejection_hint}"
		state_set "${state_name}" "action_rejection_hint" ""
	fi

	invoke_llama=false
	if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
		invoke_llama=true
	fi
	if [[ "${tool}" == "react_fallback" && "${LLAMA_AVAILABLE}" == true ]]; then
		invoke_llama=true
	fi

	allowed_tools="$(state_get "${state_name}" "allowed_tools")"

	if [[ -z "${allowed_tools}" ]]; then
		allowed_tools="$(printf '%s\n%s\n%s' "${tool}" "${REACT_REPLAN_TOOL}" "final_answer")"
	fi

	if [[ "${tool}" == "react_fallback" ]]; then
		allowed_tools="$(tool_names)"
	fi

	if [[ -n "${allowed_tools}" ]] && ! grep -Fxq "final_answer" <<<"${allowed_tools}"; then
		allowed_tools+=$'\nfinal_answer'
	fi

	if [[ -n "${allowed_tools}" ]] && ! grep -Fxq "${REACT_REPLAN_TOOL}" <<<"${allowed_tools}"; then
		allowed_tools+=$'\n'"${REACT_REPLAN_TOOL}"
	fi

	allowed_tools="$(printf '%s\n' "${allowed_tools}" | sed '/^react_fallback$/d' | awk '!seen[$0]++')"

	if [[ -z "${plan_step_guidance}" ]]; then
		plan_step_guidance="Planner provided no additional steps; choose the best next action."
	fi

	if [[ "${invoke_llama}" == true && -n "${planned_entry}" ]]; then
		local executor_schema_path executor_schema_text executor_prompt raw_executor_action executor_validation_file merged_args executor_action_json executor_thought
		executor_schema_path="$(build_executor_action_schema "${planned_args_json}")" || return 1
		executor_schema_text="$(cat "${executor_schema_path}")" || return 1
		history="$(format_tool_history "$(state_get_history_lines "${state_name}")")"

		executor_prompt="$(
			cat <<'EOF'
You are executing the next step of a plan. Do not choose a tool; the planner already selected it.
Provide only the arguments needed for this tool and a minimal thought (one sentence).
Use JSON only in the response.
EOF
		)"
		executor_prompt+=$'\nUser request:\n'
		executor_prompt+="$(state_get "${state_name}" "user_query")"
		executor_prompt+=$'\n\nPlan guidance:\n'
		executor_prompt+="${plan_step_guidance}"
		executor_prompt+=$'\n\nRecent history:\n'
		executor_prompt+="${history}"$'\n'
		executor_prompt+=$'\nRespond strictly with JSON of the form:\n'
		executor_prompt+=$'{"thought":"short reasoning","args":{"<arguments>"}}\n'

		executor_validation_file="$(mktemp)"
		raw_executor_action="$(LLAMA_TEMPERATURE=0 llama_infer "${executor_prompt}" "" 128 "${executor_schema_text}" "${REACT_MODEL_REPO:-}" "${REACT_MODEL_FILE:-}" "${REACT_CACHE_FILE:-}" "${executor_prompt}")"
		log_pretty "INFO" "Executor action received" "${raw_executor_action}"

		if ! executor_action_json=$(validate_executor_action "${raw_executor_action}" "${planned_args_json}" 2>"${executor_validation_file}"); then
			validation_error="$(cat "${executor_validation_file}")"
			record_history "${state_name}" "$(printf 'Invalid executor action from model: %s' "${validation_error}")"
			log "WARN" "Invalid executor output from llama" "${validation_error}"
			rm -f "${executor_validation_file}" "${executor_schema_path}"
		else
			executor_thought="$(jq -r '.thought // empty' <<<"${executor_action_json}" 2>/dev/null || printf '')"
			if [[ -z "${executor_thought}" ]]; then
				executor_thought="${planned_thought}"
			fi
			merged_args=$(jq -nc --argjson planner_args "${planned_args_json}" --argjson model_args "$(jq -c '.args // {}' <<<"${executor_action_json}" 2>/dev/null || printf '{}')" '($planner_args // {}) + ($model_args // {})')
			validated_action="$(jq -nc --arg thought "${executor_thought}" --arg tool "${tool}" --argjson args "${merged_args}" '{thought:$thought,tool:$tool,args:$args}')"
			rm -f "${executor_validation_file}" "${executor_schema_path}"
			printf -v "${output_name}" '%s' "${validated_action}" || return 1
			return 0
		fi
	fi

	if [[ "${invoke_llama}" != true ]]; then
		return 1
	fi

	allowed_tool_lines="$(format_tool_descriptions "${allowed_tools}" format_tool_example_line)"
	if grep -Fxq "${REACT_REPLAN_TOOL}" <<<"${allowed_tools}"; then
		allowed_tool_lines+=$'\n- '"${REACT_REPLAN_TOOL}"$': Request replanning or a revised approach when the current plan no longer fits.'
	fi
	allowed_tool_descriptions="Available tools:"
	if [[ -n "${allowed_tool_lines}" ]]; then
		allowed_tool_descriptions+=$'\n'"${allowed_tool_lines}"
	fi

	react_schema_path="$(build_react_action_schema "${allowed_tools}")" || return 1
	react_schema_text="$(cat "${react_schema_path}")" || return 1
	history="$(format_tool_history "$(state_get_history_lines "${state_name}")")"

	react_prompt_prefix="$(build_react_prompt_static_prefix)" || return 1
	react_prompt_suffix="$(
		build_react_prompt_dynamic_suffix \
			"$(state_get "${state_name}" "user_query")" \
			"${allowed_tool_descriptions}" \
			"$(state_get "${state_name}" "plan_outline")" \
			"${history}" \
			"${react_schema_text}" \
			"${plan_step_guidance}"
	)"
	react_prompt="${react_prompt_prefix}${react_prompt_suffix}"
	summarized_history="$(apply_prompt_context_budget "${react_prompt}" "${history}" 256 "react_history")"
	if [[ "${summarized_history}" != "${history}" ]]; then
		history="${summarized_history}"
		react_prompt_suffix="$(
			build_react_prompt_dynamic_suffix \
				"$(state_get "${state_name}" "user_query")" \
				"${allowed_tool_descriptions}" \
				"$(state_get "${state_name}" "plan_outline")" \
				"${history}" \
				"${react_schema_text}" \
				"${plan_step_guidance}"
		)"
		react_prompt="${react_prompt_prefix}${react_prompt_suffix}"
	fi
	validation_error_file="$(mktemp)"

	raw_action="$(llama_infer "${react_prompt}" "" 256 "${react_schema_text}" "${REACT_MODEL_REPO:-}" "${REACT_MODEL_FILE:-}" "${REACT_CACHE_FILE:-}" "${react_prompt_prefix}")"
	log_pretty "INFO" "Action received" "${raw_action}"

	if ! validated_action=$(validate_react_action "${raw_action}" "${react_schema_path}" 2>"${validation_error_file}"); then
		validation_error="$(cat "${validation_error_file}")"
		record_history "${state_name}" "$(printf 'Invalid action from model: %s' "${validation_error}")"
		log "WARN" "Invalid action output from llama" "${validation_error}"
		rm -f "${validation_error_file}"
		rm -f "${react_schema_path}"
		return 1
	fi

	rm -f "${validation_error_file}"
	rm -f "${react_schema_path}"

	if [[ -n "${planned_entry}" ]]; then
		local planner_args merged_args
		planner_args="$(planned_step_effective_args "${planned_entry}")"
		merged_args=$(jq -nc --argjson planner_args "${planner_args}" --argjson model_args "$(printf '%s' "${validated_action}" | jq -c '.args // {}' 2>/dev/null || printf '{}')" '($planner_args // {}) + ($model_args // {})')
		validated_action="$(jq -c --argjson args "${merged_args}" '.args = $args' <<<"${validated_action}" 2>/dev/null || printf '%s' "${validated_action}")"
	fi

	printf -v "${output_name}" '%s' "${validated_action}"
	return 0
}

select_next_action() {
	# Chooses the next action either from the plan or LLM.
	# Arguments:
	#   $1 - state prefix
	#   $2 - (optional) name of variable to receive JSON action output
	local state_name output_name react_fallback_action react_action_json plan_index planned_entry planned_thought planned_args_json
	state_name="$1"
	output_name="${2:-}"

	planned_args_json="{}"

	plan_index="$(state_get "${state_name}" "plan_index")"
	plan_index=${plan_index:-0}
	planned_entry=$(printf '%s\n' "$(state_get "${state_name}" "plan_entries")" | sed -n "$((plan_index + 1))p")

	if [[ -n "${planned_entry}" ]]; then
		planned_args_json="$(planned_step_effective_args "${planned_entry}")"
		local pending_index_json pending_index_current preserved_reason
		pending_index_json=$(jq -nc --arg plan_index "${plan_index}" '($plan_index | select(length>0) | tonumber?) // null')
		pending_index_current="$(state_get "${state_name}" "pending_plan_step")"
		preserved_reason=""
		if [[ -n "${pending_index_current}" && "${pending_index_current}" -eq "${plan_index}" ]]; then
			preserved_reason="$(state_get "${state_name}" "plan_skip_reason")"
		fi
		state_set_json_document "${state_name}" "$(state_get_json_document "${state_name}" | jq -c --argjson pending_plan_step "${pending_index_json}" --arg preserved_reason "${preserved_reason}" '.pending_plan_step = $pending_plan_step | .plan_skip_reason = $preserved_reason')"
	else
		state_set_json_document "${state_name}" "$(state_get_json_document "${state_name}" | jq -c '.pending_plan_step = null | .plan_skip_reason = ""')"
	fi

	if [[ -n "${planned_entry}" ]]; then
		react_fallback_action=$(jq -nc --arg thought "$(printf '%s' "${planned_entry}" | jq -r '.thought // "Following planned step"' 2>/dev/null || printf '')" --arg tool "$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')" --argjson args "${planned_args_json}" '{thought:$thought,tool:$tool,args:$args}')
	else
		react_fallback_action=""
	fi

	if ! _select_action_from_llama "${state_name}" react_action_json; then
		if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
			return 1
		fi
		if [[ -z "${react_fallback_action}" ]]; then
			return 1
		fi
		react_action_json="${react_fallback_action}"
	fi

	if [[ -n "${output_name}" ]]; then
		printf -v "${output_name}" '%s' "${react_action_json}"
	else
		printf '%s' "${react_action_json}"
	fi
}

record_plan_skip_reason() {
	# Records a skip reason for the current pending plan step and advances the index.
	# Arguments:
	#   $1 - state prefix
	#   $2 - skip reason (string)
	local state_name reason pending_plan_step updated_document
	state_name="$1"
	reason="$2"
	pending_plan_step="$(state_get "${state_name}" "pending_plan_step")"

	if [[ -z "${pending_plan_step}" ]]; then
		pending_plan_step="$(state_get "${state_name}" "plan_index")"
	fi

	if [[ -z "${pending_plan_step}" ]]; then
		return 0
	fi

	if ! updated_document="$(
		state_get_json_document "${state_name}" |
			jq -c --arg reason "${reason}" '
                                .plan_skip_reason = $reason
                                | .plan_index = ((try (.plan_index|tonumber) catch 0) + 1)
                                | .pending_plan_step = null
                        '
	)"; then
		return 1
	fi
	state_set_json_document "${state_name}" "${updated_document}"
}

record_plan_skip_without_progress() {
	# Logs and records a skip reason without advancing the plan index.
	# Arguments:
	#   $1 - state prefix
	#   $2 - skip reason (string)
	local state_name reason pending_plan_step current_plan_index updated_document existing_reason recorded_reason
	state_name="$1"
	reason="$2"
	pending_plan_step="$(state_get "${state_name}" "pending_plan_step")"
	current_plan_index="$(state_get "${state_name}" "plan_index")"
	existing_reason="$(state_get "${state_name}" "plan_skip_reason")"
	recorded_reason="${reason}"

	if [[ -n "${existing_reason}" ]]; then
		recorded_reason="${existing_reason}"
	fi
	log "INFO" "Plan step skipped without advancement" "$(
		printf 'reason=%s plan_index=%s pending_plan_step=%s' \
			"${recorded_reason}" \
			"${current_plan_index:-0}" \
			"${pending_plan_step:-}"
	)"

	if ! updated_document="$(
		state_get_json_document "${state_name}" |
			jq -c --arg reason "${recorded_reason}" '.plan_skip_reason = $reason'
	)"; then
		return 1
	fi
	state_set_json_document "${state_name}" "${updated_document}"
}

complete_pending_plan_step() {
	# Marks the pending plan step as completed after a successful tool run.
	# Arguments:
	#   $1 - state prefix
	local state_name pending_plan_step updated_document
	state_name="$1"
	pending_plan_step="$(state_get "${state_name}" "pending_plan_step")"

	if [[ -z "${pending_plan_step}" ]]; then
		return 0
	fi

	if ! updated_document="$(
		state_get_json_document "${state_name}" |
			jq -c '
                                .plan_index = ((try (.plan_index|tonumber) catch 0) + 1)
                                | .pending_plan_step = null
                                | .plan_skip_reason = ""
                        '
	)"; then
		return 1
	fi
	state_set_json_document "${state_name}" "${updated_document}"
}

validate_tool_permission() {
	# Confirms that the provided tool is permitted for the current run.
	# Arguments:
	#   $1 - state prefix
	#   $2 - tool name to validate
	local state_name tool
	state_name="$1"
	tool="$2"
	if grep -Fxq "${tool}" <<<"$(state_get "${state_name}" "allowed_tools")"; then
		return 0
	fi

	record_history "${state_name}" "$(printf 'Tool %s not permitted.' "${tool}")"
	return 1
}

execute_tool_action() {
	# Executes the selected tool.
	# Arguments:
	#   $1 - tool name
	#   $2 - tool query
	#   $3 - human-readable context (optional)
	#   $4 - structured args JSON (optional)
	local tool query context args_json
	tool="$1"
	query="$2"
	context="$3"
	args_json="$4"
	execute_tool_with_query "${tool}" "${query}" "${context}" "${args_json}"
}

is_duplicate_action() {
	# Determines whether the supplied action matches the previous non-final answer action.
	# Arguments:
	#   $1 - last action JSON
	#   $2 - candidate tool name
	#   $3 - candidate args JSON
	#   $4 - (optional) output variable name for evaluation metadata JSON
	local last_action tool args_json metadata_var last_tool last_exit_code normalized_current normalized_last duplicate
	local metadata last_exit_code_json normalized_current_json normalized_last_json last_action_json
	last_action="$1"
	tool="$2"
	args_json="$3"
	metadata_var="${4:-}"

	duplicate=false
	last_exit_code=0
	normalized_current="$(normalize_action "${tool}" "${args_json}")"
	normalized_last="{}"
	last_action_json="{}"

	if [[ "${last_action}" != "null" && -n "${last_action}" ]]; then
		if ! last_action_json="$(jq -c '.' <<<"${last_action}" 2>/dev/null)"; then
			last_action_json="{}"
		fi
		last_exit_code=$(printf '%s' "${last_action}" | jq -r '.exit_code // 0' 2>/dev/null || echo 0)
		if ((last_exit_code == 0)); then
			last_tool="$(printf '%s' "${last_action}" | jq -r '.tool // empty')"
			if ! normalized_last="$(jq -cS '{tool,args}' <<<"${last_action_json}" 2>/dev/null)"; then
				normalized_last="{}"
			fi
			if [[ "${tool}" == "${last_tool}" && "${normalized_current}" == "${normalized_last}" && "${tool}" != "final_answer" ]]; then
				duplicate=true
			fi
		fi
	fi

	if [[ "${last_exit_code}" =~ ^-?[0-9]+$ ]]; then
		last_exit_code_json=${last_exit_code}
	else
		last_exit_code_json=null
	fi

	if ! normalized_current_json="$(jq -c '.' <<<"${normalized_current}" 2>/dev/null)"; then
		normalized_current_json="{}"
	fi
	if ! normalized_last_json="$(jq -c '.' <<<"${normalized_last}" 2>/dev/null)"; then
		normalized_last_json="{}"
	fi

	metadata="$(jq -nc \
		--argjson duplicate "${duplicate}" \
		--arg tool "${tool}" \
		--argjson last_exit_code "${last_exit_code_json}" \
		--argjson normalized_candidate "${normalized_current_json}" \
		--argjson normalized_previous "${normalized_last_json}" \
		'{
                        duplicate_detected: $duplicate,
                        tool: $tool,
                        last_exit_code: $last_exit_code,
                        normalized_candidate: $normalized_candidate,
                        normalized_previous: $normalized_previous
                }')"

	if [[ -n "${metadata_var}" ]]; then
		printf -v "${metadata_var}" '%s' "${metadata}"
	fi

	if [[ "${duplicate}" == true ]]; then
		return 0
	fi

	return 1
}

log_action_gate() {
	# Emits structured metadata describing gating decisions.
	# Arguments:
	#   $1 - state prefix
	#   $2 - whether the action was allowed (string: true/false)
	#   $3 - gating reason (string)
	#   $4 - evaluation flags JSON (string, optional)
	local state_prefix allowed reason flags_json allowed_json plan_index plan_index_json pending_plan_step pending_json
	local attempt_index attempt_json payload normalized_flags
	state_prefix="$1"
	allowed="$2"
	reason="$3"
	flags_json="${4:-}"
	if [[ -z "${flags_json}" ]]; then
		flags_json="{}"
	fi

	allowed_json=false
	if [[ "${allowed}" == true ]]; then
		allowed_json=true
	fi

	plan_index="$(state_get "${state_prefix}" "plan_index")"
	pending_plan_step="$(state_get "${state_prefix}" "pending_plan_step")"
	attempt_index="$(state_get "${state_prefix}" "attempts")"

	plan_index_json=null
	pending_json=null
	attempt_json=null
	if [[ "${plan_index}" =~ ^-?[0-9]+$ ]]; then
		plan_index_json=${plan_index}
	fi
	if [[ "${pending_plan_step}" =~ ^-?[0-9]+$ ]]; then
		pending_json=${pending_plan_step}
	fi
	if [[ "${attempt_index}" =~ ^-?[0-9]+$ ]]; then
		attempt_json=${attempt_index}
	fi

	if ! normalized_flags="$(jq -c '.' <<<"${flags_json}" 2>/dev/null)"; then
		normalized_flags="{}"
	fi
	payload="$(jq -nc \
		--arg reason "${reason}" \
		--argjson allowed "${allowed_json}" \
		--argjson plan_index "${plan_index_json}" \
		--argjson pending_plan_step "${pending_json}" \
		--argjson attempt "${attempt_json}" \
		--argjson flags "${normalized_flags}" \
		'{
                        reason: $reason,
                        allowed: $allowed,
                        plan_index: $plan_index,
                        pending_plan_step: $pending_plan_step,
                        attempt: $attempt,
                        flags: $flags
                }')"

	log "INFO" "Action gate evaluation" "${payload}"
}

increment_retry_count() {
	# Increments the retry counter stored in state.
	# Arguments:
	#   $1 - state prefix
	local state_name updated_document
	state_name="$1"

	if ! updated_document="$(
		state_get_json_document "${state_name}" |
			jq -c '.retry_count = ((try (.retry_count|tonumber) catch 0) + 1)'
	)"; then
		return 1
	fi

	state_set_json_document "${state_name}" "${updated_document}"
}

increment_failure_count() {
	# Increments the failure counter stored in state.
	# Arguments:
	#   $1 - state prefix
	local state_name updated_document
	state_name="$1"

	if ! updated_document="$(
		state_get_json_document "${state_name}" |
			jq -c '.failure_count = ((try (.failure_count|tonumber) catch 0) + 1)'
	)"; then
		return 1
	fi

	state_set_json_document "${state_name}" "${updated_document}"
}

build_execution_transcript() {
	# Builds a human-readable transcript of prior steps with exit codes and outputs.
	# Arguments:
	#   $1 - state prefix
	local state_name document
	state_name="$1"
	document="$(state_get_json_document "${state_name}")"

	jq -r '
                (.history // [])
                | to_entries
                | map(
                        . as $wrapper
                        | ($wrapper.value | (try (fromjson // .) catch $wrapper.value)) as $entry
                        | if ($entry | type == "object") then
                                ($entry.observation_raw // $entry.observation // $entry.observation_summary // "") as $raw_obs
                                | ($entry.action.args // {}) as $args
                                | ($entry.action.tool // "") as $tool
                                | ($entry.thought // "") as $thought
                                | ($entry.observation_raw // {}) as $raw_field
                                | ($raw_field | (if type == "object" then . else {} end)) as $raw_obj
                                | "Step " + (($entry.step // ($wrapper.key + 1))|tostring) + ":\n"
                                + "- thought: " + $thought + "\n"
                                + "- tool: " + $tool + "\n"
                                + "- args: " + ($args | @json) + "\n"
                                + "- observation: " + (
                                        if ($raw_obj | length) > 0 then
                                                (
                                                        "output=" + (($raw_obj.output // $raw_obs // "")|tostring)
                                                        + ", error=" + (($raw_obj.error // "")|tostring)
                                                        + ", exit_code=" + (($raw_obj.exit_code // "(unknown)")|tostring)
                                                )
                                        else
                                                ($raw_obs|tostring)
                                        end
                                )
                        else
                                "Step " + (($wrapper.key + 1)|tostring) + " (raw):\n- log: " + ($entry|tostring)
                        end
                )
                | join("\n\n")
        ' <<<"${document}" 2>/dev/null || printf ''
}

apply_replan_result() {
	# Applies a planner response to the current ReAct state.
	# Arguments:
	#   $1 - state prefix
	#   $2 - planner response JSON
	#   $3 - current attempt index (int)
	local state_prefix plan_response current_attempt plan_entries plan_outline allowed_tools plan_length retry_buffer current_max new_max document
	state_prefix="$1"
	plan_response="$2"
	current_attempt="$3"

	if ! plan_entries="$(plan_json_to_entries "${plan_response}")"; then
		log "WARN" "Planner response missing entries" "$(jq -nc --argjson attempt "${current_attempt}" '{attempt:$attempt,reason:"plan_entries_unavailable"}')"
		return 1
	fi

	if ! plan_outline="$(plan_json_to_outline "${plan_response}")"; then
		log "WARN" "Planner response missing outline" "$(jq -nc --argjson attempt "${current_attempt}" '{attempt:$attempt,reason:"plan_outline_unavailable"}')"
		return 1
	fi

	if ! allowed_tools="$(derive_allowed_tools_from_plan "${plan_response}")"; then
		log "WARN" "Planner response missing allowed tools" "$(jq -nc --argjson attempt "${current_attempt}" '{attempt:$attempt,reason:"allowed_tools_unavailable"}')"
		return 1
	fi

	plan_length=$(printf '%s\n' "${plan_entries}" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
	if ! [[ "${plan_length}" =~ ^[0-9]+$ ]]; then
		plan_length=0
	fi

	retry_buffer="$(state_get "${state_prefix}" "retry_buffer")"
	if ! [[ "${retry_buffer}" =~ ^[0-9]+$ ]]; then
		retry_buffer=0
	fi

	current_max="$(state_get "${state_prefix}" "max_steps")"
	if ! [[ "${current_max}" =~ ^[0-9]+$ ]]; then
		current_max=${plan_length}
	fi

	if ! [[ "${current_attempt}" =~ ^[0-9]+$ ]]; then
		current_attempt=0
	fi

	new_max=${current_max}
	local recomputed_max
	recomputed_max=$((current_attempt + plan_length + retry_buffer))
	if ((recomputed_max > new_max)); then
		new_max=${recomputed_max}
	fi

	local application_metadata
	application_metadata="$(jq -nc \
		--argjson attempt "${current_attempt}" \
		--argjson plan_length "${plan_length}" \
		--argjson retry_buffer "${retry_buffer}" \
		--argjson current_max "${current_max}" \
		--argjson new_max "${new_max}" \
		--arg allowed_tools "${allowed_tools}" \
		'{attempt:$attempt,plan_length:$plan_length,retry_buffer:$retry_buffer,current_max:$current_max,new_max:$new_max,allowed_tools:($allowed_tools|split("\n")|map(select(length>0)))}')"
	log "INFO" "Applying replanned result" "${application_metadata}"

	if ! document="$(
		state_get_json_document "${state_prefix}" |
			jq -c \
				--arg plan_entries "${plan_entries}" \
				--arg plan_outline "${plan_outline}" \
				--arg allowed_tools "${allowed_tools}" \
				--argjson plan_length "${plan_length}" \
				--argjson max_steps "${new_max}" \
				--argjson last_replan_attempt "${current_attempt}" \
				'.plan_entries = $plan_entries
                                | .plan_outline = $plan_outline
                                | .allowed_tools = $allowed_tools
                                | .plan_length = $plan_length
                                | .plan_index = 0
                                | .pending_plan_step = null
                                | .plan_skip_reason = ""
                                | .max_steps = $max_steps
                                | .last_replan_attempt = $last_replan_attempt'
	)"; then
		return 1
	fi

	state_set_json_document "${state_prefix}" "${document}"
	state_set "${state_prefix}" "plan_length" "${plan_length}"
	state_set "${state_prefix}" "max_steps" "${new_max}"
	state_set "${state_prefix}" "plan_entries" "${plan_entries}"
	state_set "${state_prefix}" "plan_outline" "${plan_outline}"
	state_set "${state_prefix}" "allowed_tools" "${allowed_tools}"

	log "INFO" "Replan applied to state" "$(jq -nc --argjson attempt "${current_attempt}" --argjson plan_length "${plan_length}" --argjson max_steps "${new_max}" '{attempt:$attempt,plan_length:$plan_length,max_steps:$max_steps,action:"state_updated"}')"
}

maybe_trigger_replan() {
	# Re-runs the planner when failure or plan divergence thresholds are met.
	# Arguments:
	#   $1 - state prefix
	#   $2 - current attempt index (int)
	#   $3 - whether the plan diverged from execution (string: true/false)
	local state_prefix current_attempt plan_diverged failure_count threshold last_replan_attempt should_replan divergence_recorded
	state_prefix="$1"
	current_attempt="$2"
	plan_diverged="$3"

	failure_count="$(state_get "${state_prefix}" "failure_count")"
	if ! [[ "${failure_count}" =~ ^[0-9]+$ ]]; then
		failure_count=0
	fi

	threshold="${REACT_REPLAN_FAILURE_THRESHOLD:-2}"
	if ! [[ "${threshold}" =~ ^[0-9]+$ ]] || ((threshold < 1)); then
		threshold=2
	fi

	last_replan_attempt="$(state_get "${state_prefix}" "last_replan_attempt")"
	if ! [[ "${last_replan_attempt}" =~ ^[0-9]+$ ]]; then
		last_replan_attempt=0
	fi

	local evaluation_metadata
	evaluation_metadata="$(jq -nc \
		--argjson attempt "${current_attempt}" \
		--argjson failure_count "${failure_count}" \
		--argjson threshold "${threshold}" \
		--arg plan_diverged "${plan_diverged}" \
		--argjson last_replan_attempt "${last_replan_attempt}" \
		'{attempt:$attempt,failure_count:$failure_count,threshold:$threshold,plan_diverged:($plan_diverged=="true"),last_replan_attempt:$last_replan_attempt}')"
	log "DEBUG" "Evaluating replan conditions" "${evaluation_metadata}"

	should_replan=false
	divergence_recorded=false
	if ((failure_count > 0)) && ((failure_count % threshold == 0)); then
		should_replan=true
		log "INFO" "Failure threshold reached; considering replanning" "${evaluation_metadata}"
	fi

	if [[ "${plan_diverged}" == true ]]; then
		local last_divergence_step
		last_divergence_step="$(state_get "${state_prefix}" "last_plan_divergence_step")"
		if ! [[ "${last_divergence_step}" =~ ^[0-9]+$ ]]; then
			last_divergence_step=0
		fi
		if ((current_attempt > last_divergence_step)); then
			should_replan=true
			divergence_recorded=true
			log "INFO" "Plan divergence detected" "$(jq -nc \
				--argjson attempt "${current_attempt}" \
				--argjson last_divergence_step "${last_divergence_step}" \
				--argjson failure_count "${failure_count}" \
				'{attempt:$attempt,last_divergence_step:$last_divergence_step,failure_count:$failure_count,reason:"plan_divergence"}')"
		fi
	fi

	if [[ "${should_replan}" != true ]]; then
		log "DEBUG" "Replan skipped; conditions not met" "$(jq -nc --argjson attempt "${current_attempt}" --argjson failure_count "${failure_count}" --argjson threshold "${threshold}" --arg plan_diverged "${plan_diverged}" '{attempt:$attempt,failure_count:$failure_count,threshold:$threshold,plan_diverged:($plan_diverged=="true"),reason:"conditions_not_met"}')"
		return 0
	fi

	if ((last_replan_attempt == current_attempt)); then
		log "INFO" "Replan already attempted for current step" "$(jq -nc --argjson attempt "${current_attempt}" --argjson last_replan_attempt "${last_replan_attempt}" '{attempt:$attempt,last_replan_attempt:$last_replan_attempt,reason:"duplicate_attempt"}')"
		return 0
	fi

	if [[ "${divergence_recorded}" == true ]]; then
		state_set "${state_prefix}" "last_plan_divergence_step" "${current_attempt}"
	fi

	if ! declare -F generate_planner_response >/dev/null 2>&1; then
		log "WARN" "Planner unavailable; skipping replanning" "$(jq -nc --argjson attempt "${current_attempt}" --argjson failure_count "${failure_count}" '{attempt:$attempt,failure_count:$failure_count,planner_available:false,missing:"generate_planner_response"}')"
		return 1
	fi

	if ! declare -F plan_json_to_entries >/dev/null 2>&1 || ! declare -F plan_json_to_outline >/dev/null 2>&1 || ! declare -F derive_allowed_tools_from_plan >/dev/null 2>&1; then
		log "WARN" "Planner helpers missing; skipping replanning" "$(jq -nc --argjson attempt "${current_attempt}" --argjson failure_count "${failure_count}" '{attempt:$attempt,failure_count:$failure_count,planner_helpers_present:false}')"
		return 1
	fi

	local transcript user_query plan_response
	transcript="$(build_execution_transcript "${state_prefix}")"
	if [[ -z "${transcript}" ]]; then
		transcript="Execution transcript unavailable."
	fi

	user_query="$(state_get "${state_prefix}" "user_query")"
	if ! plan_response="$(generate_planner_response "${user_query}" "${transcript}")"; then
		log "WARN" "Planner failed to generate replan" "$(jq -nc --argjson attempt "${current_attempt}" --argjson failure_count "${failure_count}" '{attempt:$attempt,failure_count:$failure_count,planner_response:"generation_failed"}')"
		return 1
	fi

	local response_summary
	response_summary="$(jq -nc --argjson attempt "${current_attempt}" --argjson failure_count "${failure_count}" --argjson response_length "$(printf '%s' "${plan_response}" | jq 'length' 2>/dev/null || printf '0')" '{attempt:$attempt,failure_count:$failure_count,response_length:$response_length}')"
	log "DEBUG" "Planner response received" "${response_summary}"

	if ! apply_replan_result "${state_prefix}" "${plan_response}" "${current_attempt}"; then
		log "WARN" "Failed to apply replanned outline" "$(jq -nc --argjson attempt "${current_attempt}" --argjson failure_count "${failure_count}" --arg plan_response "${plan_response}" '{attempt:$attempt,failure_count:$failure_count,planner_response:$plan_response,reason:"apply_failed"}')"
		return 1
	fi

	state_set "${state_prefix}" "last_replan_attempt" "${current_attempt}"
	log "INFO" "Recorded last replan attempt" "$(jq -nc --argjson attempt "${current_attempt}" '{last_replan_attempt:$attempt}')"
	local replan_metadata
	replan_metadata="$(jq -nc \
		--argjson attempt "${current_attempt}" \
		--argjson failure_count "${failure_count}" \
		--arg plan_diverged "${plan_diverged}" \
		'{attempt:$attempt,failure_count:$failure_count,plan_diverged:($plan_diverged == "true")}')"
	log "INFO" "Replanned after execution issue" "${replan_metadata}"
}

react_loop() {
	local user_query allowed_tools plan_entries plan_outline action_json tool query observation current_step thought args_json action_context
	local normalized_args_json final_answer_payload pending_plan_step plan_diverged gate_reason duplicate_metadata
	local state_prefix last_action
	user_query="$1"
	allowed_tools="$2"
	plan_entries="$3"
	plan_outline="$4"

	state_prefix="react_state"
	initialize_react_state "${state_prefix}" "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
	action_json=""

	while :; do
		local max_steps attempts
		max_steps=$(state_get "${state_prefix}" "max_steps")
		attempts=$(state_get "${state_prefix}" "attempts")
		if ! [[ "${max_steps}" =~ ^[0-9]+$ ]]; then
			max_steps=0
		fi
		if ! [[ "${attempts}" =~ ^[0-9]+$ ]]; then
			attempts=0
		fi

		if ((attempts >= max_steps)); then
			break
		fi

		current_step=$((attempts + 1))
		state_set "${state_prefix}" "attempts" "${current_step}"
		action_json=""
		gate_reason="validated"
		duplicate_metadata="{}"

		local progress_step progress_made plan_completed
		progress_step=$(($(state_get "${state_prefix}" "step") + 1))
		progress_made=false
		plan_completed=false

		if ! select_next_action "${state_prefix}" action_json; then
			log "WARN" "Skipping step due to invalid action selection" "step=${current_step}"
			log_action_gate "${state_prefix}" false "action_selection_failed" "$(jq -nc '{selection_valid:false}')"
			record_plan_skip_without_progress "${state_prefix}" "action_selection_failed"
			increment_retry_count "${state_prefix}"
			continue
		fi
		local action_selected duplicate_resolution_attempts duplicate_resolution_limit
		action_selected=false
		duplicate_resolution_attempts=0
		duplicate_resolution_limit=3

		while [[ "${action_selected}" == false ]]; do
			tool="$(printf '%s' "${action_json}" | jq -r '.tool // empty' 2>/dev/null || true)"
			thought="$(printf '%s' "${action_json}" | jq -r '.thought // empty' 2>/dev/null || true)"
			if ! args_json="$(printf '%s' "${action_json}" | jq -c '.args // {}' 2>/dev/null)"; then
				args_json="{}"
			fi
			normalized_args_json="$(normalize_args_json "${args_json}")"

			last_action="$(state_get "${state_prefix}" "last_action")"

			final_answer_payload=""
			if [[ "${tool}" == "final_answer" ]]; then
				final_answer_payload="$(extract_tool_query "${tool}" "${normalized_args_json}")"
				state_set "${state_prefix}" "final_answer_action" "${final_answer_payload}"
			fi

			if ! validate_tool_permission "${state_prefix}" "${tool}"; then
				log_action_gate "${state_prefix}" false "tool_not_permitted" "$(jq -nc '{selection_valid:true,tool_permitted:false}')"
				record_plan_skip_without_progress "${state_prefix}" "tool_not_permitted"
				increment_retry_count "${state_prefix}"
				maybe_trigger_replan "${state_prefix}" "${current_step}" true || true
				action_json=""
				break
			fi

			if is_duplicate_action "${last_action}" "${tool}" "${normalized_args_json}" duplicate_metadata; then
				local duplicate_flags
				duplicate_flags="$(jq -nc --argjson duplicate_info "${duplicate_metadata}" '{selection_valid:true,tool_permitted:true} + ($duplicate_info // {})')"
				log_action_gate "${state_prefix}" false "duplicate_action" "${duplicate_flags}"
				log "WARN" "Duplicate action detected" "${tool}"
				observation="Duplicate action detected. Please try a different approach or call final_answer if you are stuck."
				record_tool_execution "${state_prefix}" "${tool}" "${thought} (REPEATED)" "${normalized_args_json}" "${observation}" "${observation}" "${current_step}"
				increment_failure_count "${state_prefix}"

				state_set "${state_prefix}" "action_rejection_hint" "Proposed action duplicated the last successful step (tool=${tool}). Suggest a different tool or updated arguments." || true
				duplicate_resolution_attempts=$((duplicate_resolution_attempts + 1))

				if ((duplicate_resolution_attempts >= duplicate_resolution_limit)); then
					log "WARN" "Exceeded duplicate resolution attempts" "$(jq -nc --argjson attempts "${duplicate_resolution_attempts}" '{attempts:$attempts,reason:"duplicate_persistence"}')"
					maybe_trigger_replan "${state_prefix}" "${current_step}" false || true
					increment_retry_count "${state_prefix}"
					action_json=""
					break
				fi

				if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
					local revised_action_json
					if _select_action_from_llama "${state_prefix}" revised_action_json; then
						action_json="${revised_action_json}"
						duplicate_metadata="{}"
						continue
					fi
				fi

				increment_retry_count "${state_prefix}"
				action_json=""
				break
			fi

			action_selected=true
		done

		if [[ "${action_selected}" != true ]]; then
			continue
		fi

		# Track whether the selected action fulfills the pending planned step.
		# The plan index only advances after executing the expected tool (or when
		# an explicit skip reason is recorded) to keep plan progress in sync with
		# actual execution.
		local planned_entry planned_tool plan_step_matches_action
		plan_step_matches_action=true
		plan_diverged=false
		planned_entry=""
		planned_tool=""

		pending_plan_step="$(state_get "${state_prefix}" "pending_plan_step")"
		if [[ -n "${pending_plan_step}" ]]; then
			planned_entry=$(printf '%s\n' "$(state_get "${state_prefix}" "plan_entries")" | sed -n "$((pending_plan_step + 1))p")
			planned_tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
			if [[ -n "${planned_tool}" && "${planned_tool}" != "${tool}" && "${tool}" != "${REACT_REPLAN_TOOL}" ]]; then
				plan_step_matches_action=false
				plan_diverged=true
				gate_reason="plan_tool_mismatch"
				record_plan_skip_without_progress "${state_prefix}" "plan_tool_mismatch"
				increment_retry_count "${state_prefix}"
				maybe_trigger_replan "${state_prefix}" "${current_step}" true || true
				action_selected=false
			fi
		fi

		if [[ "${tool}" == "${REACT_REPLAN_TOOL}" ]]; then
			plan_diverged=true
			record_plan_skip_without_progress "${state_prefix}" "plan_replan_requested"
			maybe_trigger_replan "${state_prefix}" "${current_step}" true || true
			increment_retry_count "${state_prefix}"
			action_selected=false
		fi

		if [[ "${action_selected}" == false ]]; then
			continue
		fi

		if [[ -z "${final_answer_payload}" ]]; then
			final_answer_payload="$(extract_tool_query "${tool}" "${normalized_args_json}")"
		fi
		query="${final_answer_payload}"
		action_context="$(format_action_context "${thought}" "${tool}" "${normalized_args_json}")"

		local gate_flags
		gate_flags="$(jq -nc \
			--argjson duplicate_info "${duplicate_metadata}" \
			--argjson tool_permitted true \
			--argjson selection_valid true \
			--argjson plan_step_matches_action "$([[ "${plan_step_matches_action}" == true ]] && printf 'true' || printf 'false')" \
			--argjson plan_diverged "$([[ "${plan_diverged}" == true ]] && printf 'true' || printf 'false')" \
			'{
                                selection_valid: $selection_valid,
                                tool_permitted: $tool_permitted,
                                plan_step_matches_action: $plan_step_matches_action,
                                plan_diverged: $plan_diverged
                        } + ($duplicate_info // {})')"
		log_action_gate "${state_prefix}" true "${gate_reason}" "${gate_flags}"

		local tool_status failure_detail errexit_enabled
		observation=""
		errexit_enabled=false
		if [[ $- == *e* ]]; then
			errexit_enabled=true
		fi
		local observation_file
		observation_file="$(mktemp)"
		set +e
		execute_tool_action "${tool}" "${query}" "${action_context}" "${normalized_args_json}" >"${observation_file}"
		tool_status=$?
		if [[ "${errexit_enabled}" == true ]]; then
			set -e
		fi
		observation="$(cat "${observation_file}" 2>/dev/null || printf '')"
		rm -f "${observation_file}"
		if ((tool_status != 0)); then
			failure_detail="Tool ${tool} failed to run (exit ${tool_status}). Check stderr logs for details."
			log "ERROR" "Tool execution failed" "$(printf 'step=%s tool=%s exit_code=%s' "${current_step}" "${tool}" "${tool_status}")"
			observation=$(jq -nc \
				--arg output "${observation}" \
				--arg error "${failure_detail}" \
				--argjson exit_code "${tool_status}" \
				'{output:$output,error:$error,exit_code:$exit_code}')
		fi

		if [[ -z "${observation}" ]]; then
			observation=$(jq -nc \
				--arg output "" \
				--arg error "Tool produced no output; marking as failure." \
				--argjson exit_code "${tool_status}" \
				'{output:$output,error:$error,exit_code:$exit_code}')
		fi

		local exit_code
		exit_code=$(printf '%s' "${observation}" | jq -r '.exit_code // empty' 2>/dev/null || printf '')
		if [[ -z "${exit_code}" ]]; then
			exit_code=${tool_status:-0}
			observation=$(jq -c \
				--argjson exit_code "${exit_code}" \
				'. + {exit_code:$exit_code}' <<<"${observation}" 2>/dev/null || jq -nc \
				--arg output "" \
				--arg error "Tool returned invalid observation payload." \
				--argjson exit_code "${exit_code}" \
				'{output:$output,error:$error,exit_code:$exit_code}')
		fi

		if [[ "${tool}" == "final_answer" && ${exit_code} -eq 0 && -n "${final_answer_payload}" ]]; then
			observation="${final_answer_payload}"
		fi

		local observation_summary
		observation_summary="$(select_observation_summary "${tool}" "${observation}" "$(pwd)")"

		local failure_record failure_error
		failure_error=$(printf '%s' "${observation}" | jq -r '.error // empty' 2>/dev/null || printf '')
		if ((exit_code != 0)); then
			failure_record=$(jq -nc \
				--arg tool "${tool}" \
				--argjson step "${current_step}" \
				--argjson exit_code "${exit_code}" \
				--arg error "${failure_error:-"Tool execution failed"}" \
				'{tool:$tool,step:$step,exit_code:$exit_code,error:$error}')
			state_set_json_document "${state_prefix}" "$(state_get_json_document "${state_prefix}" | jq -c --argjson failure "${failure_record}" '.last_tool_error = $failure')"
			log "ERROR" "Tool reported failure" "$(printf 'step=%s tool=%s exit_code=%s error=%s' "${current_step}" "${tool}" "${exit_code}" "${failure_error:-"(none)"}")"
		else
			state_set_json_document "${state_prefix}" "$(state_get_json_document "${state_prefix}" | jq -c '.last_tool_error = null')"
			progress_made=true
		fi

		if ((exit_code == 0)) && [[ "${plan_step_matches_action}" == true ]]; then
			if [[ -z "$(state_get "${state_prefix}" "pending_plan_step")" ]]; then
				state_set "${state_prefix}" "pending_plan_step" "$(state_get "${state_prefix}" "plan_index")"
			fi
			complete_pending_plan_step "${state_prefix}"
			local plan_length_value plan_index_value
			plan_length_value=$(state_get "${state_prefix}" "plan_length")
			plan_index_value=$(state_get "${state_prefix}" "plan_index")
			if [[ "${plan_length_value}" =~ ^[0-9]+$ && ${plan_length_value} -gt 0 ]]; then
				if ! [[ "${plan_index_value}" =~ ^[0-9]+$ ]]; then
					plan_index_value=0
				fi
				if ((plan_index_value >= plan_length_value)); then
					plan_completed=true
				fi
			fi
		fi

		record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${normalized_args_json}" "${observation}" "${observation_summary}" "${current_step}"
		if ((exit_code != 0)); then
			local plan_entries_text
			plan_entries_text="$(state_get "${state_prefix}" "plan_entries")"
			increment_retry_count "${state_prefix}"
			increment_failure_count "${state_prefix}"
			if ! maybe_trigger_replan "${state_prefix}" "${current_step}" "${plan_diverged}"; then
				if [[ -n "${plan_entries_text}" && "${LLAMA_AVAILABLE}" == true ]]; then
					log "INFO" "Tool failed during planned execution; falling back to LLM" "${tool}"
					state_set "${state_prefix}" "plan_entries" ""
				fi
			fi
		elif [[ "${plan_diverged}" == true ]]; then
			maybe_trigger_replan "${state_prefix}" "${current_step}" "${plan_diverged}" || true
		fi

		local normalized_action
		normalized_action="$(normalize_action "${tool}" "${normalized_args_json}")"
		state_set_json_document "${state_prefix}" "$(state_get_json_document "${state_prefix}" | jq -c --argjson action "${normalized_action}" --argjson exit_code "${exit_code}" '.last_action = ($action + {exit_code:$exit_code})')"

		if [[ "${progress_made}" == true ]]; then
			state_set "${state_prefix}" "step" "${progress_step}"
		fi
		if [[ "${tool}" == "final_answer" && ${exit_code} -eq 0 ]]; then
			state_set "${state_prefix}" "final_answer" "${observation}"
			break
		fi
		if [[ "${plan_completed}" == true ]]; then
			break
		fi
	done

	finalize_react_result "${state_prefix}"
}
