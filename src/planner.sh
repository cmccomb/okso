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
#   - bash 5+
#   - optional llama.cpp binary
#   - jq
#   - gum (for interactive approvals; falls back to POSIX prompts)
#
# Exit codes:
#   Functions return non-zero on misuse; fatal errors logged by caller.

# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/planner.sh}/logging.sh"
# shellcheck source=./tools.sh disable=SC1091
source "${BASH_SOURCE[0]%/planner.sh}/tools.sh"
# shellcheck source=./respond.sh disable=SC1091
source "${BASH_SOURCE[0]%/planner.sh}/respond.sh"

llama_infer() {
	# Runs llama.cpp with HF caching enabled for the configured model.
	local prompt
	prompt="$1"
	stop_string="$2"
	number_of_tokens="$3"

	# If a stop string is provided, use it to terminate output.
	if [[ -n "${stop_string}" ]]; then
		"${LLAMA_BIN}" \
			--hf-repo "${MODEL_REPO}" \
			--hf-file "${MODEL_FILE}" \
			-no-cnv --no-display-prompt --simple-io --verbose -r "${stop_string}" \
			-n "${number_of_tokens}" \
			-p "${prompt}" 2>/dev/null || true
		return
	fi

	"${LLAMA_BIN}" \
		--hf-repo "${MODEL_REPO}" \
		--hf-file "${MODEL_FILE}" \
		-n "${number_of_tokens}" \
		-no-cnv --no-display-prompt --simple-io --verbose \
		-p "${prompt}" 2>/dev/null || true
}

build_planner_prompt() {
	# Arguments:
	#   $1 - user query (string)
	local user_query tool_lines
	user_query="$1"
	tool_lines=""

	for tool in "${TOOLS[@]}"; do
		tool_lines+=$(printf -- '- %s: %s\n' "${tool}" "${TOOL_DESCRIPTION[${tool}]}")
	done

	cat <<PROMPT
You are a planner for an autonomous agent. Given a user request and a list of available tools, draft a numbered list of high-level actions the agent should take. Each step must mention the tool name that will be used. Do NOT include fully executable shell commands; keep the guidance conceptual. Always end with a final step that uses the final_answer tool to deliver the response back to the user.

Available tools:
${tool_lines}
User request: ${user_query}
PROMPT
}

append_final_answer_step() {
	# Ensures the plan includes a final step with the final_answer tool.
	# Arguments:
	#   $1 - plan text (string)
	local plan_text step_count
	plan_text="$1"

	if [[ "${plan_text,,}" == *"final_answer"* ]]; then
		printf '%s' "${plan_text}"
		return 0
	fi

	step_count=$(grep -Ec '^[[:space:]]*[0-9]+\.' <<<"${plan_text}" || true)
	step_count=${step_count:-0}
	step_count=$((step_count + 1))
	printf '%s\n%d. Use final_answer to summarize the result for the user.' "${plan_text}" "${step_count}"
}

generate_plan_outline() {
	# Arguments:
	#   $1 - user query (string)
	local user_query prompt raw_plan
	user_query="$1"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		printf '1. Use final_answer to respond directly to the user request.'
		return 0
	fi

	prompt="$(build_planner_prompt "${user_query}")"
	raw_plan="$(llama_infer "${prompt}" '' 512)"
	append_final_answer_step "${raw_plan}"
}

