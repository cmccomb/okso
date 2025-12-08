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

        if [[ ${VERBOSITY:-1} -ge 2 ]]; then
                printf '%s\n' "${raw}" >&2
        fi

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

allowed_tool_list() {
        local ranked entry tool
        ranked="$1"
        local includes_final_answer=false
        while IFS= read -r entry; do
                [[ -z "${entry}" ]] && continue
                tool="${entry##*:}"
                printf '%s\n' "${tool}"
                if [[ "${tool}" == "final_answer" ]]; then
                        includes_final_answer=true
                fi
        done <<<"${ranked}"

        if [[ "${includes_final_answer}" != true ]]; then
                printf 'final_answer\n'
        fi
}

build_plan_outline() {
        # Arguments:
        #   $1 - ranked plan entries (tool|query|score per line)
        local plan_entries index tool query outline_line
        plan_entries="$1"
        index=1
        while IFS='|' read -r tool query _score; do
                [[ -z "${tool}" ]] && continue
                outline_line=$(printf '%d. %s -> %s' "${index}" "${tool}" "${query}")
                printf '%s\n' "${outline_line}"
                index=$((index + 1))
        done <<<"${plan_entries}"
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
        state_ref[plan_outline]="$(build_plan_outline "${4}")"
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
        local user_query ranked plan_entries allowed_tools action_json action_type tool query observation current_step
        declare -A react_state
        user_query="$1"
        ranked="$2"
        plan_entries="$3"
        allowed_tools="$(allowed_tool_list "${ranked}")"

        initialize_react_state react_state "${user_query}" "${allowed_tools}" "${plan_entries}"
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
