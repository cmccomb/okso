#!/usr/bin/env bash
# shellcheck shell=bash
#
# Planning and execution helpers for the do assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/planner.sh}/planner.sh"
#
# Environment variables:
#   USER_QUERY (string): user-provided request for planning.
#   LLAMA_BIN (string): llama.cpp binary path.
#   MODEL_PATH (string): resolved GGUF path.
#   PLAN_ONLY, DRY_RUN (bool): control execution and preview behaviour.
#   APPROVE_ALL, FORCE_CONFIRM (bool): confirmation toggles.
#   VERBOSITY (int): log level.
#
# Dependencies:
#   - bash 5+
#   - optional llama.cpp binary
#
# Exit codes:
#   Functions return non-zero on misuse; fatal errors logged by caller.

# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/planner.sh}/logging.sh"
# shellcheck source=./tools.sh disable=SC1091
source "${BASH_SOURCE[0]%/planner.sh}/tools.sh"

build_ranking_prompt() {
	local user_query prompt tool
	user_query="$1"
	prompt="You are selecting tools to execute for a request. Respond with only the tools needed as lines in the format: tool=<name> score=<0-5> reason=<short justification>. Do not invent tools.\nRequest: ${user_query}\nAvailable tools:"

	for tool in "${TOOLS[@]}"; do
		prompt+=$(
			printf '\n- name=%s desc=%s safety=%s command=%s' \
				"${tool}" "${TOOL_DESCRIPTION[${tool}]}" "${TOOL_SAFETY[${tool}]}" "${TOOL_COMMAND[${tool}]}"
		)
	done

	printf '%s\n' "${prompt}"
}

