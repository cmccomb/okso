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

structured_tool_relevance() {
	# Arguments:
	#   $1 - user query (string)
	local user_query grammar tool_alternatives prompt raw
	local -a relevant_tools
	declare -A relevance_map=()
	user_query="$1"

	# I had to comment this out in order to get this to run outsid eof a test environment. Weird.
	#	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
	#		return 0
	#	fi

	tool_alternatives=""
	for tool in "${TOOLS[@]}"; do
		tool_alternatives+=$(printf '"%s" | ' "${tool}")
	done
	tool_alternatives="${tool_alternatives% | }"

	read -r -d '' grammar <<GRAM || true
root ::= "{" ws entries? ws "}"
entries ::= pair (ws "," ws pair)*
pair ::= tool-key ws ":" ws bool

tool-key ::= "\"" tool-name "\""
tool-name ::= ${tool_alternatives}

bool ::= "true" | "false"
ws ::= [ \t\n\r]*
GRAM

	prompt="Return a compact JSON map of tool relevance using boolean flags based on their relevance for addressing the query from the user. The available tools are: \n"
	for tool in "${TOOLS[@]}"; do
		prompt+=$(printf '%s ' "- ${tool}\n")
	done
	prompt+="\n\nUser request: ${user_query}"

	log "INFO" "Structured tool relevance prompt:" "${prompt}" >&2

	raw="$(${LLAMA_BIN} \
		--hf-repo "${MODEL_REPO}" \
		--hf-file "${MODEL_FILE}" \
		-no-cnv --simple-io \
		--no-display-prompt \
		--repeat-penalty 1.5 \
		--grammar "${grammar}" \
		-p "${prompt}" 2>/dev/null || true)" #
	echo "${raw}" >&2

	mapfile -t relevant_tools < <(jq -r '
                if type == "array" then
                        .[] | select(.relevant == true and .tool != null) | "\(.tool)"
                elif type == "object" then
                        to_entries[] | select(.value == true) | "\(.key)"
                else
                        empty
                end
        ' <<<"${raw}" 2>/dev/null || true)

	for tool in "${relevant_tools[@]}"; do
		relevance_map["${tool}"]=true
	done

	for tool in "${TOOLS[@]}"; do
		if [[ -n "${relevance_map[${tool}]:-}" ]]; then
			printf '5:%s\n' "${tool}"
		fi
	done
}

rank_tools() {
	local user_query
	user_query="$1"

	# Had to comment this out to get it to run outside of a test enviornment
	#	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
	#		log "WARN" "llama.cpp binary unavailable; skipping tool selection" "${LLAMA_BIN}" >&2
	#		return 0
	#	fi

	structured_tool_relevance "${user_query}"
	return $?
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

build_plan_entries() {
	local ranked user_query entry score tool plan query
	ranked="$1"
	user_query="$2"
	plan=""

	while IFS= read -r entry; do
		[[ -z "${entry}" ]] && continue
		score="${entry%%:*}"
		tool="${entry##*:}"
		query="$(derive_tool_query "${tool}" "${user_query}")"
		plan+="${tool}|${query}|${score}"$'\n'
	done <<<"${ranked}"

	printf '%s' "${plan}"
}

execute_tool_with_query() {
	local tool_name tool_query handler output status
	tool_name="$1"
	tool_query="$2"
	handler="${TOOL_HANDLER[${tool_name}]}"

	local requires_confirmation
	requires_confirmation=false
	if should_prompt_for_tool; then
		requires_confirmation=true
	fi

	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}"
		return 1
	fi

	if [[ "${requires_confirmation}" == true ]]; then
		log "INFO" "Requesting tool confirmation" "$(printf 'tool=%s query=%s' "${tool_name}" "${tool_query}")"
	fi

	if ! confirm_tool "${tool_name}"; then
		printf 'Declined %s\n' "${tool_name}"
		return 0
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
	local user_query allowed_tools history tool_lines
	user_query="$1"
	allowed_tools="$2"
	history="$3"

	tool_lines="Allowed tools:"
	while IFS= read -r tool; do
		tool_lines+=$(printf '\n- %s: %s (example query: %s)' "${tool}" "${TOOL_DESCRIPTION[${tool}]}" "${TOOL_COMMAND[${tool}]}")
	done <<<"${allowed_tools}"

	cat <<PROMPT
You are an assistant that can take iterative actions. Respond ONLY with a single JSON object on each turn.
Action schema:
- To use a tool: {"type":"tool","tool":"<tool_name>","query":"<specific command>"}
- To finish: {"type":"final","answer":"<concise reply>"}
Use tools only when necessary. Provide concrete tool queries, not general requests. If no tools are needed, return type=final.
User request: ${user_query}
${tool_lines}
Previous steps:
${history}
PROMPT
}

allowed_tool_list() {
	local ranked entry tool
	ranked="$1"
	while IFS= read -r entry; do
		[[ -z "${entry}" ]] && continue
		tool="${entry##*:}"
		printf '%s\n' "${tool}"
	done <<<"${ranked}"
}

fallback_action_from_plan() {
	local plan_entries step_index user_query
	plan_entries=()
	while IFS= read -r line; do
		plan_entries+=("${line}")
	done <<<"$1"
	step_index=$2
	user_query="$3"
	if ((step_index < ${#plan_entries[@]})); then
		IFS='|' read -r tool query score <<<"${plan_entries[${step_index}]}"
		jq -n --arg tool "${tool}" --arg query "${query}" '{type:"tool", tool:$tool, query:$query}'
	else
		jq -n --arg answer "$(respond_text "${user_query}" 1000)" '{type:"final", answer:$answer}'
	fi
}

initialize_react_state() {
	# Arguments:
	#   $1 - name of associative array to populate
	#   $2 - user query
	#   $3 - allowed tools (newline delimited)
	#   $4 - ranked plan entries
	local -n state_ref=$1
	state_ref[user_query]="$2"
	state_ref[allowed_tools]="$3"
	state_ref[plan_entries]="$4"
	state_ref[history]=""
	state_ref[step]=0
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
	local -n state_ref=$1
	local react_prompt
	if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
		react_prompt="$(build_react_prompt "${state_ref[user_query]}" "${state_ref[allowed_tools]}" "${state_ref[history]}")"
		llama_infer "${react_prompt}"
		return
	fi

	fallback_action_from_plan "${state_ref[plan_entries]}" $((state_ref[step] - 1)) "${state_ref[user_query]}"
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
	local state_name
	local -n state_ref=$1
	local tool query observation
	state_name="$1"
	tool="$2"
	query="$3"
	observation="$4"
	record_history "${state_name}" "$(printf 'Action %s query=%s\nObservation: %s' "${tool}" "${query}" "${observation}")"
}

finalize_react_result() {
	# Arguments:
	#   $1 - name of associative array holding state
	local -n state_ref=$1
	if [[ -z "${state_ref[final_answer]}" ]]; then
		state_ref[final_answer]="$(respond_text "${state_ref[user_query]} ${state_ref[history]}" 1000)"
	fi

	printf '%s\n' "${state_ref[final_answer]}"
	if [[ -z "${state_ref[history]}" ]]; then
		printf 'Execution summary: no tool runs.\n'
	else
		printf 'Execution summary:\n%s\n' "${state_ref[history]}"
	fi
}

react_loop() {
	local user_query ranked plan_entries allowed_tools action_json action_type tool query observation
	declare -A react_state
	user_query="$1"
	ranked="$2"
	plan_entries="$3"
	allowed_tools="$(allowed_tool_list "${ranked}")"

	initialize_react_state react_state "${user_query}" "${allowed_tools}" "${plan_entries}"

	while ((react_state[step] < react_state[max_steps])); do
		react_state[step]=$((react_state[step] + 1))

		action_json="$(select_next_action react_state)"
		action_type="$(printf '%s' "${action_json}" | jq -r '.type // empty' 2>/dev/null || true)"
		tool="$(printf '%s' "${action_json}" | jq -r '.tool // empty' 2>/dev/null || true)"
		query="$(printf '%s' "${action_json}" | jq -r '.query // empty' 2>/dev/null || true)"

		if [[ "${action_type}" != "tool" && "${action_type}" != "final" ]]; then
			record_history react_state "$(printf 'Unusable action: %s' "${action_json}")"
			continue
		fi

		if [[ "${action_type}" == "final" ]]; then
			react_state[final_answer]="$(printf '%s' "${action_json}" | jq -r '.answer // ""')"
			break
		fi

		if ! validate_tool_permission react_state "${tool}"; then
			continue
		fi

		observation="$(execute_tool_action "${tool}" "${query}")"
		record_tool_execution react_state "${tool}" "${query}" "${observation}"
	done

	finalize_react_result react_state
}
