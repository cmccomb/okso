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
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on invalid actions or tool execution failures.

REACT_LIB_DIR=${REACT_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=../formatting.sh disable=SC1091
source "${REACT_LIB_DIR}/../formatting.sh"
# shellcheck source=../prompt/build_react.sh disable=SC1091
source "${REACT_LIB_DIR}/../prompt/build_react.sh"
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
# shellcheck source=../llm/context_budget.sh disable=SC1091
source "${REACT_LIB_DIR}/../llm/context_budget.sh"

format_tool_args() {
	# Formats tool arguments into a JSON object.
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - primary payload string (string)
	# Returns:
	#   A JSON string representing the tool arguments.
	local tool payload text_key
	tool="$1"
	payload="$2"
	text_key="${CANONICAL_TEXT_ARG_KEY:-input}"
	case "${tool}" in
	terminal)
		read -r -a terminal_tokens <<<"${payload}"
		if ((${#terminal_tokens[@]} == 0)); then
			terminal_tokens=("status")
		fi
		jq -nc --arg command "${terminal_tokens[0]}" --argjson args "$(printf '%s\n' "${terminal_tokens[@]:1}" | jq -Rcs 'split("\n") | map(select(length > 0))')" '{command:$command,args:$args}'
		;;
	python_repl)
		jq -nc --arg code "${payload}" '{code:$code}'
		;;
	notes_search | calendar_search | mail_search)
		jq -nc --arg key "${text_key}" --arg value "${payload}" '{($key):$value}'
		;;
	web_search)
		jq -nc --arg query "${payload}" '{query:$query}'
		;;
	notes_list | reminders_list | calendar_list | mail_list_inbox | mail_list_unread)
		jq -nc '{}'
		;;
	notes_create | notes_append)
		local title body
		title=${payload%%$'\n'*}
		body=${payload#"${title}"}
		body=${body#$'\n'}
		jq -nc --arg title "${title}" --arg body "${body}" '{title:$title,body:$body}'
		;;
	notes_read)
		jq -nc --arg title "${payload}" '{title:$title}'
		;;
	reminders_create)
		local title notes time
		title=${payload%%$'\n'*}
		notes=${payload#"${title}"}
		notes=${notes#$'\n'}
		time=""
		jq -nc --arg title "${title}" --arg time "${time}" --arg notes "${notes}" '{title:$title,time:$time,notes:$notes}'
		;;
	reminders_complete)
		jq -nc --arg title "${payload}" '{title:$title}'
		;;
	calendar_create)
		local title start_time location
		title=${payload%%$'\n'*}
		start_time=${payload#"${title}"}
		start_time=${start_time#$'\n'}
		location=${start_time#*$'\n'}
		start_time=${start_time%%$'\n'*}
		jq -nc --arg title "${title}" --arg start_time "${start_time}" --arg location "${location}" '{title:$title,start_time:$start_time,location:$location}'
		;;
	mail_draft | mail_send)
		jq -nc --arg envelope "${payload}" '{envelope:$envelope}'
		;;
	final_answer)
		jq -nc --arg key "${text_key}" --arg value "${payload}" '{($key):$value}'
		;;
	*)
		jq -nc --arg key "${text_key}" --arg value "${payload}" '{($key):$value}'
		;;
	esac
}

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
	normalized="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"
	printf '%s' "${normalized}"
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
	local history plan_step_guidance plan_index planned_entry tool planned_thought planned_args_json invoke_llama allowed_tool_lines allowed_tool_descriptions summarized_history
	state_name="$1"
	output_name="$2"

	plan_index="$(state_get "${state_name}" "plan_index")"
	plan_index=${plan_index:-0}
	planned_entry=$(printf '%s\n' "$(state_get "${state_name}" "plan_entries")" | sed -n "$((plan_index + 1))p")
	tool=""
	planned_thought="Following planned step"
	planned_args_json="{}"
	plan_step_guidance="Planner provided no additional steps; choose the best next action."
	if [[ -n "${planned_entry}" ]]; then
		tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
		planned_thought="$(printf '%s' "${planned_entry}" | jq -r '.thought // "Following planned step"' 2>/dev/null || printf '')"
		planned_args_json="$(printf '%s' "${planned_entry}" | jq -c '.args // {}' 2>/dev/null || printf '{}')"
		plan_step_guidance="$(
			jq -rn \
				--arg step "$((plan_index + 1))" \
				--arg tool "${tool:-}" \
				--arg thought "${planned_thought}" \
				--argjson args "${planned_args_json}" \
				'"Step \($step) suggested by the planner:\n- tool: \($tool // "(unspecified)")\n- thought: \($thought // "")\n- args: \($args|@json)"'
		)"
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
		allowed_tools="$(tool_names)"
	fi

	if [[ "${tool}" == "react_fallback" ]]; then
		allowed_tools="$(tool_names)"
	fi

	if [[ -n "${allowed_tools}" ]] && ! grep -Fxq "final_answer" <<<"${allowed_tools}"; then
		allowed_tools+=$'\nfinal_answer'
	fi

	allowed_tools="$(printf '%s\n' "${allowed_tools}" | sed '/^react_fallback$/d' | awk '!seen[$0]++')"

	if [[ -z "${plan_step_guidance}" ]]; then
		plan_step_guidance="Planner provided no additional steps; choose the best next action."
	fi

	if [[ "${invoke_llama}" != true ]]; then
		return 1
	fi

	allowed_tool_lines="$(format_tool_descriptions "${allowed_tools}" format_tool_example_line)"
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

	plan_index="$(state_get "${state_name}" "plan_index")"
	plan_index=${plan_index:-0}
	planned_entry=$(printf '%s\n' "$(state_get "${state_name}" "plan_entries")" | sed -n "$((plan_index + 1))p")

	if [[ -n "${planned_entry}" ]]; then
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
		react_fallback_action=$(jq -nc --arg thought "$(printf '%s' "${planned_entry}" | jq -r '.thought // "Following planned step"' 2>/dev/null || printf '')" --arg tool "$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')" --argjson args "$(printf '%s' "${planned_entry}" | jq -c '.args // {}' 2>/dev/null || printf '{}')" '{thought:$thought,tool:$tool,args:$args}')
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
	local last_action tool args_json last_tool last_exit_code normalized_current normalized_last
	last_action="$1"
	tool="$2"
	args_json="$3"

	if [[ "${last_action}" == "null" ]]; then
		return 1
	fi

	last_exit_code=$(printf '%s' "${last_action}" | jq -r '.exit_code // 0' 2>/dev/null || echo 0)
	if ((last_exit_code != 0)); then
		return 1
	fi

	last_tool="$(printf '%s' "${last_action}" | jq -r '.tool // empty')"
	normalized_current="$(normalize_action "${tool}" "${args_json}")"
	normalized_last="$(jq -cS '{tool,args}' <<<"$(jq -c '.' <<<"${last_action}" 2>/dev/null || printf '{}')" 2>/dev/null || printf '{}')"
	if [[ "${tool}" == "${last_tool}" && "${normalized_current}" == "${normalized_last}" && "${tool}" != "final_answer" ]]; then
		return 0
	fi

	return 1
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