declare -A TOOL_QUERY_DERIVERS=(
	[terminal]=derive_terminal_query
	[reminders_create]=derive_reminders_create_query
	[reminders_list]=derive_reminders_list_query
	[notes_create]=derive_notes_create_query
	[notes_append]=derive_notes_append_query
	[notes_search]=derive_notes_search_query
	[notes_read]=derive_notes_read_query
	[notes_list]=derive_notes_list_query
)

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
	handler="${TOOL_QUERY_DERIVERS[${tool_name}]:-derive_default_tool_query}"

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
	local plan_text lower_line tool
	declare -A seen=()
	local -a required=()
	plan_text="$1"

	while IFS= read -r line; do
		lower_line="${line,,}"
		for tool in "${TOOLS[@]}"; do
			if [[ -n "${seen[${tool}]:-}" ]]; then
				continue
			fi
			if [[ "${lower_line}" == *"${tool,,}"* ]]; then
				required+=("${tool}")
				seen["${tool}"]=1
			fi
		done
	done <<<"${plan_text}"

	if [[ -z "${seen[final_answer]:-}" ]]; then
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
	handler="${TOOL_HANDLER[${tool_name}]}"

	local requires_confirmation
	requires_confirmation=false
	if [[ "${tool_name}" != "final_answer" ]] && should_prompt_for_tool; then
		requires_confirmation=true
	fi

	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}"
		return 1
	fi

	if [[ "${tool_name}" != "final_answer" ]]; then
		if [[ "${requires_confirmation}" == true ]]; then
			log "INFO" "Requesting tool confirmation" "$(printf 'tool=%s query=%s' "${tool_name}" "${tool_query}")"
		fi

		if ! confirm_tool "${tool_name}"; then
			printf 'Declined %s\n' "${tool_name}"
			return 0
		fi
	fi

	if [[ "${DRY_RUN}" == true || "${PLAN_ONLY}" == true ]]; then
		log "INFO" "Skipping execution in preview mode" "${tool_name}"
		return 0
	fi

	output="$(TOOL_QUERY="${tool_query}" ${handler} 2>&1)"
	status=$?
	if ((status != 0)); then
		log "WARN" "Tool reported non-zero exit" "${tool_name}"
	fi
	printf '%s\n' "${output}"
	return 0
}

build_react_prompt() {
	local user_query allowed_tools history plan_outline tool_lines
	user_query="$1"
	allowed_tools="$2"
	history="$3"
	plan_outline="$4"

	tool_lines="Available tools:"
	while IFS= read -r tool; do
		tool_lines+=$(printf '\n- %s: %s (example query: %s)' "${tool}" "${TOOL_DESCRIPTION[${tool}]}" "${TOOL_COMMAND[${tool}]}")
	done <<<"${allowed_tools}"

	cat <<PROMPT
You are an assistant planning a sequence of actions. Use the high-level plan as guidance but adapt after each observation.
Respond ONLY with a single JSON object per turn.
Action schema:
- To use a tool: {"type":"tool","tool":"<tool_name>","query":"<specific command>"}
- To finish: {"type":"tool","tool":"final_answer","query":"<final user-facing reply>"}
High-level plan:
${plan_outline}
User request: ${user_query}
${tool_lines}
Previous steps:
${history}
PROMPT
}

initialize_react_state() {
	# Arguments:
	#   $1 - name of associative array to populate
	#   $2 - user query
	#   $3 - allowed tools (newline delimited)
	#   $4 - ranked plan entries
	#   $5 - plan outline text
	local -n state_ref=$1
	state_ref[user_query]="$2"
	state_ref[allowed_tools]="$3"
	state_ref[plan_entries]="$4"
	state_ref[plan_outline]="$5"
	state_ref[history]=""
	state_ref[step]=0
	state_ref[plan_index]=0
	state_ref[max_steps]="${MAX_STEPS:-6}"
	state_ref[final_answer]=""
}

record_history() {
	# Arguments:
	#   $1 - name of associative array holding state
	#   $2 - formatted history entry
	local -n state_ref=$1
	local entry
	entry="$2"
	state_ref[history]+=$(printf '%s\n' "${entry}")
}

