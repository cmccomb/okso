#!/usr/bin/env bash
# shellcheck shell=bash
#
# Intent recognition helpers for the okso planner.
#
# Usage:
#   source "${BASH_SOURCE[0]%/intent.sh}/intent.sh"
#
# Environment variables:
#   INTENT_MODEL_REPO (string): Hugging Face repository name for intent inference.
#   INTENT_MODEL_FILE (string): model file within the repository for intent inference.
#   INTENT_CACHE_FILE (string): prompt cache file for intent llama.cpp calls.
#   INTENT_MAX_OUTPUT_TOKENS (int >=1): llama.cpp generation budget for intent inference.
#   INTENT_CONFIDENCE_MIN (float 0-1): minimum confidence required to enforce tool filtering.
#   INTENT_DISABLE_SEARCH (bool): when true, skip pre-planner search regardless of intent.
#   LLAMA_AVAILABLE (bool): whether llama.cpp can run locally.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - llama.cpp (optional)
#
# Exit codes:
#   Functions return non-zero on validation errors.

PLANNING_INTENT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${PLANNING_INTENT_DIR}/../core/logging.sh"
# shellcheck source=src/lib/llm/templates.sh
source "${PLANNING_INTENT_DIR}/../llm/templates.sh"
# shellcheck source=src/lib/llm/schema.sh
source "${PLANNING_INTENT_DIR}/../llm/schema.sh"
# shellcheck source=src/lib/llm/llama_client.sh
source "${PLANNING_INTENT_DIR}/../llm/llama_client.sh"

intent_schema_text() {
	# Loads the intent JSON schema as a single line.
	# Returns:
	#   schema JSON text (string)
	load_schema_text intent 2>/dev/null || true
}

render_intent_prompt() {
	# Renders the intent prompt with the user query embedded.
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   rendered prompt on stdout; non-zero on failure.
	local user_query schema_json
	user_query="$1"
	schema_json="$(intent_schema_text)"

	render_prompt_template "intent" USER_QUERY "${user_query}" INTENT_SCHEMA "${schema_json}"
}

intent_fallback_json() {
	# Returns a deterministic fallback intent payload.
	# Arguments:
	#   $1 - intent label (string)
	#   $2 - confidence (string/float)
	#   $3 - rationale (string)
	# Returns:
	#   JSON object on stdout.
	local intent_label confidence rationale
	intent_label="$1"
	confidence="$2"
	rationale="$3"

	jq -nc \
		--arg intent "${intent_label}" \
		--arg rationale "${rationale}" \
		--argjson confidence "${confidence}" \
		'{intent:$intent, confidence:$confidence, rationale:$rationale}'
}

