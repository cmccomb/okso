#!/usr/bin/env bash
# shellcheck shell=bash
#
# Planning and execution helpers for the okso assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/planner.sh}/planner.sh"
#
# Environment variables:
#   USER_QUERY (string): user-provided request for planning.
#   LLAMA_BIN (string): llama.cpp binary path.
#   MODEL_REPO (string): Hugging Face repository name.
#   MODEL_FILE (string): model file within the repository.
#   PLAN_ONLY, DRY_RUN (bool): control execution and preview behaviour.
#   APPROVE_ALL, FORCE_CONFIRM (bool): confirmation toggles.
#   VERBOSITY (int): log level.
#
# Dependencies:
#   - bash 3+
#   - optional llama.cpp binary
#   - jq
#   - gum (for interactive approvals; falls back to POSIX prompts)
#
# Exit codes:
#   Functions return non-zero on misuse; fatal errors logged by caller.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./errors.sh disable=SC1091
source "${LIB_DIR}/errors.sh"
# shellcheck source=./logging.sh disable=SC1091
source "${LIB_DIR}/logging.sh"
# shellcheck source=./tools.sh disable=SC1091
source "${LIB_DIR}/tools.sh"
# shellcheck source=./respond.sh disable=SC1091
source "${LIB_DIR}/respond.sh"
# shellcheck source=./prompts.sh disable=SC1091
source "${LIB_DIR}/prompts.sh"
# shellcheck source=./grammar.sh disable=SC1091
source "${LIB_DIR}/grammar.sh"
# shellcheck source=./state.sh disable=SC1091
source "${LIB_DIR}/state.sh"
# shellcheck source=./llama_client.sh disable=SC1091
source "${LIB_DIR}/llama_client.sh"
# shellcheck source=./formatting.sh disable=SC1091
source "${LIB_DIR}/formatting.sh"

lowercase() {
	# Arguments:
	#   $1 - input string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Normalize noisy planner output into a clean PlannerPlan JSON array.
# Reads from stdin, writes clean JSON array to stdout.
normalize_planner_plan() {
	local raw plan_candidate fallback_json normalized

	raw="$(cat)"
	plan_candidate="$(printf '%s' "$raw" | jq -ec 'select(type=="array")' 2>/dev/null || true)"

	fallback_json=$(printf '%s' "$raw" |
		sed -E 's/^[[:space:]]*[0-9]+[.)][[:space:]]*//' |
		sed -E 's/^[[:space:]-]+//' |
		sed '/^[[:space:]]*$/d' |
		jq -Rsc 'split("\n") | map(select(length > 0))') || fallback_json=""

	if [[ -n "${plan_candidate:-}" ]]; then
		normalized=$(printf '%s' "$plan_candidate" | jq -ec 'if type == "array" then [.. | select(type == "string" and length > 0)] else empty end | select(length > 0)' 2>/dev/null) || normalized=""
		if [[ -n "${normalized}" ]]; then
			printf '%s' "$normalized" | jq -c '.'
			return 0
		fi
	fi

	if [[ -n "${fallback_json}" && "${fallback_json}" != "[]" ]]; then
		log "INFO" "normalize_planner_plan: derived plan from fallback outline" "${fallback_json}" >&2
		printf '%s' "$fallback_json" | jq -c '.'
		return 0
	fi

	log "ERROR" "normalize_planner_plan: no JSON array found in planner output" "" >&2
	return 1
}

append_final_answer_step() {
	# Ensures the plan includes a final step with the final_answer tool.
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json has_final updated_plan
	plan_json="${1:-[]}"

	plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)"

	has_final="$(jq -r 'map(ascii_downcase | contains("final_answer")) | any' <<<"${plan_clean}" 2>/dev/null || echo false)"
	if [[ "${has_final}" == "true" ]]; then
		printf '%s' "${plan_clean}"
		return 0
	fi

	updated_plan="$(jq -c '. + ["Use final_answer to summarize the result for the user."]' <<<"${plan_clean}" 2>/dev/null || printf '%s' "${plan_json}")"
	printf '%s' "${updated_plan}"
}

plan_json_to_outline() {
	# Converts a JSON array of plan steps into a numbered outline string.
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json
	plan_json="${1:-[]}"

	plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)"

	jq -r 'to_entries | map("\(.key + 1). \(.value)") | join("\n")' <<<"${plan_clean}"
}

