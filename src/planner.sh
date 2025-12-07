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

MIN_TOOL_SCORE=${MIN_TOOL_SCORE:-3}

llama_infer() {
	# Runs llama.cpp with HF caching enabled for the configured model.
	local prompt
	prompt="$1"

	echo "${prompt}"

	"${LLAMA_BIN}" \
		--hf-repo "${MODEL_REPO}" \
		--hf-file "${MODEL_FILE}" \
		-no-cnv \
		-p "${prompt}" 2>/dev/null || true
}

build_ranking_prompt() {
	local user_query prompt tool
	user_query="$1"
	prompt=$'You are selecting tools to execute for a request. Respond ONLY with a JSON array of objects formatted as [{"tool":"name","score":0-5,"reason":"brief justification"}]. Do not invent tools.'
	prompt+=$'\nRequest: '${user_query}'\nAvailable tools:'

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
		score="${raw_line%%:*}"
		tool="${raw_line##*:}"
		if [[ -n "${TOOL_DESCRIPTION[${tool}]:-}" ]]; then
			if [[ -z "${best_scores[${tool}]:-}" || ${score} -gt ${best_scores[${tool}]} ]]; then
				best_scores[${tool}]="${score}"
			fi
		fi
	done < <(jq -r '.[] | select(.tool != null and .score != null) | (.score | tonumber) as $score | "\($score):\(.tool)"' <<<"${raw}" 2>/dev/null)

	for tool in "${!best_scores[@]}"; do
		results+=("${best_scores[${tool}]}:${tool}")
	done

	if [[ ${#results[@]} -eq 0 ]]; then
		return 1
	fi

	printf '%s\n' "${results[@]}" | sort -r -n -t ':' -k1,1 | head -n 3
}

filter_ranked_tools() {
	local ranked entry score filtered
	ranked="$1"
	filtered=()
	while IFS= read -r entry; do
		[[ -z "${entry}" ]] && continue
		score="${entry%%:*}"
		if ((score >= MIN_TOOL_SCORE)); then
			filtered+=("${entry}")
		fi
	done <<<"${ranked}"

	if [[ ${#filtered[@]} -eq 0 && -n "${ranked}" ]]; then
		filtered+=("${ranked%%$'\n'*}")
	fi

	printf '%s\n' "${filtered[@]}"
}

structured_tool_relevance() {
	# Arguments:
	#   $1 - user query (string)
	local user_query grammar tool_alternatives prompt raw
	user_query="$1"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		return 0
	fi

	tool_alternatives=""
	for tool in "${TOOLS[@]}"; do
		tool_alternatives+=$(printf '"%s" | ' "${tool}")
	done
	tool_alternatives="${tool_alternatives% | }"

	read -r -d '' grammar <<GRAM || true
root ::= "[" entries? "]"
entries ::= item ("," item)*
item ::= "{\\\"tool\\\":" tool_name ",\\\"relevant\\\":" bool "}"
tool_name ::= ${tool_alternatives}
bool ::= "true" | "false"
GRAM

	prompt="Identify which tools are relevant to the user request with true/false flags."
	prompt+=" User request: ${user_query}"

        raw="$(${LLAMA_BIN} \
                --hf-repo "${MODEL_REPO}" \
                --hf-file "${MODEL_FILE}" \
                --grammar "${grammar}" \
                -p "${prompt}" 2>/dev/null || true)"

	jq -r '.[] | select(.relevant == true and .tool != null) | "5:\(.tool)"' <<<"${raw}" 2>/dev/null || true
}

heuristic_rank_tools() {
	local user_query tool score lower_query has_shell_command has_backtick
	user_query="$1"
	lower_query=${user_query,,}
	has_backtick=false
	has_shell_command=false
	local threshold
	threshold=2

	declare -A best_scores=()

	if [[ "${user_query}" =~ \`[^\`]+\` ]]; then
		has_backtick=true
	fi

	if [[ "${lower_query}" =~ (^|[[:space:]])(ls|cd|cat|grep|find|pwd|rg)([[:space:]]|$) ]]; then
		has_shell_command=true
	fi

	while IFS= read -r entry; do
		[[ -z "${entry}" ]] && continue
		score="${entry%%:*}"
		tool="${entry##*:}"
		if [[ -z "${best_scores[${tool}]:-}" || ${score} -gt ${best_scores[${tool}]} ]]; then
			best_scores[${tool}]="${score}"
		fi
	done < <(structured_tool_relevance "${user_query}" || true)

	for tool in "${TOOLS[@]}"; do
		score=0

		case "${tool}" in
		terminal)
			if [[ "${has_backtick}" == true || "${has_shell_command}" == true ]]; then
				score=5
			elif [[ "${lower_query}" == *"list files"* || "${lower_query}" == *"show directory"* || "${lower_query}" == *"show folder"* || "${lower_query}" == *"grep"* || "${lower_query}" == *"find "* || "${lower_query}" == *"search files"* || "${lower_query}" == *"look around"* || "${lower_query}" == *"what's here"* || "${lower_query}" == *"folder"* ]]; then
				score=4
			elif [[ "${lower_query}" == *"file"* ]]; then
				score=3
			fi
			;;
		reminders_create)
			if [[ "${lower_query}" == *"remind me"* || "${lower_query}" == *"set a reminder"* || "${lower_query}" == *"add a reminder"* || "${lower_query}" == *"remember to"* ]]; then
				score=5
			elif [[ "${lower_query}" == *"reminder"* ]]; then
				score=3
			fi
			;;
		reminders_list)
			if [[ "${lower_query}" == *"show reminders"* || "${lower_query}" == *"list reminders"* || "${lower_query}" == *"what reminders"* ]]; then
				score=4
			fi
			;;
		*)
			if [[ "${lower_query}" == *"note"* || "${lower_query}" == *"notes"* || "${lower_query}" == *"write this down"* || "${lower_query}" == *"jot"* || "${lower_query}" == *"save this"* ]]; then
				case "${tool}" in
				notes_create)
					score=5
					;;
				notes_append | notes_search | notes_read | notes_list)
					score=4
					;;
				esac
			fi

			if [[ "${lower_query}" == *"${tool,,}"* ]]; then
				((score < 4)) && score=4
			fi
			;;
		esac

		if [[ ${score} -gt ${best_scores[${tool}]:-0} ]]; then
			best_scores[${tool}]="${score}"
		fi
	done

	local results
	results=()
	for tool in "${!best_scores[@]}"; do
		if ((best_scores[${tool}] >= threshold)); then
			results+=("${best_scores[${tool}]}:${tool}")
		fi
	done

	if [[ ${#results[@]} -eq 0 ]]; then
		return 0
	fi

	printf '%s\n' "${results[@]}" | sort -r -n -t ':' -k1,1 | head -n 3
}

rank_tools() {
	local user_query prompt raw parsed
	user_query="$1"
	prompt="$(build_ranking_prompt "${user_query}")"

	if [[ "${LLAMA_AVAILABLE}" == true ]]; then
		raw="$(llama_infer "${prompt}")"
		parsed="$(parse_llama_ranking "${raw}" || true)"
	fi

	if [[ -z "${parsed:-""}" ]]; then
		parsed="$(heuristic_rank_tools "${user_query}")"
	fi

	printf '%s\n' "$(filter_ranked_tools "${parsed}")"
}

generate_tool_prompt() {
	local user_query ranked entry score tool prompt
	user_query="$1"
	ranked="$2"
	prompt="User request: ${user_query}. Suggested tools:"
	if [[ -z "${ranked}" ]]; then
		printf 'User request: %s. Suggested tools: none.\n' "${user_query}"
		return
	fi
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

derive_tool_query() {
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - user query (string)
	local tool_name user_query lower_query
	tool_name="$1"
	user_query="$2"
	lower_query=${user_query,,}

	case "${tool_name}" in
	terminal)
		if [[ "${user_query}" =~ \`([^\`]+)\` ]]; then
			printf '%s\n' "${BASH_REMATCH[1]}"
			return
		fi

		if [[ "${lower_query}" == *"todo"* ]]; then
			printf 'rg -n "TODO" .\n'
			return
		fi

		if [[ "${lower_query}" == *"list files"* || "${lower_query}" == *"show directory"* || "${lower_query}" == *"show folder"* ]]; then
			printf 'ls -la\n'
			return
		fi

		if [[ "${user_query}" =~ (^|[[:space:]])(ls|cd|cat|grep|find|pwd|rg)([[:space:]]|$) ]]; then
			printf '%s\n' "${BASH_REMATCH[2]}"
			return
		fi

		printf 'status\n'
		;;
	reminders_create)
		if [[ "${lower_query}" == *"remind me to"* ]]; then
			printf '%s\n' "${user_query#*remind me to }"
			return
		fi
		if [[ "${lower_query}" == *"remind me"* ]]; then
			printf '%s\n' "${user_query#*remind me }"
			return
		fi
		printf '%s\n' "${user_query}"
		;;
	reminders_list)
		printf 'list\n'
		;;
	notes_create)
		if [[ "${lower_query}" == note* ]]; then
			printf '%s\n' "${user_query#note }"
			return
		fi
		printf '%s\n' "${user_query}"
		;;
	notes_append)
		printf '%s\n' "${user_query}"
		;;
	notes_search | notes_read | notes_list)
		printf '%s\n' "${user_query}"
		;;
	*)
		printf '%s\n' "${user_query}"
		;;
	esac
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

	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}"
		return 1
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
#	PROMPT
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
		jq -n --arg answer "$(respond_text "${user_query}" "")" '{type:"final", answer:$answer}'
	fi
}

react_loop() {
	local user_query ranked plan_entries max_steps allowed_tools history step action_json action_type tool query observation final_answer
	user_query="$1"
	ranked="$2"
	plan_entries="$3"
	max_steps=${MAX_STEPS:-6}
	allowed_tools="$(allowed_tool_list "${ranked}")"
	history=""
	step=0
	final_answer=""

	while ((step < max_steps)); do
		step=$((step + 1))

		if [[ "${LLAMA_AVAILABLE}" == true ]]; then
			action_json="$(llama_infer "$(build_react_prompt "${user_query}" "${allowed_tools}" "${history}")")"
		else
			action_json="$(fallback_action_from_plan "${plan_entries}" $((step - 1)) "${user_query}")"
		fi

		action_type="$(printf '%s' "${action_json}" | jq -r '.type // empty' 2>/dev/null)"
		tool="$(printf '%s' "${action_json}" | jq -r '.tool // empty' 2>/dev/null)"
		query="$(printf '%s' "${action_json}" | jq -r '.query // empty' 2>/dev/null)"

		if [[ "${action_type}" != "tool" && "${action_type}" != "final" ]]; then
			history+=$(printf 'Unusable action: %s\n' "${action_json}")
			continue
		fi

		if [[ "${action_type}" == "final" ]]; then
			final_answer="$(printf '%s' "${action_json}" | jq -r '.answer // ""')"
			break
		fi

		if ! grep -Fxq "${tool}" <<<"${allowed_tools}"; then
			history+=$(printf 'Tool %s not permitted.\n' "${tool}")
			continue
		fi

		observation="$(execute_tool_with_query "${tool}" "${query}")" || observation=""
		history+=$(printf 'Action %s query=%s\nObservation: %s\n' "${tool}" "${query}" "${observation}")
	done

	if [[ -z "${final_answer}" ]]; then
		final_answer="$(respond_text "${user_query}" "${history}")"
	fi

	printf '%s\n' "${final_answer}"
	if [[ -z "${history}" ]]; then
		printf 'Execution summary: no actions executed.\n'
	else
		printf 'Execution summary:\n%s\n' "${history}"
	fi
}
