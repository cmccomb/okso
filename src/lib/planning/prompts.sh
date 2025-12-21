#!/usr/bin/env bash
# shellcheck shell=bash
#
# Prompt builders for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/prompts.sh}/prompts.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 3.2+
#
# Exit codes:
#   Functions print prompts and return 0 on success.

PLANNING_PROMPTS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROMPTS_DIR="${PLANNING_PROMPTS_DIR%/lib/planning}/prompts"

# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_PROMPTS_DIR}/../core/logging.sh"

# shellcheck source=./schema.sh disable=SC1091
source "${PLANNING_PROMPTS_DIR}/schema.sh"

load_prompt_template() {
	# Loads a prompt template from the prompts directory.
	# Arguments:
	#   $1 - prompt name (string)
	# Returns:
	#   The content of the prompt template (string).
	local prompt_name prompt_path
	prompt_name="$1"
	prompt_path="${PROMPTS_DIR}/${prompt_name}.txt"

	if [[ ! -f "${prompt_path}" ]]; then
		log "ERROR" "prompt template missing" "${prompt_path}" || true
		return 1
	fi

	cat "${prompt_path}"
}

render_prompt_template() {
	# Renders a prompt template by substituting key/value pairs.
	# Arguments:
	#   $1 - prompt name (string)
	#   $@ - alternating keys and values for substitution (string)
	# Returns:
	#   The rendered prompt text (string).
	local prompt_name prompt_text
	local -a substitutions=()

	prompt_name="$1"
	shift
	prompt_text="$(load_prompt_template "${prompt_name}")" || return 1

	if (($# % 2 != 0)); then
		log "ERROR" "render_prompt_template expects substitution pairs" "args_count=$#" || true
		return 1
	fi

	while (($# > 0)); do
		local key value
		key="$1"
		value="$2"
		substitutions+=("${key}=${value}")
		shift 2
	done

	if ((${#substitutions[@]} == 0)); then
		printf '%s' "${prompt_text}"
		return 0
	fi

	env "${substitutions[@]}" envsubst <<<"${prompt_text}"
}

build_final_answer_fallback_prompt() {
	# Builds a prompt for summarizing a final answer from prior agent context.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - context (string, optional)
	# Returns:
	#   The full prompt text (string).
	local user_query context final_fallback_schema current_date current_time current_weekday
	user_query="$1"
	context="${2:-}"
	final_fallback_schema="$(load_schema_text concise_response)"
	current_date="$(date -u '+%Y-%m-%d')"
	current_time="$(date -u '+%H:%M:%S')"
	current_weekday="$(date -u '+%A')"

	render_prompt_template "final_answer_fallback" \
		user_query "${user_query}" \
		context "${context}" \
		final_fallback_schema "${final_fallback_schema}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}"
}

build_planner_prompt_static_prefix() {
	# Returns the deterministic planner prompt prefix that excludes runtime fields.
	local template anchor
	template="$(load_prompt_template "planner")" || return 1
	anchor="\${current_date}"

	if [[ "${template}" != *"${anchor}"* ]]; then
		printf '%s' "${template}"
		return 0
	fi

	printf '%s' "${template%%"${anchor}"*}"
}

build_planner_prompt_dynamic_suffix() {
	# Builds the runtime portion of the planner prompt.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted tool descriptions (string)
	# Returns:
	#   The dynamic suffix for the planner prompt (string).
	local user_query tool_lines planner_schema current_date current_time current_weekday rendered prefix
	user_query="$1"
	tool_lines="$2"
	planner_schema="$(load_schema_text planner_plan)"
	current_date="$(date -u '+%Y-%m-%d')"
	current_time="$(date -u '+%H:%M:%S')"
	current_weekday="$(date -u '+%A')"

	rendered="$(render_prompt_template "planner" \
		user_query "${user_query}" \
		tool_lines "${tool_lines}" \
		planner_schema "${planner_schema}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}")"
	prefix="$(build_planner_prompt_static_prefix)" || return 1
	printf '%s' "${rendered#"${prefix}"}"
}

build_planner_prompt() {
	# Builds a prompt for the high-level planner.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted tool descriptions (string)
	# Returns:
	#   The full prompt text (string).
	local prefix suffix
	prefix="$(build_planner_prompt_static_prefix)" || return 1
	suffix="$(build_planner_prompt_dynamic_suffix "$1" "$2")" || return 1
	printf '%s%s' "${prefix}" "${suffix}"
}

build_react_prompt_static_prefix() {
	# Returns the deterministic ReAct prompt prefix that excludes runtime fields.
	local template anchor
	template="$(load_prompt_template "react")" || return 1
	anchor="\${current_date}"

	if [[ "${template}" != *"${anchor}"* ]]; then
		printf '%s' "${template}"
		return 0
	fi

	printf '%s' "${template%%"${anchor}"*}"
}

build_react_prompt_dynamic_suffix() {
	# Builds the runtime portion of the ReAct execution prompt.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted allowed tool descriptions (string)
	#   $3 - high-level plan outline (string)
	#   $4 - prior interaction history (string)
	#   $5 - JSON schema describing allowed ReAct actions (string)
	#   $6 - current plan step guidance (string)
	# Returns:
	#   The dynamic suffix for the ReAct prompt (string).
	local user_query allowed_tools plan_outline history react_schema plan_step current_date current_time current_weekday
	local rendered prefix
	user_query="$1"
	allowed_tools="$2"
	plan_outline="$3"
	history="$4"
	react_schema="$5"
	plan_step="$6"
	current_date="$(date -u '+%Y-%m-%d')"
	current_time="$(date -u '+%H:%M:%S')"
	current_weekday="$(date -u '+%A')"

	rendered="$(render_prompt_template "react" \
		user_query "${user_query}" \
		allowed_tools "${allowed_tools}" \
		plan_outline "${plan_outline}" \
		history "${history}" \
		react_schema "${react_schema}" \
		plan_step "${plan_step}" \
		current_date "${current_date}" \
		current_time "${current_time}" \
		current_weekday "${current_weekday}")"
	prefix="$(build_react_prompt_static_prefix)" || return 1
	printf '%s' "${rendered#"${prefix}"}"
}

build_react_prompt() {
	# Builds a prompt for the ReAct execution loop.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted allowed tool descriptions (string)
	#   $3 - high-level plan outline (string)
	#   $4 - prior interaction history (string)
	#   $5 - JSON schema describing allowed ReAct actions (string)
	#   $6 - current plan step guidance (string)
	# Returns:
	#   The full prompt text (string).
	local prefix suffix
	prefix="$(build_react_prompt_static_prefix)" || return 1
	suffix="$(build_react_prompt_dynamic_suffix "$1" "$2" "$3" "$4" "$5" "$6")" || return 1
	printf '%s%s' "${prefix}" "${suffix}"
}