react_loop() {
	local user_query allowed_tools plan_entries plan_outline action_json tool query observation current_step thought args_json action_context
	local normalized_args_json final_answer_payload pending_plan_step
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

		local progress_step progress_made plan_completed
		progress_step=$(($(state_get "${state_prefix}" "step") + 1))
		progress_made=false
		plan_completed=false

		if ! select_next_action "${state_prefix}" action_json; then
			log "WARN" "Skipping step due to invalid action selection" "step=${current_step}"
			record_plan_skip_without_progress "${state_prefix}" "action_selection_failed"
			increment_retry_count "${state_prefix}"
			continue
		fi
		tool="$(printf '%s' "${action_json}" | jq -r '.tool // empty' 2>/dev/null || true)"
		thought="$(printf '%s' "${action_json}" | jq -r '.thought // empty' 2>/dev/null || true)"
		args_json="$(printf '%s' "${action_json}" | jq -c '.args // {}' 2>/dev/null || printf '{}')"
		normalized_args_json="$(normalize_args_json "${args_json}")"

		last_action="$(state_get "${state_prefix}" "last_action")"

		final_answer_payload=""
		if [[ "${tool}" == "final_answer" ]]; then
			final_answer_payload="$(extract_tool_query "${tool}" "${normalized_args_json}")"
			state_set "${state_prefix}" "final_answer_action" "${final_answer_payload}"
		fi

		if ! validate_tool_permission "${state_prefix}" "${tool}"; then
			record_plan_skip_without_progress "${state_prefix}" "tool_not_permitted"
			increment_retry_count "${state_prefix}"
			continue
		fi

		if is_duplicate_action "${last_action}" "${tool}" "${normalized_args_json}"; then
			log "WARN" "Duplicate action detected" "${tool}"
			observation="Duplicate action detected. Please try a different approach or call final_answer if you are stuck."
			record_tool_execution "${state_prefix}" "${tool}" "${thought} (REPEATED)" "${normalized_args_json}" "${observation}" "${current_step}"
			record_plan_skip_without_progress "${state_prefix}" "duplicate_action"
			increment_retry_count "${state_prefix}"
			continue
		fi

		# Track whether the selected action fulfills the pending planned step.
		# The plan index only advances after executing the expected tool (or when
		# an explicit skip reason is recorded) to keep plan progress in sync with
		# actual execution.
		local planned_entry planned_tool plan_step_matches_action
		plan_step_matches_action=true
		planned_entry=""
		planned_tool=""

		pending_plan_step="$(state_get "${state_prefix}" "pending_plan_step")"
		if [[ -n "${pending_plan_step}" ]]; then
			planned_entry=$(printf '%s\n' "$(state_get "${state_prefix}" "plan_entries")" | sed -n "$((pending_plan_step + 1))p")
			planned_tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
			if [[ -n "${planned_tool}" && "${planned_tool}" != "${tool}" ]]; then
				plan_step_matches_action=false
				record_plan_skip_without_progress "${state_prefix}" "plan_tool_mismatch"
				increment_retry_count "${state_prefix}"
			fi
		fi

		if [[ -z "${final_answer_payload}" ]]; then
			final_answer_payload="$(extract_tool_query "${tool}" "${normalized_args_json}")"
		fi
		query="${final_answer_payload}"
		action_context="$(format_action_context "${thought}" "${tool}" "${normalized_args_json}")"

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
			complete_pending_plan_step "${state_prefix}"
			local plan_length_value plan_index_value
			plan_length_value=$(state_get "${state_prefix}" "plan_length")
			plan_index_value=$(state_get "${state_prefix}" "plan_index")
			if [[ "${plan_length_value}" =~ ^[0-9]+$ && ${plan_length_value} -gt 0 ]]; then
				if ! [[ "${plan_index_value}" =~ ^[0-9]+$ ]]; then
					plan_index_value=0
				fi
				if ((plan_index_value < plan_length_value)); then
					state_set "${state_prefix}" "plan_index" "${plan_length_value}"
					plan_index_value=${plan_length_value}
				fi
				if ((plan_index_value >= plan_length_value)); then
					plan_completed=true
				fi
			fi
		fi

		record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${normalized_args_json}" "${observation}" "${current_step}"
		if ((exit_code != 0)); then
			local plan_entries_text
			plan_entries_text="$(state_get "${state_prefix}" "plan_entries")"
			if [[ -n "${plan_entries_text}" && "${LLAMA_AVAILABLE}" == true ]]; then
				log "INFO" "Tool failed during planned execution; falling back to LLM" "${tool}"
				state_set "${state_prefix}" "plan_entries" ""
			fi
			increment_retry_count "${state_prefix}"
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
