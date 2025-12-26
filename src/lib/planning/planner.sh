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
#   SEARCH_REPHRASER_MODEL_REPO (string): Hugging Face repository name for search rephrasing inference.
#   SEARCH_REPHRASER_MODEL_FILE (string): model file within the repository for search rephrasing inference.
#   EXECUTOR_MODEL_REPO (string): Hugging Face repository name for executor inference.
#   EXECUTOR_MODEL_FILE (string): model file within the repository for executor inference.
#   EXECUTOR_ENTRYPOINT (string): optional path override for the executor entrypoint script.
#   TOOLS (array): optional array of tool names available to the planner.
#   PLAN_ONLY, DRY_RUN (bool): control execution and preview behaviour.
#   APPROVE_ALL, FORCE_CONFIRM (bool): confirmation toggles.
#   VERBOSITY (int): log level.
#   PLANNER_SKIP_TOOL_LOAD (bool): skip sourcing the tool suite; useful for tests.
#   PLANNER_SAMPLE_COUNT (int >=1): number of planner generations to sample; values below 1 are coerced to 1.
#   PLANNER_TEMPERATURE (float 0-1): temperature forwarded to planner llama.cpp calls.
#   PLANNER_DEBUG_LOG (string): JSONL sink for scored planner candidates; truncated at each invocation.
#   PLANNER_MAX_OUTPUT_TOKENS (int >=1): planner llama.cpp generation budget; values below 1 fall back to the default.
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

# Planner architecture overview
# -----------------------------
# The planner performs a short, deterministic pass before the executor loop
# executes any tools. The high-level flow is:
#   1. Tools and schemas are sourced so the planner understands which actions
#      are available and how they should be called.
#   2. A lightweight web search seeds context that the planner can cite when
#      drafting the outline (optional when the search tool is absent).
#   3. Prompt builders render a prefix + suffix prompt that injects schemas,
#      tool descriptions, and examples into a llama.cpp completion request.
#   4. Raw model responses are normalized into the canonical planner schema
#      and scored for safety + viability.
#   5. The best candidate's plan and allowed tools are forwarded to the executor
#      loop, which handles execution, approvals, and final answers.
#
# This file owns steps (1)–(4); execution dispatch lives in ../executor/executor.sh.

# shellcheck source=../core/errors.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../core/errors.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../core/logging.sh"
# shellcheck source=../tools.sh disable=SC1091
if [[ "${PLANNER_SKIP_TOOL_LOAD:-false}" != true ]]; then
	source "${PLANNING_LIB_DIR}/../tools.sh"
else
	log "DEBUG" "Skipping tool suite load" "planner_skip_tool_load=true" >&2
fi
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
# shellcheck source=./rephrasing.sh disable=SC1091
source "${PLANNING_LIB_DIR}/rephrasing.sh"
if [[ "${PLANNER_SKIP_TOOL_LOAD:-false}" != true ]]; then
	# shellcheck source=../exec/dispatch.sh disable=SC1091
	source "${PLANNING_LIB_DIR}/../exec/dispatch.sh"
fi

initialize_planner_models() {
	# Hydrates planner and executor model specs when callers did not pass
	# explicit repositories or filenames via the environment. This keeps
	# downstream llama.cpp calls predictable regardless of how the planner
	# was sourced (CLI invocation vs. tests).
	if [[ -z "${PLANNER_MODEL_REPO:-}" || -z "${PLANNER_MODEL_FILE:-}" || -z "${REACT_MODEL_REPO:-}" || -z "${REACT_MODEL_FILE:-}" ]]; then
		hydrate_model_specs
	fi
}
export -f initialize_planner_models

