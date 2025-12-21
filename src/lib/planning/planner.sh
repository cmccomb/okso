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
#   PLANNER_MODEL_REPO (string): Hugging Face repository name for planner inference.
#   PLANNER_MODEL_FILE (string): model file within the repository for planner inference.
#   REACT_MODEL_REPO (string): Hugging Face repository name for ReAct inference.
#   REACT_MODEL_FILE (string): model file within the repository for ReAct inference.
#   TOOLS (array): optional array of tool names available to the planner.
#   PLAN_ONLY, DRY_RUN (bool): control execution and preview behaviour.
#   APPROVE_ALL, FORCE_CONFIRM (bool): confirmation toggles.
#   VERBOSITY (int): log level.
#
# Dependencies:
#   - bash 3.2+
#   - optional llama.cpp binary
#   - jq
#   - gum (for interactive approvals; falls back to POSIX prompts)

# Exit codes:
#   Functions return non-zero on misuse; fatal errors logged by caller.

# Ensure third-party shell hooks (e.g., mise) do not execute during
# library initialization, which can cause infinite chpwd invocations
# in non-interactive contexts such as Bats tests.
unset -f chpwd _mise_hook __zsh_like_cd cd 2>/dev/null || true
# shellcheck disable=SC2034
chpwd_functions=()

PLANNING_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/errors.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../core/errors.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../core/logging.sh"
# shellcheck source=../tools.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../tools.sh"
# shellcheck source=./respond.sh disable=SC1091
source "${PLANNING_LIB_DIR}/respond.sh"
# shellcheck source=./prompts.sh disable=SC1091
source "${PLANNING_LIB_DIR}/prompts.sh"
# shellcheck source=./schema.sh disable=SC1091
source "${PLANNING_LIB_DIR}/schema.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../core/state.sh"
# shellcheck source=./llama_client.sh disable=SC1091
source "${PLANNING_LIB_DIR}/llama_client.sh"
# shellcheck source=../config.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../config.sh"
# shellcheck source=./normalization.sh disable=SC1091
source "${PLANNING_LIB_DIR}/normalization.sh"
# shellcheck source=./prompting.sh disable=SC1091
source "${PLANNING_LIB_DIR}/prompting.sh"
# shellcheck source=./execution.sh disable=SC1091
source "${PLANNING_LIB_DIR}/execution.sh"

initialize_planner_models() {
	if [[ -z "${PLANNER_MODEL_REPO:-}" || -z "${PLANNER_MODEL_FILE:-}" || -z "${REACT_MODEL_REPO:-}" || -z "${REACT_MODEL_FILE:-}" ]]; then
		hydrate_model_specs
	fi
}
export -f initialize_planner_models

lowercase() {
	# Arguments:
	#   $1 - input string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

generate_plan_json() {
	# Arguments:
	#   $1 - user query (string)
	local user_query
	local -a planner_tools=()
	user_query="$1"

	local tools_decl
	if tools_decl=$(declare -p TOOLS 2>/dev/null) && grep -q 'declare -a' <<<"${tools_decl}"; then
		planner_tools=("${TOOLS[@]}")
	else
		planner_tools=()
		while IFS= read -r tool_name; do
			[[ -z "${tool_name}" ]] && continue
			planner_tools+=("${tool_name}")
		done < <(tool_names)
	fi

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "Using static plan because llama is unavailable" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
		printf '%s' '[{"tool":"final_answer","args":{},"thought":"Respond directly to the user request."}]'
		return 0
	fi

	local prompt raw_plan planner_schema_text plan_json
	planner_schema_text="$(load_schema_text planner_plan)"

	prompt="$(build_planner_prompt_with_tools "${user_query}" "${planner_tools[@]}")"
	log "DEBUG" "Generated planner prompt" "${prompt}" >&2
	raw_plan="$(llama_infer "${prompt}" '' 512 "${planner_schema_text}" "${PLANNER_MODEL_REPO:-}" "${PLANNER_MODEL_FILE:-}")" || raw_plan="[]"
	if ! plan_json="$(append_final_answer_step "${raw_plan}")"; then
		log "ERROR" "Planner output failed validation; request regeneration" "${raw_plan}" >&2
		return 1
	fi
	printf '%s' "${plan_json}"
}

generate_plan_outline() {
	# Arguments:
	#   $1 - user query (string)
	local plan_json
	plan_json="$(generate_plan_json "$1")"
	plan_json_to_outline "${plan_json}"
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

	if [[ -z "${plan_entries}" ]]; then
		printf '[]'
		return 0
	fi

	printf '%s\n' "${plan_entries}" |
		sed '/^[[:space:]]*$/d' |
		jq -sc 'map(select(type=="object"))'
}

derive_allowed_tools_from_plan() {
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json tool seen
	plan_json="${1:-[]}"

	seen=""
	local -a required=()
	local plan_contains_fallback=false
	if jq -e '.[] | select(.tool == "react_fallback")' <<<"${plan_json}" >/dev/null 2>&1; then
		plan_contains_fallback=true
	fi

	if [[ "${plan_contains_fallback}" == true ]]; then
		while IFS= read -r tool; do
			[[ -z "${tool}" ]] && continue
			if grep -Fxq "${tool}" <<<"${seen}"; then
				continue
			fi
			required+=("${tool}")
			seen+="${tool}"$'\n'
		done < <(tool_names)
	else
		while IFS= read -r tool; do
			[[ -z "${tool}" ]] && continue
			if grep -Fxq "${tool}" <<<"${seen}"; then
				continue
			fi
			required+=("${tool}")
			seen+="${tool}"$'\n'
		done < <(jq -r '.[] | .tool // empty' <<<"${plan_json}" 2>/dev/null || true)
	fi

	if ! grep -Fxq "final_answer" <<<"${seen}"; then
		required+=("final_answer")
	fi

	printf '%s\n' "${required[@]}"
}

plan_json_to_entries() {
	local plan_json
	plan_json="$1"
	printf '%s' "${plan_json}" | jq -cr '.[]'
}

# shellcheck source=./react.sh disable=SC1091
source "${PLANNING_LIB_DIR}/react.sh"