lowercase_intent() {
	# Lowercases a string for deterministic matching.
	# Arguments:
	#   $1 - input string
	# Returns:
	#   lowercase string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

intent_keyword_match() {
	# Heuristic intent matcher for deterministic fallback.
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   JSON intent payload on stdout.
	local query_lower
	query_lower="$(lowercase_intent "$1")"

	if [[ "${query_lower}" == *"reminder"* || "${query_lower}" == *"remind"* ]]; then
		intent_fallback_json "reminders" 0.4 "Heuristic match: reminders keywords"
		return 0
	fi

	if [[ "${query_lower}" == *"note"* || "${query_lower}" == *"notes"* ]]; then
		intent_fallback_json "notes" 0.4 "Heuristic match: notes keywords"
		return 0
	fi

	if [[ "${query_lower}" == *"calendar"* || "${query_lower}" == *"event"* ]]; then
		intent_fallback_json "calendar" 0.4 "Heuristic match: calendar keywords"
		return 0
	fi

	if [[ "${query_lower}" == *"email"* || "${query_lower}" == *"mail"* ]]; then
		intent_fallback_json "mail" 0.4 "Heuristic match: mail keywords"
		return 0
	fi

	if [[ "${query_lower}" == *"search"* || "${query_lower}" == *"web"* || "${query_lower}" == *"lookup"* ]]; then
		intent_fallback_json "web_research" 0.4 "Heuristic match: web keywords"
		return 0
	fi

	if [[ "${query_lower}" == *"calculate"* || "${query_lower}" == *"compute"* || "${query_lower}" == *"sum"* ]]; then
		intent_fallback_json "math" 0.4 "Heuristic match: math keywords"
		return 0
	fi

	if [[ "${query_lower}" == *"code"* || "${query_lower}" == *"refactor"* || "${query_lower}" == *"implement"* ]]; then
		intent_fallback_json "coding" 0.4 "Heuristic match: coding keywords"
		return 0
	fi

	if [[ "${query_lower}" == *"file"* || "${query_lower}" == *"directory"* || "${query_lower}" == *"folder"* ]]; then
		intent_fallback_json "filesystem" 0.4 "Heuristic match: filesystem keywords"
		return 0
	fi

	intent_fallback_json "general" 0.0 "No heuristic match"
}

recognize_intent() {
	# Classifies the user query into a canonical intent.
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   intent JSON payload on stdout.
	local user_query prompt raw schema_json max_generation_tokens cache_file
	user_query="$1"

	if [[ -z "${user_query}" ]]; then
		intent_fallback_json "general" 0.0 "Empty user query"
		return 0
	fi

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		intent_keyword_match "${user_query}"
		return 0
	fi

	max_generation_tokens=${INTENT_MAX_OUTPUT_TOKENS:-256}
	if ! [[ "${max_generation_tokens}" =~ ^[0-9]+$ ]] || ((max_generation_tokens < 1)); then
		max_generation_tokens=256
	fi

	prompt="$(render_intent_prompt "${user_query}")" || {
		log "ERROR" "Failed to render intent prompt" "intent_prompt_render_failed" >&2
		intent_keyword_match "${user_query}"
		return 0
	}

	schema_json="$(intent_schema_text)"
	cache_file="${INTENT_CACHE_FILE:-${OKSO_INTENT_CACHE_FILE:-${OKSO_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/okso}}/intent.prompt-cache}"

	if ! raw="$(LLAMA_TEMPERATURE=0.0 llama_infer "${prompt}" '' "${max_generation_tokens}" "${schema_json}" "${INTENT_MODEL_REPO:-}" "${INTENT_MODEL_FILE:-}" "${cache_file}" "${prompt}")"; then
		log "WARN" "Intent model invocation failed; falling back" "intent_infer_failed" >&2
		intent_keyword_match "${user_query}"
		return 0
	fi

	if ! jq -e '.intent and .confidence and .rationale' <<<"${raw}" >/dev/null 2>&1; then
		log "WARN" "Intent output invalid; falling back" "intent_parse_failed" >&2
		intent_keyword_match "${user_query}"
		return 0
	fi

	printf '%s' "${raw}"
}

intent_requires_search() {
	# Determines whether pre-planner web search should run.
	# Arguments:
	#   $1 - intent JSON payload (string)
	# Returns:
	#   0 if search should run; 1 if search should be skipped.
	local intent_json intent_label
	intent_json="$1"

	if [[ "${INTENT_DISABLE_SEARCH:-false}" == true ]]; then
		return 1
	fi

	if [[ -z "${intent_json}" ]]; then
		return 0
	fi

	intent_label="$(jq -r '.intent // ""' <<<"${intent_json}" 2>/dev/null)"
	if [[ -z "${intent_label}" ]]; then
		return 0
	fi

	case "${intent_label}" in
	web_research | general)
		return 0
		;;
	notes | reminders | calendar | mail | filesystem | coding | math)
		return 1
		;;
	*)
		return 0
		;;
	esac
}

intent_group_for_intent() {
	# Maps intent labels to newline-delimited tool group names.
	# Arguments:
	#   $1 - intent label (string)
	# Returns:
	#   tool group names on stdout.
	case "$1" in
	web_research)
		printf '%s\n' "web"
		;;
	notes)
		printf '%s\n' "notes"
		;;
	reminders)
		printf '%s\n' "reminders"
		;;
	calendar)
		printf '%s\n' "calendar"
		;;
	mail)
		printf '%s\n' "mail"
		;;
	filesystem)
		printf '%s\n' "filesystem"
		;;
	coding)
		printf '%s\n' "coding"
		;;
	math)
		printf '%s\n' "math"
		;;
	*)
		printf '%s\n' "general"
		;;
	esac
}