generate_plan_outline() {
	# Arguments:
	#   $1 - user query (string)
	local user_query
	user_query="$1"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "Using static plan outline because llama is unavailable" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
		printf '1. Use final_answer to respond directly to the user request.'
		return 0
	fi

	local prompt raw_plan planner_grammar_path plan_outline_json
	local tool_lines
	tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${TOOLS[@]}")" format_tool_summary_line)"
	planner_grammar_path="$(grammar_path planner_plan)"

	prompt="$(build_planner_prompt "${user_query}" "${tool_lines}")"
	raw_plan="$(llama_infer "${prompt}" '' 512 "${planner_grammar_path}")" || raw_plan="[]"
	plan_outline_json="$(append_final_answer_step "${raw_plan}")" || plan_outline_json="${raw_plan}"
	plan_json_to_outline "${plan_outline_json}" || printf '%s' "${plan_outline_json}"
}

tool_query_deriver() {
	# Arguments:
	#   $1 - tool name (string)
	case "$1" in
	terminal)
		printf '%s' "derive_terminal_query"
		;;
	reminders_create)
		printf '%s' "derive_reminders_create_query"
		;;
	reminders_list)
		printf '%s' "derive_reminders_list_query"
		;;
	notes_create)
		printf '%s' "derive_notes_create_query"
		;;
	notes_append)
		printf '%s' "derive_notes_append_query"
		;;
	notes_search)
		printf '%s' "derive_notes_search_query"
		;;
	notes_read)
		printf '%s' "derive_notes_read_query"
		;;
	notes_list)
		printf '%s' "derive_notes_list_query"
		;;
	*)
		printf '%s' "derive_default_tool_query"
		;;
	esac
}

derive_default_tool_query() {
	# Arguments:
	#   $1 - user query (string)
	printf '%s\n' "$1"
}

derive_tool_query() {
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - user query (string)
	local tool_name user_query handler
	tool_name="$1"
	user_query="$2"
	handler="$(tool_query_deriver "${tool_name}")"

	"${handler}" "${user_query}"
}

emit_plan_json() {
	local plan_entries
	plan_entries="$1"

	while IFS=$'|' read -r tool query score; do
		[[ -z "${tool}" ]] && continue
		jq -n \
			--arg tool "${tool}" \
			--arg query "${query}" \
			--argjson score "${score:-0}" \
			'{tool:$tool, query:$query, score:$score}'
	done <<<"${plan_entries}" | jq -sc '.'
}

extract_tools_from_plan() {
	# Arguments:
	#   $1 - plan outline text (string)
	local plan_text lower_line tool tool_list
	local seen
	seen=""
	local -a required=()
	plan_text="$1"
	tool_list="$(tool_names)"

	while IFS= read -r line; do
		lower_line="$(lowercase "${line}")"
		while IFS= read -r tool; do
			[[ -z "${tool}" ]] && continue
			if grep -Fxq "${tool}" <<<"${seen}"; then
				continue
			fi
			if [[ "${lower_line}" == *"$(lowercase "${tool}")"* ]]; then
				required+=("${tool}")
				seen+="${tool}"$'\n'
			fi
		done <<<"${tool_list}"
	done <<<"${plan_text}"

	if ! grep -Fxq "final_answer" <<<"${seen}"; then
		required+=("final_answer")
	fi

	printf '%s\n' "${required[@]}"
}

build_plan_entries_from_tools() {
	# Arguments:
	#   $1 - newline-delimited tool names
	#   $2 - user query (string)
	local tool_list user_query plan query
	tool_list="$1"
	user_query="$2"
	plan=""

	while IFS= read -r tool; do
		[[ -z "${tool}" ]] && continue
		if [[ "${tool}" == "final_answer" ]]; then
			continue
		fi
		query="$(derive_tool_query "${tool}" "${user_query}")"
		plan+="${tool}|${query}|0"$'\n'
	done <<<"${tool_list}"

	printf '%s' "${plan}"
}

should_prompt_for_tool() {
	if [[ "${PLAN_ONLY}" == true || "${DRY_RUN}" == true ]]; then
		return 1
	fi
	if [[ "${FORCE_CONFIRM}" == true ]]; then
		return 0
	fi
	if [[ "${APPROVE_ALL}" == true ]]; then
		return 1
	fi

	return 0
}

confirm_tool() {
	local tool_name
	tool_name="$1"
	if ! should_prompt_for_tool; then
		return 0
	fi

	local prompt
	prompt="Execute tool \"${tool_name}\"?"
	if command -v gum >/dev/null 2>&1; then
		if ! gum confirm --affirmative "Run" --negative "Skip" "${prompt}"; then
			log "WARN" "Tool execution declined" "${tool_name}"
			printf '[%s skipped]\n' "${tool_name}"
			return 1
		fi
		return 0
	fi

	printf '%s [y/N]: ' "${prompt}" >&2
	read -r reply
	if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
		log "WARN" "Tool execution declined" "${tool_name}"
		printf '[%s skipped]\n' "${tool_name}"
		return 1
	fi
	return 0
}