planner_format_search_context() {
	# Formats web search JSON into readable prompt text.
	# Arguments:
	#   $1 - raw search payload (JSON string)
	local raw_context formatted
	raw_context="$1"

	if [[ -z "${raw_context}" ]]; then
		printf '%s' "Search context unavailable."
		return 0
	fi

	if ! formatted=$(jq -r '
                def fmt(idx; item): "\(idx). \(item.title // "Untitled"): \(item.snippet // "") [\(item.url // "")";
                if (.items | length == 0) then
                        "No search results were captured for this query."
                else
                        "Query: \(.query // "")\n" +
                        ((.items // []) | to_entries | map(fmt(.key + 1; .value)) | join("\n"))
                end
        ' <<<"${raw_context}" 2>/dev/null); then
		log "ERROR" "Failed to format search context" "planner_search_context_parse_error" >&2
		printf '%s' "Search context unavailable."
		return 0
	fi

	printf '%s' "${formatted}"
}

planner_fetch_search_context() {
	# Executes deterministic web searches for rephrased queries before planning.
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   Formatted search context (string). Fallbacks are empty but non-fatal.
	local user_query tool_args raw_context queries_json formatted_context
	local -a formatted_sections=()
	user_query="$1"

	if ! declare -F tool_web_search >/dev/null 2>&1; then
		log "WARN" "web_search tool unavailable; skipping pre-plan search" "planner_tools_missing_web_search" >&2
		printf '%s' "Search context unavailable."
		return 0
	fi

	if ! queries_json="$(planner_generate_search_queries "${user_query}")"; then
		log "WARN" "Failed to derive search queries; defaulting to raw query" "planner_rephrase_failed" >&2
		queries_json="$(jq -nc --arg query "${user_query}" '[ $query ]' 2>/dev/null || printf '["%s"]' "${user_query}")"
	fi

	if [[ -z "${queries_json}" ]]; then
		queries_json="$(jq -nc --arg query "${user_query}" '[ $query ]' 2>/dev/null || printf '["%s"]' "${user_query}")"
	fi

	local index=0
	while IFS= read -r search_query; do
		((index++))
		if [[ -z "${search_query}" ]]; then
			continue
		fi

		tool_args=$(jq -nc --arg query "${search_query}" '{query:$query, num:5}' 2>/dev/null)
		if [[ -z "${tool_args}" ]]; then
			log "WARN" "Failed to encode search args" "planner_search_args_encoding_failed" >&2
			raw_context=$(jq -nc --arg query "${search_query}" '{query:$query,items:[]}' 2>/dev/null)
		elif ! raw_context=$(TOOL_ARGS="${tool_args}" tool_web_search 2>/dev/null); then
			log "WARN" "Pre-plan search failed" "planner_preplan_search_failed" >&2
			raw_context=$(jq -nc --arg query "${search_query}" '{query:$query,items:[]}' 2>/dev/null)
		fi

		formatted_context=$(planner_format_search_context "${raw_context}")
		formatted_sections+=("Search ${index}: ${formatted_context}")
	done < <(jq -r '.[]' <<<"${queries_json}" 2>/dev/null)

	printf '%s' "$(printf '%s\n' "${formatted_sections[@]}" | sed '/^[[:space:]]*$/d' | paste -sd $'\n\n' -)"
}

lowercase() {
	# Arguments:
	#   $1 - input string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_positive_int() {
	# Coerces planner numeric inputs into positive integers to keep llama.cpp
	# invocations predictable.
	# Arguments:
	#   $1 - raw value (string)
	#   $2 - fallback value used when validation fails (string)
	#   $3 - metric name for logging (string)
	local raw fallback metric sanitized
	raw="$1"
	fallback="$2"
	metric="$3"

	if [[ "${raw}" =~ ^[0-9]+$ ]] && ((raw >= 1)); then
		sanitized="${raw}"
	else
		log "WARN" "Invalid ${metric}; using fallback" "${metric}=${raw:-unset}" >&2
		sanitized="${fallback}"
	fi

	printf '%s' "${sanitized}"
}

validate_temperature() {
	# Normalizes planner temperature into a bounded numeric value.
	# Arguments:
	#   $1 - raw temperature (string)
	#   $2 - fallback temperature when validation fails (string)
	local raw fallback sanitized
	raw="$1"
	fallback="$2"

	if [[ "${raw}" =~ ^[0-9]*\.?[0-9]+$ ]] && awk -v t="${raw}" 'BEGIN { exit !(t >= 0 && t <= 1) }'; then
		sanitized="${raw}"
	else
		log "WARN" "Invalid planner temperature; using fallback" "temperature=${raw:-unset}" >&2
		sanitized="${fallback}"
	fi

	printf '%s' "${sanitized}"
}

generate_planner_response() {
	# Arguments:
	#   $1 - user query (string)
	local user_query
	local -a planner_tools=()
	user_query="$1"

	initialize_planner_models

	if ! require_llama_available "planner generation"; then
		log "ERROR" "Planner cannot generate steps without llama.cpp" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
		local fallback
		fallback="LLM unavailable. Request received: ${user_query}"
		jq -nc \
			--arg answer "${fallback}" \
			'{plan:[{tool:"final_answer", args:{input:$answer}, thought:"Provide the direct response."}]}'
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

	local planner_tool_catalog
	planner_tool_catalog="$(printf '%s\n' "${planner_tools[@]}" | paste -sd ',' -)"
	log "DEBUG" "Planner tool catalog" "${planner_tool_catalog}" >&2

	local planner_schema_text planner_prompt_prefix planner_suffix tool_lines prompt search_context
	planner_schema_text="$(load_schema_text planner_plan)"

	tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${planner_tools[@]}")" format_tool_line)"
	search_context="$(planner_fetch_search_context "${user_query}")"
	planner_prompt_prefix="$(build_planner_prompt_static_prefix)"
	planner_suffix="$(build_planner_prompt_dynamic_suffix "${user_query}" "${tool_lines}" "${search_context}")"
	prompt="${planner_prompt_prefix}${planner_suffix}"
	log "DEBUG" "Generated planner prompt" "${prompt}" >&2

	local sample_count temperature debug_log_dir debug_log_file max_generation_tokens
	sample_count="$(validate_positive_int "${PLANNER_SAMPLE_COUNT:-3}" 3 "PLANNER_SAMPLE_COUNT")"
	temperature="$(validate_temperature "${PLANNER_TEMPERATURE:-0.2}" 0.2)"
	max_generation_tokens="$(validate_positive_int "${PLANNER_MAX_OUTPUT_TOKENS:-1024}" 1024 "PLANNER_MAX_OUTPUT_TOKENS")"
	# Capture the sampling configuration early so operators can verify the
	# breadth of exploration before generation begins. This also doubles as
	# a trace when investigating unexpected candidate rankings.
	log "INFO" "Planner sampling configuration" "$(jq -nc --arg sample_count "${sample_count}" --arg temperature "${temperature}" '{sample_count:$sample_count,temperature:$temperature}')" >&2
	# Sample count controls how many candidates are generated and scored.
	# Validation clamps values below 1 to a single candidate so downstream
	# selection always has material to review.
	if ! [[ "${sample_count}" =~ ^[0-9]+$ ]] || ((sample_count < 1)); then
		sample_count=1
	fi

	if ! [[ "${max_generation_tokens}" =~ ^[0-9]+$ ]] || ((max_generation_tokens < 1)); then
		max_generation_tokens=1024
	fi

	# Temperature is forwarded verbatim to llama.cpp; callers should keep
	# values in a 0-1 range to avoid erratic generation.

	debug_log_dir="${TMPDIR:-/tmp}"
	# Each candidate is appended to PLANNER_DEBUG_LOG as a JSON object with
	# score, tie-breaker, rationale, and the normalized response. The file
	# is truncated per invocation to keep the latest run isolated.
	debug_log_file="${PLANNER_DEBUG_LOG:-${debug_log_dir%/}/okso_planner_candidates.log}"
	mkdir -p "$(dirname "${debug_log_file}")" 2>/dev/null || true
	: >"${debug_log_file}" 2>/dev/null || true

	# Seed the best score with a very negative value so that even heavily
	# penalized candidates remain eligible for selection. This avoids
	# returning empty results when every candidate incurs availability or
	# safety deductions during scoring.
	local best_plan="" best_score=-999999 best_tie_breaker=-9999 candidate_index=0 raw_plan normalized_plan
	local candidate_score candidate_tie_breaker candidate_scorecard candidate_rationale
	while ((candidate_index < sample_count)); do
		candidate_index=$((candidate_index + 1))

		# Each loop iteration generates a single candidate, normalizes it
		# into the canonical schema, and scores it for downstream
		# selection. Any failure to normalize or score results in the
		# candidate being skipped, which keeps downstream selection
		# deterministic and safe.
		raw_plan="$(LLAMA_TEMPERATURE="${temperature}" llama_infer "${prompt}" '' "${max_generation_tokens}" "${planner_schema_text}" "${PLANNER_MODEL_REPO:-}" "${PLANNER_MODEL_FILE:-}" "${PLANNER_CACHE_FILE:-}" "${planner_prompt_prefix}")" || raw_plan="[]"

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

		# Emit a detailed INFO log for each candidate so operators can
		# trace how the scorer evaluated the plan. The rationale array
		# is preserved intact for downstream debugging.
		log "INFO" "Planner candidate scored" "$(jq -nc \
			--argjson index "${candidate_index}" \
			--argjson score "${candidate_score}" \
			--argjson tie_breaker "${candidate_tie_breaker}" \
			--argjson rationale "${candidate_rationale}" \
			'{index:$index,score:$score,tie_breaker:$tie_breaker,rationale:$rationale}')" >&2

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

	jq -c '.plan // .' <<<"${response_json}"
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
	local plan_json tool seen status
	plan_json="${1:-[]}"

	if plan_json="$(extract_plan_array "${plan_json}")"; then
		status=0
	else
		status=$?
	fi
	if [[ ${status} -ne 0 ]]; then
		return 1
	fi

	seen=""
	local -a required=()
	local plan_contains_fallback=false
	if jq -e '.[] | select(.tool == "executor_fallback")' <<<"${plan_json}" >/dev/null 2>&1; then
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
	local plan_json status
	plan_json="$1"

	if plan_json="$(extract_plan_array "${plan_json}")"; then
		status=0
	else
		status=$?
	fi
	if [[ ${status} -ne 0 ]]; then
		return 1
	fi

	printf '%s' "${plan_json}" # | jq -cr '.[]'
}

# Emits the next planned action for deterministic execution when llama.cpp is disabled.
# Arguments:
#   $1 - state prefix (string)
#   $2 - variable name to populate with the selected action JSON
select_next_action() {
	local state_prefix output_var plan_entries_raw plan_entries plan_array plan_index next_action plan_length plan_json
	state_prefix="$1"
	output_var="$2"

	plan_entries_raw="$(state_get "${state_prefix}" "plan_entries" 2>/dev/null || printf '')"
	plan_entries="$(printf '%s' "${plan_entries_raw}" | jq -r '.' 2>/dev/null || printf '%s' "${plan_entries_raw}")"

	if jq -e 'type == "array"' <<<"${plan_entries}" >/dev/null 2>&1; then
		plan_json="${plan_entries}"
	elif jq -e 'type == "object"' <<<"${plan_entries}" >/dev/null 2>&1; then
		plan_json="[${plan_entries}]"
	else
		plan_json="$(printf '%s\n' "${plan_entries}" | jq -cs 'map(select(length > 0) | (try fromjson catch .))' 2>/dev/null || printf '[]')"
	fi

	if ! plan_array="$(normalize_planner_plan <<<"${plan_json}")"; then
		return 1
	fi

	plan_index="$(state_get "${state_prefix}" "plan_index" 2>/dev/null || printf '0')"
	if [[ -z "${plan_index}" || ! "${plan_index}" =~ ^[0-9]+$ ]]; then
		plan_index=0
	fi

	plan_length="$(jq -r 'length' <<<"${plan_array}" 2>/dev/null || printf '0')"
	if ((plan_index >= plan_length)); then
		return 1
	fi

	next_action="$(jq -c --argjson idx "${plan_index}" '.[ $idx ]' <<<"${plan_array}" 2>/dev/null || printf '')"
	if [[ -z "${next_action}" ]]; then
		return 1
	fi

	state_set "${state_prefix}" "plan_index" $((plan_index + 1)) || return 1
	printf -v "${output_var}" '%s' "${next_action}"
}

EXECUTOR_ENTRYPOINT=${EXECUTOR_ENTRYPOINT:-"${PLANNING_LIB_DIR}/../executor/executor.sh"}

if [[ "${PLANNER_SKIP_TOOL_LOAD:-false}" == true ]]; then
	log "DEBUG" "Skipping executor entrypoint load" "planner_skip_tool_load=true" >&2
else
	if [[ ! -f "${EXECUTOR_ENTRYPOINT}" ]]; then
		log "ERROR" "Executor entrypoint missing" "EXECUTOR_ENTRYPOINT=${EXECUTOR_ENTRYPOINT}" >&2
		return 1 2>/dev/null
	fi

	# shellcheck source=../executor/executor.sh disable=SC1091
	source "${EXECUTOR_ENTRYPOINT}"
fi
