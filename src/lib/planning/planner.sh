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
# shellcheck source=../formatting.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../formatting.sh"
# shellcheck source=../config.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../config.sh"

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

# Normalize noisy planner output into a clean PlannerPlan JSON array of objects.
# Reads from stdin, writes clean JSON array to stdout.
normalize_planner_plan() {
	local raw plan_candidate normalized

	raw="$(cat)"

	plan_candidate=$(
		RAW_INPUT="${raw}" python3 - <<PYTHON
import json
import os
import re
import sys

raw_input = os.environ.get("RAW_INPUT", "")


def try_parse(text: str) -> list | None:
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, list) else None


candidate = try_parse(raw_input)
if candidate is None:
    match = re.search(r"\[[\s\S]*?\]", raw_input)
    if match:
        candidate = try_parse(match.group(0))

if candidate is None:
    sys.exit(1)

json.dump(candidate, sys.stdout)

PYTHON

	) || plan_candidate=""

	if [[ -n "${plan_candidate:-}" ]]; then
		normalized=$(jq -ec '
                        def valid_step:
                                (.tool | type == "string")
                                and (.tool | length) > 0
                                and ((.args | type == "object") or (.args == null))
                                and ((.thought | type == "string") or (.thought == null));

                        if type != "array" then
                                error("plan must be an array")
                        elif any(.[]; (type != "object") or (valid_step | not)) then
                                error("plan contains invalid steps")
                        else
                                map({tool: .tool, args: (.args // {}), thought: (.thought // "")})
                        end
                        ' <<<"${plan_candidate}" 2>/dev/null || true)
		if [[ -n "${normalized}" && "${normalized}" != "[]" ]]; then
			printf '%s' "${normalized}"
			return 0
		fi
	fi

	log "ERROR" "normalize_planner_plan: unable to parse planner output" "${raw}" >&2
	return 1
}

append_final_answer_step() {
	# Ensures the plan includes a final step with the final_answer tool.
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json plan_clean has_final updated_plan
	plan_json="${1:-[]}"

	plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)" || return 1

	has_final="$(jq -r 'map((.tool // "") | ascii_downcase == "final_answer") | any' <<<"${plan_clean}" 2>/dev/null || echo false)"
	if [[ "${has_final}" == "true" ]]; then
		printf '%s' "${plan_clean}"
		return 0
	fi

	updated_plan="$(jq -c '. + [{tool:"final_answer",thought:"Summarize the result for the user.",args:{}}]' <<<"${plan_clean}" 2>/dev/null || printf '%s' "${plan_json}")"
	printf '%s' "${updated_plan}"
}

plan_json_to_outline() {
	# Converts a JSON array of plan steps into a numbered outline string.
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json plan_clean
	plan_json="${1:-[]}"

	if jq -e 'type == "array"' <<<"${plan_json}" >/dev/null 2>&1; then
		plan_clean="${plan_json}"
	else
		plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)" || return 1
	fi

	if [[ -z "${plan_clean}" ]]; then
		return 1
	fi

	jq -r 'to_entries | map("\(.key + 1). " + (if (.value.thought // "") != "" then (.value.thought // "") else "Use " + (.value.tool // "unknown") end)) | join("\n")' <<<"${plan_clean}"
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
	local tool_lines
	if ((${#planner_tools[@]} > 0)); then
		tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${planner_tools[@]}")" format_tool_summary_line)"
	else
		tool_lines=""
	fi
	planner_schema_text="$(load_schema_text planner_plan)"

	prompt="$(build_planner_prompt "${user_query}" "${tool_lines}")"
	log "DEBUG" "Generated planner prompt" "${prompt}" >&2
	raw_plan="$(llama_infer "${prompt}" '' 512 "${planner_schema_text}" "${PLANNER_MODEL_REPO}" "${PLANNER_MODEL_FILE}")" || raw_plan="[]"
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
	local tool_name context
	tool_name="$1"
	context="$2"
	if ! should_prompt_for_tool; then
		return 0
	fi

	local prompt
	prompt="Execute tool \"${tool_name}\"?"
	if [[ -n "${context}" ]]; then
		prompt+=$'\n'"${context}"
	fi
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
	# Arguments:
	#   $1 - tool name
	#   $2 - tool query (legacy string)
	#   $3 - human-readable context
	#   $4 - structured args JSON
	local tool_name tool_query context handler output status tool_args_json
	tool_name="$1"
	tool_query="$2"
	context="$3"
	tool_args_json="$4"
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

		if ! confirm_tool "${tool_name}" "${context}"; then
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

	TOOL_QUERY="${tool_query}" TOOL_ARGS="${tool_args_json}" ${handler} >"${stdout_file}" 2>"${stderr_file}"
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

	jq -nc \
		--arg output "${output}" \
		--arg error "${stderr_output}" \
		--argjson exit_code "${status}" \
		'{output: $output, error: $error, exit_code: $exit_code}'
	return 0
}

# shellcheck source=./react.sh disable=SC1091
source "${PLANNING_LIB_DIR}/react.sh"