execute_tool_with_query() {
	local tool_name tool_query handler output status
	tool_name="$1"
	tool_query="$2"
	handler="$(tool_handler "${tool_name}")"

	local requires_confirmation
	requires_confirmation=false
	if [[ "${tool_name}" != "final_answer" ]] && should_prompt_for_tool; then
		requires_confirmation=true
	fi

	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}" >&2
		return 1
	fi

	if [[ "${tool_name}" != "final_answer" ]]; then
		if [[ "${requires_confirmation}" == true ]]; then
			log "INFO" "Requesting tool confirmation" "$(printf 'tool=%s query=%s' "${tool_name}" "${tool_query}")" >&2
		fi

		if ! confirm_tool "${tool_name}"; then
			printf 'Declined %s\n' "${tool_name}"
			return 0
		fi
	fi

	if [[ "${DRY_RUN}" == true || "${PLAN_ONLY}" == true ]]; then
		log "INFO" "Skipping execution in preview mode" "${tool_name}" >&2
		return 0
	fi

	local stdout_file stderr_file stderr_output
	stdout_file="$(mktemp)"
	stderr_file="$(mktemp)"

	TOOL_QUERY="${tool_query}" ${handler} >"${stdout_file}" 2>"${stderr_file}"
	status=$?
	output="$(cat "${stdout_file}")"
	stderr_output="$(cat "${stderr_file}")"

	rm -f "${stdout_file}" "${stderr_file}"

	if [[ -n "${stderr_output}" ]]; then
		log "INFO" "Tool emitted stderr" "$(printf 'tool=%s stderr=%s' "${tool_name}" "${stderr_output}")" >&2
	fi
	if ((status != 0)); then
		log "WARN" "Tool reported non-zero exit" "${tool_name}" >&2
	fi
	printf '%s\n' "${output}"
	return 0
}

initialize_react_state() {
	# Arguments:
	#   $1 - state prefix to populate
	#   $2 - user query
	#   $3 - allowed tools (newline delimited)
	#   $4 - ranked plan entries
	#   $5 - plan outline text
	local state_prefix
	state_prefix="$1"

	state_set_json_document "${state_prefix}" "$(jq -c -n \
		--arg user_query "$2" \
		--arg allowed_tools "$3" \
		--arg plan_entries "$4" \
		--arg plan_outline "$5" \
		--argjson max_steps "${MAX_STEPS:-6}" \
		'{
                        user_query: $user_query,
                        allowed_tools: $allowed_tools,
                        plan_entries: $plan_entries,
                        plan_outline: $plan_outline,
                        history: [],
                        step: 0,
                        plan_index: 0,
                        max_steps: $max_steps,
                        final_answer: ""
                }')"
}

record_history() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - formatted history entry
	local entry
	entry="$2"
	state_append_history "$1" "${entry}"
}

select_next_action() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - (optional) name of variable to receive JSON action output
	local state_name output_name react_prompt plan_index planned_entry tool query next_action_payload allowed_tool_descriptions allowed_tool_lines
	state_name="$1"
	output_name="${2:-}"
	if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
		allowed_tool_lines="$(format_tool_descriptions "$(state_get "${state_name}" "allowed_tools")" format_tool_example_line)"
		allowed_tool_descriptions="Available tools:"
		if [[ -n "${allowed_tool_lines}" ]]; then
			allowed_tool_descriptions+=$'\n'"${allowed_tool_lines}"
		fi
		react_prompt="$(build_react_prompt "$(state_get "${state_name}" "user_query")" "${allowed_tool_descriptions}" "$(state_get "${state_name}" "plan_outline")" "$(state_get "${state_name}" "history")")"

		local react_grammar_path raw_action validated_action
		react_grammar_path="$(grammar_path react_action)"

		raw_action="$(llama_infer "${react_prompt}" "" 256 "${react_grammar_path}")"
		if ! validated_action=$(jq -cer 'select(type == "object") | {type, tool, query} | select(.type|type == "string") | select(.tool|type == "string") | select(.query|type == "string")' <<<"${raw_action}"); then
			log "ERROR" "Invalid action output from llama" "${raw_action}"
			return 1
		fi

		if [[ -n "${output_name}" ]]; then
			printf -v "${output_name}" '%s' "${validated_action}"
		else
			printf '%s\n' "${validated_action}"
		fi

		return
	fi

	plan_index="$(state_get "${state_name}" "plan_index")"
	plan_index=${plan_index:-0}
	planned_entry=$(printf '%s\n' "$(state_get "${state_name}" "plan_entries")" | sed -n "$((plan_index + 1))p")

	if [[ -n "${planned_entry}" ]]; then
		tool="${planned_entry%%|*}"
		query="${planned_entry#*|}"
		query="${query%%|*}"
		state_increment "${state_name}" "plan_index" 1 >/dev/null
		next_action_payload="$(jq -n --arg tool "${tool}" --arg query "${query}" '{type:"tool", tool:$tool, query:$query}')"
	else
		local final_query
		final_query="$(respond_text "$(state_get "${state_name}" "user_query") $(state_get "${state_name}" "history")" 512)"
		next_action_payload="$(jq -n --arg tool "final_answer" --arg query "${final_query}" '{type:"tool", tool:$tool, query:$query}')"
	fi

	if [[ -n "${output_name}" ]]; then
		printf -v "${output_name}" '%s' "${next_action_payload}"
	else
		printf '%s\n' "${next_action_payload}"
	fi
}

