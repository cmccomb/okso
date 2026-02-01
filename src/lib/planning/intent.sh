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
# shellcheck source=src/lib/workflows/loader.sh
source "${PLANNING_INTENT_DIR}/../workflows/loader.sh"

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
	#   $3 - rationale (string)
	# Returns:
	#   JSON object on stdout.
	local intent_label rationale
	intent_label="$1"
	rationale="$2"

	jq -nc \
		--arg intent "${intent_label}" \
		--arg rationale "${rationale}" \
		'{intents:[$intent], rationale:$rationale}'
}

lowercase_intent() {
	# Lowercases a string for deterministic matching.
	# Arguments:
	#   $1 - input string
	# Returns:
	#   lowercase string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

recognize_intent() {
	# Classifies the user query into a canonical intent.
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   intent JSON payload on stdout.
	local user_query prompt raw schema_json max_generation_tokens cache_file model_repo model_file
	user_query="$1"

	max_generation_tokens=${INTENT_MAX_OUTPUT_TOKENS:-256}
	if ! [[ "${max_generation_tokens}" =~ ^[0-9]+$ ]] || ((max_generation_tokens < 1)); then
		max_generation_tokens=256
	fi

	prompt="$(render_intent_prompt "${user_query}")" || {
		log "ERROR" "Failed to render intent prompt" "intent_prompt_render_failed" >&2
		return 0
	}

	schema_json="$(intent_schema_text)"
	cache_file="${INTENT_CACHE_FILE:-${OKSO_INTENT_CACHE_FILE:-${OKSO_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/okso}}/intent.prompt-cache}"
	model_repo="${INTENT_MODEL_REPO:-${PLANNER_MODEL_REPO:-}}"
	model_file="${INTENT_MODEL_FILE:-${PLANNER_MODEL_FILE:-}}"

	if ! raw="$(LLAMA_TEMPERATURE=0.0 llama_infer "${prompt}" '' "${max_generation_tokens}" "${schema_json}" "${model_repo}" "${model_file}" "${cache_file}" "${prompt}")"; then
		log "WARN" "Intent model invocation failed; falling back" "intent_infer_failed" >&2
		return 0
	fi

	if ! jq -e '.intents and (.intents | length > 0) and .rationale' <<<"${raw}" >/dev/null 2>&1; then
		log "WARN" "Intent output invalid; falling back" "intent_parse_failed" >&2
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
	local intent_json
	intent_json="$1"

	if [[ "${INTENT_DISABLE_SEARCH:-false}" == true ]]; then
		return 1
	fi

	if [[ -z "${intent_json}" ]]; then
		return 0
	fi

	if jq -e '.intents and (.intents | length > 0)' <<<"${intent_json}" >/dev/null 2>&1; then
		if jq -e '.intents[] | select(. == "web" or . == "general")' <<<"${intent_json}" >/dev/null 2>&1; then
			return 0
		fi
		if jq -e '.intents[] | select(. != "notes" and . != "reminders" and . != "calendar" and . != "mail" and . != "filesystem" and . != "coding" and . != "math")' <<<"${intent_json}" >/dev/null 2>&1; then
			return 0
		fi
		return 1
	fi
	intent_label="$(jq -r '.intent // ""' <<<"${intent_json}" 2>/dev/null)"
	if [[ -z "${intent_label}" ]]; then
		return 0
	fi

	case "${intent_label}" in
	web | general)
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
	web)
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

	if [[ "${tool}" == workflow_* ]]; then
		local workflow_name workflow_intents
		workflow_name="${tool#workflow_}"
		workflow_intents="$(workflow_intents_for_name "${workflow_name}")"
		if jq -e --arg group "${group}" '.[]? == $group' <<<"${workflow_intents}" >/dev/null 2>&1; then
			return 0
		fi
		return 1
	fi

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
		[[ "${tool}" == "terminal" || "${tool}" == file_* ]]
		;;
	coding)
		[[ "${tool}" == "terminal" || "${tool}" == file_* || "${tool}" == "python_repl" ]]
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
	local intent_json intent_label
	local -a available_tools selected_groups selected_tools
	intent_json="$1"

	while IFS= read -r tool_name; do
		[[ -z "${tool_name}" ]] && continue
		available_tools+=("${tool_name}")
	done < <(tool_names)

	if [[ -z "${intent_json}" ]]; then
		printf '%s\n' "${available_tools[@]}"
		return 0
	fi

	if jq -e '.intents and (.intents | length > 0)' <<<"${intent_json}" >/dev/null 2>&1; then
		while IFS= read -r intent_label; do
			[[ -z "${intent_label}" ]] && continue
			while IFS= read -r group; do
				[[ -z "${group}" ]] && continue
				selected_groups+=("${group}")
			done < <(intent_group_for_intent "${intent_label}")
		done < <(jq -r '.intents[]' <<<"${intent_json}" 2>/dev/null)
	else
		intent_label="$(jq -r '.intent // ""' <<<"${intent_json}" 2>/dev/null)"
		if [[ -z "${intent_label}" ]]; then
			printf '%s\n' "${available_tools[@]}"
			return 0
		fi
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

format_intent_context() {
	# Formats intent JSON for logging.
	# Arguments:
	#   $1 - intent JSON payload (string)
	#   $2 - planner tool list (newline-delimited string)
	# Returns:
	#   formatted string on stdout.

	local intent_json planner_tools
	intent_json="$1"
	planner_tools="$2"

	# Extract fields
	local rationale intents tools
	rationale="$(jq -r '.rationale // "No rationale provided"' <<<"${intent_json}" 2>/dev/null)"
	intents="$(jq -r '.intents // [] | join(", ")' <<<"${intent_json}" 2>/dev/null)"
	tools="$(printf '%s\n' "${planner_tools}" | paste -sd ',' -)"

	# Format output
	printf 'Rationale: %s\nIntents: %s\nEnabled Tools: %s' "${rationale}" "${intents}" "${tools}"
}

export -f recognize_intent
export -f intent_to_tools
export -f intent_requires_search
export -f render_intent_prompt
export -f format_intent_context