parse_llama_ranking() {
	local raw_line tool score raw
	raw="$1"
	local results
	declare -A best_scores=()
	results=()

	while IFS= read -r raw_line; do
		if [[ "${raw_line}" =~ tool[=:\ ]*([a-zA-Z0-9_-]+)[[:space:]]+score[=:\ ]*([0-5]) ]]; then
			tool="${BASH_REMATCH[1]}"
			score="${BASH_REMATCH[2]}"
			if [[ -n "${TOOL_DESCRIPTION[${tool}]:-}" ]]; then
				if [[ -z "${best_scores[${tool}]:-}" || ${score} -gt ${best_scores[${tool}]} ]]; then
					best_scores[${tool}]="${score}"
				fi
			fi
		fi
	done <<<"${raw}"

	for tool in "${!best_scores[@]}"; do
		results+=("${best_scores[${tool}]}:${tool}")
	done

	if [[ ${#results[@]} -eq 0 ]]; then
		return 1
	fi

	printf '%s\n' "${results[@]}" | sort -r -n -t ':' -k1,1 | head -n 3
}

heuristic_rank_tools() {
	local user_query tool desc score lower_query is_note_intent
	user_query="$1"
	lower_query=${user_query,,}
	is_note_intent=false
	if [[ "${lower_query}" == *"note"* ]]; then
		is_note_intent=true
	fi
	local scores
	scores=()

        for tool in "${TOOLS[@]}"; do
                desc="${TOOL_DESCRIPTION[${tool}]}"
                score=1
                if [[ "${is_note_intent}" == true ]]; then
                        case "${tool}" in
                        notes_create)
                                score=5
                                ;;
                        notes_append | notes_search | notes_read | notes_list)
                                score=4
                                ;;
                        esac
                fi

                if [[ "${tool}" == "os_nav" && "${lower_query}" == *"list"* ]]; then
                        if [[ "${lower_query}" == *"file"* || "${lower_query}" == *"dir"* || "${lower_query}" == *"directory"* ]]; then
                                score=5
                        fi
                fi

                if [[ "${lower_query}" == *"${tool,,}"* ]]; then
                        score=5
                elif [[ "${desc,,}" == *"${lower_query}"* ]]; then
                        ((score < 4)) && score=4
                elif printf '%s' "${desc}" | grep -iq "${user_query}"; then
                        ((score < 3)) && score=3
                elif [[ "${TOOL_COMMAND[${tool}]}" == *"${user_query}"* ]]; then
                        ((score < 2)) && score=2
                fi
                scores+=("${score}:${tool}")
        done

	printf '%s\n' "${scores[@]}" | sort -r -n -t ':' -k1,1 | head -n 3
}

rank_tools() {
	local user_query prompt raw parsed
	user_query="$1"
	prompt="$(build_ranking_prompt "${user_query}")"

	if [[ "${LLAMA_AVAILABLE}" == true ]]; then
		raw="$(${LLAMA_BIN} -m "${MODEL_PATH}" -p "${prompt}" 2>/dev/null || true)"
		parsed="$(parse_llama_ranking "${raw}" || true)"
	fi

	if [[ -z "${parsed:-""}" ]]; then
		parsed="$(heuristic_rank_tools "${user_query}")"
	fi

	printf '%s\n' "${parsed}"
}

generate_tool_prompt() {
	local user_query ranked entry score tool prompt
	user_query="$1"
	ranked="$2"
	prompt="User request: ${user_query}. Suggested tools:"
	while IFS= read -r entry; do
		score="${entry%%:*}"
		tool="${entry##*:}"
		prompt+=$(
			printf ' %s(score=%s,desc=%s,safety=%s,cmd=%s),' \
				"${tool}" "${score}" "${TOOL_DESCRIPTION[${tool}]}" "${TOOL_SAFETY[${tool}]}" "${TOOL_COMMAND[${tool}]}"
		)
	done <<<"${ranked}"
	printf '%s\n' "${prompt%,}"
}

emit_plan_json() {
	local ranked entry score tool first description command safety
	ranked="$1"
	first=true

	printf '['
	while IFS= read -r entry; do
		[[ -z "${entry}" ]] && continue
		score="${entry%%:*}"
		tool="${entry##*:}"
		description="$(json_escape "${TOOL_DESCRIPTION[${tool}]}")"
		command="$(json_escape "${TOOL_COMMAND[${tool}]}")"
		safety="$(json_escape "${TOOL_SAFETY[${tool}]}")"
		if [[ "${first}" == true ]]; then
			first=false
		else
			printf ','
		fi
		printf '{"tool":"%s","score":%s,"command":"%s","description":"%s","safety":"%s"}' \
			"$(json_escape "${tool}")" "${score:-0}" "${command}" "${description}" "${safety}"
	done <<<"${ranked}"
	printf ']\n'
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

	printf 'Execute tool "%s"? [y/N]: ' "${tool_name}" >&2
	read -r reply
	if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
		log "WARN" "Tool execution declined" "${tool_name}"
		return 1
	fi
	return 0
}

execute_tool() {
	local tool_name handler
	tool_name="$1"
	handler="${TOOL_HANDLER[${tool_name}]}"
	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}"
		return 1
	fi

	if ! confirm_tool "${tool_name}"; then
		return 1
	fi

	if [[ "${DRY_RUN}" == true || "${PLAN_ONLY}" == true ]]; then
		log "INFO" "Skipping execution in preview mode" "${tool_name}"
		return 0
	fi

	TOOL_QUERY="${USER_QUERY:-}" ${handler}
}

collect_plan() {
	local ranked plan_prompt raw_plan
	ranked="$1"
	plan_prompt="Plan a concise sequence of tool uses to satisfy: ${USER_QUERY}. Candidates: ${ranked}."
	if [[ "${LLAMA_AVAILABLE}" == true ]]; then
		raw_plan="$(${LLAMA_BIN} -m "${MODEL_PATH}" -p "${plan_prompt}" 2>/dev/null || true)"
	else
		raw_plan="Use top-ranked tools sequentially: ${ranked}."
	fi
	printf '%s\n' "${raw_plan}"
}

planner_executor_loop() {
	local plan ranked entry tool summary plan_json
	ranked="$1"
	plan="$(collect_plan "${ranked}")"
	plan_json="$(emit_plan_json "${ranked}")"
	log "INFO" "Generated plan" "${plan}"

	if [[ "${PLAN_ONLY}" == true ]]; then
		printf '%s\n' "${plan_json}"
		return 0
	fi

	if [[ "${DRY_RUN}" == true ]]; then
		printf 'Dry run: planned tool calls (no execution).\n'
		printf '%s\n' "${plan_json}"
		return 0
	fi

	summary=""
	while IFS= read -r entry; do
		tool="${entry##*:}"
		if execute_tool "${tool}"; then
			summary+=$(printf '[%s executed] ' "${tool}")
		else
			summary+=$(printf '[%s skipped] ' "${tool}")
		fi
	done <<<"${ranked}"

	log "INFO" "Execution summary" "${summary}"
	printf '%s\n' "${summary}"
}