validate_tool_permission() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - tool name to validate
	local state_name
	local tool
	state_name="$1"
	tool="$2"
	if grep -Fxq "${tool}" <<<"$(state_get "${state_name}" "allowed_tools")"; then
		return 0
	fi

	record_history "${state_name}" "$(printf 'Tool %s not permitted.' "${tool}")"
	return 1
}

execute_tool_action() {
	# Arguments:
	#   $1 - tool name
	#   $2 - tool query
	local tool query
	tool="$1"
	query="$2"
	execute_tool_with_query "${tool}" "${query}" || true
}

record_tool_execution() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - tool name
	#   $3 - query string
	#   $4 - observation text
	#   $5 - step index
	local state_name
	local tool query observation step_index
	state_name="$1"
	tool="$2"
	query="$3"
	observation="$4"
	step_index="$5"
	record_history "${state_name}" "$(printf 'Step %s action %s query=%s\nObservation: %s' "${step_index}" "${tool}" "${query}" "${observation}")"
	log "INFO" "Recorded tool execution" "$(printf 'step=%s tool=%s' "${step_index}" "${tool}")"
}

finalize_react_result() {
	# Arguments:
	#   $1 - state prefix
	local state_name
	state_name="$1"
	if [[ -z "$(state_get "${state_name}" "final_answer")" ]]; then
		log "ERROR" "Final answer missing; generating fallback" "${state_name}"
		state_set "${state_name}" "final_answer" "$(respond_text "$(state_get "${state_name}" "user_query") $(state_get "${state_name}" "history")" 1000)"
	fi

	log_pretty "INFO" "Final answer" "$(state_get "${state_name}" "final_answer")"
	if [[ -z "$(state_get "${state_name}" "history")" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "$(state_get "${state_name}" "history")"
	fi
}

react_loop() {
	local user_query allowed_tools plan_entries plan_outline action_json action_type tool query observation current_step
	local state_prefix
	user_query="$1"
	allowed_tools="$2"
	plan_entries="$3"
	plan_outline="$4"

	state_prefix="react_state"
	initialize_react_state "${state_prefix}" "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
	action_json=""

	while (($(state_get "${state_prefix}" "step") < $(state_get "${state_prefix}" "max_steps"))); do
		current_step=$(($(state_get "${state_prefix}" "step") + 1))

		select_next_action "${state_prefix}" action_json
		action_type="$(printf '%s' "${action_json}" | jq -r '.type // empty' 2>/dev/null || true)"
		tool="$(printf '%s' "${action_json}" | jq -r '.tool // empty' 2>/dev/null || true)"
		query="$(printf '%s' "${action_json}" | jq -r '.query // empty' 2>/dev/null || true)"

		if [[ "${action_type}" != "tool" ]]; then
			record_history "${state_prefix}" "$(printf 'Step %s unusable action: %s' "${current_step}" "${action_json}")"
			state_set "${state_prefix}" "step" "${current_step}"
			continue
		fi

		if ! validate_tool_permission "${state_prefix}" "${tool}"; then
			state_set "${state_prefix}" "step" "${current_step}"
			continue
		fi

		observation="$(execute_tool_action "${tool}" "${query}")"
		record_tool_execution "${state_prefix}" "${tool}" "${query}" "${observation}" "${current_step}"

		state_set "${state_prefix}" "step" "${current_step}"
		if [[ "${tool}" == "final_answer" ]]; then
			state_set "${state_prefix}" "final_answer" "${observation}"
			break
		fi
	done

	finalize_react_result "${state_prefix}"
}
