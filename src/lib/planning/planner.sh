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
#   REACT_ENTRYPOINT (string): optional path override for the ReAct entrypoint script.
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
# shellcheck source=../assistant/respond.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../assistant/respond.sh"
# shellcheck source=../prompt/build_planner.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../prompt/build_planner.sh"
# shellcheck source=../schema/schema.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../schema/schema.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../core/state.sh"
# shellcheck source=../dependency_guards/dependency_guards.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../dependency_guards/dependency_guards.sh"
# shellcheck source=../llm/llama_client.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../llm/llama_client.sh"
# shellcheck source=../config.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../config.sh"
# shellcheck source=./normalization.sh disable=SC1091
source "${PLANNING_LIB_DIR}/normalization.sh"
# shellcheck source=./scoring.sh disable=SC1091
source "${PLANNING_LIB_DIR}/scoring.sh"
# shellcheck source=./prompting.sh disable=SC1091
source "${PLANNING_LIB_DIR}/prompting.sh"
# shellcheck source=../exec/dispatch.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../exec/dispatch.sh"

PLANNER_WEB_SEARCH_BUDGET_FILE=${PLANNER_WEB_SEARCH_BUDGET_FILE:-"${TMPDIR:-/tmp}/okso_planner_web_search_budget"}
export PLANNER_WEB_SEARCH_BUDGET_FILE
PLANNER_WEB_SEARCH_BUDGET_CAP=${PLANNER_WEB_SEARCH_BUDGET_CAP:-2}
if [[ -z "${PLANNER_WEB_SEARCH_BUDGET_CAP}" || ! "${PLANNER_WEB_SEARCH_BUDGET_CAP}" =~ ^[0-9]+$ ]]; then
	PLANNER_WEB_SEARCH_BUDGET_CAP=2
fi
export PLANNER_WEB_SEARCH_BUDGET_CAP

planner_web_search_budget_value() {
	if [[ -f "${PLANNER_WEB_SEARCH_BUDGET_FILE}" ]]; then
		cat "${PLANNER_WEB_SEARCH_BUDGET_FILE}" 2>/dev/null || printf '0'
	else
		printf '0'
	fi
}
export -f planner_web_search_budget_value

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

score_planner_candidate() {
	# Arguments:
	#   $1 - normalized planner response JSON (string)
	local normalized_json score
	normalized_json="$1"

	score=$(jq -er '
                if .mode == "quickdraw" then
                        0
                else
                        ((.plan | length) - 1) as $step_count
                        | (if $step_count < 0 then 0 else $step_count end) as $safe_steps
                        | ($safe_steps * 10) + (.plan | map(.tool) | unique | length)
                end
                ' <<<"${normalized_json}" 2>/dev/null) || score=0

	printf '%s' "${score}"
}

generate_planner_response() {
	# Arguments:
	#   $1 - user query (string)
	local user_query
	local -a planner_tools=()
	user_query="$1"

	if ! require_llama_available "planner generation"; then
		log "ERROR" "Planner cannot generate steps without llama.cpp" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
		local fallback
		fallback="LLM unavailable. Request received: ${user_query}"
		jq -nc \
			--arg answer "${fallback}" \
			--arg rationale "Respond directly; tools skipped because llama.cpp is unavailable." \
			'{mode:"quickdraw", plan: [], quickdraw:{final_answer:$answer, confidence:0, rationale:$rationale}}'
		return 0
	fi

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

	if ! printf '%s\0' "${planner_tools[@]}" | grep -Fxzq "web_search"; then
		planner_tools+=("web_search")
		log "INFO" "Web search enabled for planning" "planner_tools_appended=web_search" >&2
	else
		log "DEBUG" "Web search already available to planner" "planner_tools_present=web_search" >&2
	fi

	local planner_tool_catalog
	planner_tool_catalog="$(printf '%s\n' "${planner_tools[@]}" | paste -sd ',' -)"
	log "DEBUG" "Planner tool catalog" "${planner_tool_catalog}" >&2

	local planner_schema_text planner_prompt_prefix planner_suffix tool_lines prompt
	planner_schema_text="$(load_schema_text planner_plan)"

	tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${planner_tools[@]}")" format_tool_summary_line)"
	planner_prompt_prefix="$(build_planner_prompt_static_prefix)"
	planner_suffix="$(build_planner_prompt_dynamic_suffix "${user_query}" "${tool_lines}")"
	prompt="${planner_prompt_prefix}${planner_suffix}"
	log "DEBUG" "Generated planner prompt" "${prompt}" >&2

	local sample_count temperature debug_log_dir debug_log_file
	sample_count="${PLANNER_SAMPLE_COUNT:-3}"
	temperature="${PLANNER_TEMPERATURE:-0.2}"
	if ! [[ "${sample_count}" =~ ^[0-9]+$ ]] || ((sample_count < 1)); then
		sample_count=1
	fi

	debug_log_dir="${TMPDIR:-/tmp}"
	debug_log_file="${PLANNER_DEBUG_LOG:-${debug_log_dir%/}/okso_planner_candidates.log}"
	mkdir -p "$(dirname "${debug_log_file}")" 2>/dev/null || true
	: >"${debug_log_file}" 2>/dev/null || true

	local best_plan="" best_score=-1 best_tie_breaker=-9999 candidate_index=0 raw_plan normalized_plan
	local candidate_score candidate_tie_breaker candidate_scorecard candidate_rationale
	while ((candidate_index < sample_count)); do
		candidate_index=$((candidate_index + 1))

		raw_plan="$(LLAMA_TEMPERATURE="${temperature}" llama_infer "${prompt}" '' 512 "${planner_schema_text}" "${PLANNER_MODEL_REPO:-}" "${PLANNER_MODEL_FILE:-}" "${PLANNER_CACHE_FILE:-}" "${planner_prompt_prefix}")" || raw_plan="[]"

		if ! normalized_plan="$(normalize_planner_response <<<"${raw_plan}")"; then
			log "ERROR" "Planner output failed validation; request regeneration" "${raw_plan}" >&2
			continue
		fi

		if ! candidate_scorecard="$(score_planner_candidate "${normalized_plan}")"; then
			log "ERROR" "Planner output failed scoring" "${normalized_plan}" >&2
			continue
		fi

		candidate_score="$(jq -er '.score' <<<"${candidate_scorecard}" 2>/dev/null || printf '0')"
		candidate_tie_breaker="$(jq -er '.tie_breaker // 0' <<<"${candidate_scorecard}" 2>/dev/null || printf '0')"
		candidate_rationale="$(jq -c '.rationale // []' <<<"${candidate_scorecard}" 2>/dev/null || printf '[]')"

		jq -nc \
			--argjson index "${candidate_index}" \
			--argjson score "${candidate_score}" \
			--argjson tie_breaker "${candidate_tie_breaker}" \
			--argjson rationale "${candidate_rationale}" \
			--argjson response "${normalized_plan}" \
			'{index:$index, score:$score, tie_breaker:$tie_breaker, rationale:$rationale, response:$response}' >>"${debug_log_file}" 2>/dev/null || true

		if ((candidate_score > best_score)) || { ((candidate_score == best_score)) && ((candidate_tie_breaker > best_tie_breaker)); }; then
			best_score=${candidate_score}
			best_tie_breaker=${candidate_tie_breaker}
			best_plan="${normalized_plan}"
		fi
	done

	if [[ -z "${best_plan}" ]]; then
		log "ERROR" "Planner output failed validation; request regeneration" "no_valid_candidates" >&2
		return 1
	fi

	printf '%s' "${best_plan}"
}