select_next_action() {
	# Arguments:
	#   $1 - name of associative array holding state
	#   $2 - (optional) name of variable to receive JSON action output
	local state_name output_name
	state_name="$1"
	output_name="${2:-}"
	local -n state_ref=$state_name
	local react_prompt plan_index planned_entry tool query next_action_payload
	if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
		react_prompt="$(build_react_prompt "${state_ref[user_query]}" "${state_ref[allowed_tools]}" "${state_ref[history]}" "${state_ref[plan_outline]}")"
		llama_infer "${react_prompt}"
		return
	fi

	plan_index="${state_ref[plan_index]}"
	planned_entry=$(printf '%s\n' "${state_ref[plan_entries]}" | sed -n "$((plan_index + 1))p")

	if [[ -n "${planned_entry}" ]]; then
		tool="${planned_entry%%|*}"
		query="${planned_entry#*|}"
		query="${query%%|*}"
		state_ref[plan_index]=$((plan_index + 1))
		next_action_payload="$(jq -n --arg tool "${tool}" --arg query "${query}" '{type:"tool", tool:$tool, query:$query}')"
	else
		local final_query
		final_query="$(respond_text "${state_ref[user_query]} ${state_ref[history]}" 512)"
		next_action_payload="$(jq -n --arg tool "final_answer" --arg query "${final_query}" '{type:"tool", tool:$tool, query:$query}')"
	fi

	if [[ -n "${output_name}" ]]; then
		local -n output_ref=$output_name
		output_ref="${next_action_payload}"
	else
		printf '%s\n' "${next_action_payload}"
	fi
}

validate_tool_permission() {
	# Arguments:
	#   $1 - name of associative array holding state
	#   $2 - tool name to validate
	local state_name
	local -n state_ref=$1
	local tool
	state_name="$1"
	tool="$2"
	if grep -Fxq "${tool}" <<<"${state_ref[allowed_tools]}"; then
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
	#   $1 - name of associative array holding state
	#   $2 - tool name
	#   $3 - query string
	#   $4 - observation text
	#   $5 - step index
	local state_name
	local -n state_ref=$1
	local tool query observation step_index
	state_name="$1"
	tool="$2"
	query="$3"
	observation="$4"
	step_index="$5"
	record_history "${state_name}" "$(printf 'Step %s action %s query=%s\nObservation: %s' "${step_index}" "${tool}" "${query}" "${observation}")"
}

finalize_react_result() {
	# Arguments:
	#   $1 - name of associative array holding state
	local -n state_ref=$1
	if [[ -z "${state_ref[final_answer]}" ]]; then
		state_ref[final_answer]="$(respond_text "${state_ref[user_query]} ${state_ref[history]}" 1000)"
	fi

	printf '%s\n' "${state_ref[final_answer]}"
	if [[ -n "${state_ref[plan_outline]}" ]]; then
		printf 'Plan outline:\n%s\n' "${state_ref[plan_outline]}"
	fi
	if [[ -z "${state_ref[history]}" ]]; then
		printf 'Execution summary: no tool runs.\n'
	else
		printf 'Execution summary:\n%s\n' "${state_ref[history]}"
	fi
}

react_loop() {
	local user_query allowed_tools plan_entries plan_outline action_json action_type tool query observation current_step
	declare -A react_state
	user_query="$1"
	allowed_tools="$2"
	plan_entries="$3"
	plan_outline="$4"

	initialize_react_state react_state "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
	action_json=""

	while ((react_state[step] < react_state[max_steps])); do
		current_step=$((react_state[step] + 1))

		select_next_action react_state action_json
		action_type="$(printf '%s' "${action_json}" | jq -r '.type // empty' 2>/dev/null || true)"
		tool="$(printf '%s' "${action_json}" | jq -r '.tool // empty' 2>/dev/null || true)"
		query="$(printf '%s' "${action_json}" | jq -r '.query // empty' 2>/dev/null || true)"

		if [[ "${action_type}" != "tool" ]]; then
			record_history react_state "$(printf 'Step %s unusable action: %s' "${current_step}" "${action_json}")"
			react_state[step]=${current_step}
			continue
		fi

		if ! validate_tool_permission react_state "${tool}"; then
			react_state[step]=${current_step}
			continue
		fi

		observation="$(execute_tool_action "${tool}" "${query}")"
		record_tool_execution react_state "${tool}" "${query}" "${observation}" "${current_step}"

		react_state[step]=${current_step}
		if [[ "${tool}" == "final_answer" ]]; then
			react_state[final_answer]="${observation}"
			break
		fi
	done

	finalize_react_result react_state
}