intent_tool_matches_group() {
	# Determines if a tool name belongs to a group.
	# Arguments:
	#   $1 - tool group (string)
	#   $2 - tool name (string)
	# Returns:
	#   0 if the tool matches; 1 otherwise.
	local group tool
	group="$1"
	tool="$2"

	case "${group}" in
	general)
		return 0
		;;
	web)
		[[ "${tool}" == "web_search" || "${tool}" == "web_fetch" ]]
		;;
	notes)
		[[ "${tool}" == notes_* ]]
		;;
	reminders)
		[[ "${tool}" == reminders_* ]]
		;;
	calendar)
		[[ "${tool}" == calendar_* ]]
		;;
	mail)
		[[ "${tool}" == mail_* ]]
		;;
	filesystem)
		[[ "${tool}" == "terminal" || "${tool}" == files_* ]]
		;;
	coding)
		[[ "${tool}" == "terminal" || "${tool}" == files_* || "${tool}" == "python_repl" ]]
		;;
	math)
		[[ "${tool}" == "python_repl" ]]
		;;
	*)
		return 1
		;;
	esac
}

intent_to_tools() {
	# Converts an intent payload into a newline-delimited tool list.
	# Arguments:
	#   $1 - intent JSON payload (string)
	# Returns:
	#   tool names on stdout.
	local intent_json intent_label confidence tool_groups confidence_min
	local -a available_tools selected_groups selected_tools
	intent_json="$1"

	confidence_min="${INTENT_CONFIDENCE_MIN:-0.45}"

	while IFS= read -r tool_name; do
		[[ -z "${tool_name}" ]] && continue
		available_tools+=("${tool_name}")
	done < <(tool_names)

	if [[ -z "${intent_json}" ]]; then
		printf '%s\n' "${available_tools[@]}"
		return 0
	fi

	intent_label="$(jq -r '.intent // ""' <<<"${intent_json}" 2>/dev/null)"
	confidence="$(jq -r '.confidence // "0"' <<<"${intent_json}" 2>/dev/null)"

	if [[ -z "${intent_label}" ]]; then
		printf '%s\n' "${available_tools[@]}"
		return 0
	fi

	if ! awk -v score="${confidence}" -v min="${confidence_min}" 'BEGIN { exit !(score >= min) }'; then
		log "INFO" "Intent confidence below threshold; using full tool list" "intent=${intent_label},confidence=${confidence},min=${confidence_min}" >&2
		printf '%s\n' "${available_tools[@]}"
		return 0
	fi

	if jq -e '.tool_groups and (.tool_groups | length > 0)' <<<"${intent_json}" >/dev/null 2>&1; then
		while IFS= read -r group; do
			[[ -z "${group}" ]] && continue
			selected_groups+=("${group}")
		done < <(jq -r '.tool_groups[]' <<<"${intent_json}" 2>/dev/null)
	else
		while IFS= read -r group; do
			[[ -z "${group}" ]] && continue
			selected_groups+=("${group}")
		done < <(intent_group_for_intent "${intent_label}")
	fi

	for group in "${selected_groups[@]}"; do
		for tool in "${available_tools[@]}"; do
			if intent_tool_matches_group "${group}" "${tool}"; then
				selected_tools+=("${tool}")
			fi
		done
	done

	if [[ ${#selected_tools[@]} -eq 0 ]]; then
		printf '%s\n' "${available_tools[@]}"
		return 0
	fi

	if [[ " ${selected_tools[*]} " != *" final_answer "* ]]; then
		selected_tools+=("final_answer")
	fi

	printf '%s\n' "${selected_tools[@]}" | awk 'NF && !seen[$0]++'
}

export -f recognize_intent
export -f intent_to_tools
export -f intent_requires_search
export -f render_intent_prompt