generate_plan_outline() {
	# Arguments:
	#   $1 - user query (string)
	local response_json
	if ! response_json="$(generate_planner_response "$1")"; then
		return 1
	fi
	plan_json_to_outline "${response_json}"
}

# Backwards compatibility wrapper; prefer generate_planner_response for new callers.
generate_plan_json() {
	local response_json
	if ! response_json="$(generate_planner_response "$1")"; then
		return 1
	fi

	if jq -e '.mode == "plan"' <<<"${response_json}" >/dev/null 2>&1; then
		jq -c '.plan' <<<"${response_json}"
	else
		jq -c '.' <<<"${response_json}"
	fi
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
	#   $1 - planner response JSON (object or legacy plan array)
	local plan_json tool seen web_search_cap web_search_count
	plan_json="${1:-[]}"
	web_search_cap="${PLANNER_WEB_SEARCH_BUDGET_CAP}"

	if [[ -z "${web_search_cap}" || ! "${web_search_cap}" =~ ^[0-9]+$ ]]; then
		web_search_cap=2
	fi

	PLANNER_WEB_SEARCH_BUDGET=0
	export PLANNER_WEB_SEARCH_BUDGET
	printf '%s' "${PLANNER_WEB_SEARCH_BUDGET}" >"${PLANNER_WEB_SEARCH_BUDGET_FILE}" 2>/dev/null || true

	if jq -e '.mode == "quickdraw"' <<<"${plan_json}" >/dev/null 2>&1; then
		return 0
	fi

	if jq -e '.mode == "plan" and (.plan | type == "array")' <<<"${plan_json}" >/dev/null 2>&1; then
		plan_json="$(jq -c '.plan' <<<"${plan_json}")"
	fi

	web_search_count=$(jq -r '[.[] | select(.tool == "web_search")] | length' <<<"${plan_json}" 2>/dev/null || printf '0')
	PLANNER_WEB_SEARCH_BUDGET="${web_search_count}"
	export PLANNER_WEB_SEARCH_BUDGET
	printf '%s' "${PLANNER_WEB_SEARCH_BUDGET}" >"${PLANNER_WEB_SEARCH_BUDGET_FILE}" 2>/dev/null || true
	if ((web_search_count > web_search_cap)); then
		log "ERROR" "Planner web_search budget exceeded" "$(printf 'requested=%s cap=%s' "${web_search_count}" "${web_search_cap}")" >&2 || true
		return 1
	fi
	if ((web_search_count > 0)); then
		log "INFO" "Planner web_search budget accepted" "$(printf 'requested=%s cap=%s' "${web_search_count}" "${web_search_cap}")" >&2 || true
	fi

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
	if jq -e '.mode == "quickdraw"' <<<"${plan_json}" >/dev/null 2>&1; then
		return 0
	fi
	if jq -e '.mode == "plan" and (.plan | type == "array")' <<<"${plan_json}" >/dev/null 2>&1; then
		plan_json="$(jq -c '.plan' <<<"${plan_json}")"
	fi
	printf '%s' "${plan_json}" | jq -cr '.[]'
}

REACT_ENTRYPOINT=${REACT_ENTRYPOINT:-"${PLANNING_LIB_DIR}/../react/react.sh"}

if [[ ! -f "${REACT_ENTRYPOINT}" ]]; then
	log "ERROR" "ReAct entrypoint missing" "REACT_ENTRYPOINT=${REACT_ENTRYPOINT}" >&2
	return 1 2>/dev/null
fi

# shellcheck source=../react/react.sh disable=SC1091
source "${REACT_ENTRYPOINT}"
