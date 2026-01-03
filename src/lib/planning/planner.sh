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
# This file owns steps (1)–(4); execution dispatch lives in ../executor/loop.sh.

# shellcheck source=src/lib/core/errors.sh
source "${PLANNING_LIB_DIR}/../core/errors.sh"
# shellcheck source=src/lib/core/logging.sh
source "${PLANNING_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/tools.sh
if [[ "${PLANNER_SKIP_TOOL_LOAD:-false}" != true ]]; then
	source "${PLANNING_LIB_DIR}/../tools.sh"
else
	log "DEBUG" "Skipping tool suite load" "planner_skip_tool_load=true" >&2
fi
# shellcheck source=src/lib/prompt/build_planner.sh
source "${PLANNING_LIB_DIR}/../prompt/build_planner.sh"
# shellcheck source=src/lib/schema/schema.sh
source "${PLANNING_LIB_DIR}/../schema/schema.sh"
# shellcheck source=src/lib/core/json_state.sh
source "${PLANNING_LIB_DIR}/../core/json_state.sh"
# shellcheck source=src/lib/llm/llama_client.sh
source "${PLANNING_LIB_DIR}/../llm/llama_client.sh"
# shellcheck source=src/lib/config.sh
source "${PLANNING_LIB_DIR}/../config.sh"
# shellcheck source=src/lib/planning/normalization.sh
source "${PLANNING_LIB_DIR}/normalization.sh"
# shellcheck source=src/lib/planning/scoring.sh
source "${PLANNING_LIB_DIR}/scoring.sh"
# shellcheck source=src/lib/planning/prompting.sh
source "${PLANNING_LIB_DIR}/prompting.sh"
# shellcheck source=src/lib/planning/rephrasing.sh
source "${PLANNING_LIB_DIR}/rephrasing.sh"
if [[ "${PLANNER_SKIP_TOOL_LOAD:-false}" != true ]]; then
	# shellcheck source=src/lib/executor/dispatch.sh
	source "${PLANNING_LIB_DIR}/../executor/dispatch.sh"
fi

initialize_planner_models() {
	# Hydrates planner and executor model specs when callers did not pass
	# explicit repositories or filenames via the environment. This keeps
	# downstream llama.cpp calls predictable regardless of how the planner
	# was sourced (CLI invocation vs. tests).
	if [[ -z "${PLANNER_MODEL_REPO:-}" || -z "${PLANNER_MODEL_FILE:-}" || -z "${EXECUTOR_MODEL_REPO:-}" || -z "${EXECUTOR_MODEL_FILE:-}" ]]; then
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

	# Fallback when no context is available
	if [[ -z "${raw_context}" ]]; then
		printf '%s' "Search context unavailable."
		return 0
	fi

	# Format the search results
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

	# Return the formatted context
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

	# Derive search queries
	if ! queries_json="$(planner_generate_search_queries "${user_query}")"; then
		log "WARN" "Failed to derive search queries; defaulting to raw query" "pre_planner_search_terms_failed" >&2
		queries_json="$(jq -nc --arg query "${user_query}" '[ $query ]' 2>/dev/null || printf '["%s"]' "${user_query}")"
	fi

	# Execute searches and format context
	local index=0
	while IFS= read -r search_query; do
		((index++))
		if [[ -z "${search_query}" ]]; then
			continue
		fi

		# Prepare tool arguments
		tool_args=$(jq -nc --arg query "${search_query}" '{query:$query, num:5}' 2>/dev/null)

		# Execute the search tool
		if [[ -z "${tool_args}" ]]; then
			log "WARN" "Failed to encode search args" "planner_search_args_encoding_failed" >&2
			raw_context=$(jq -nc --arg query "${search_query}" '{query:$query,items:[]}' 2>/dev/null)
		elif ! raw_context=$(TOOL_ARGS="${tool_args}" tool_web_search 2>/dev/null); then
			log "WARN" "Pre-plan search failed" "planner_preplan_search_failed" >&2
			raw_context=$(jq -nc --arg query "${search_query}" '{query:$query,items:[]}' 2>/dev/null)
		fi

		# Format the search context
		formatted_context=$(planner_format_search_context "${raw_context}")
		formatted_sections+=("Search ${index}: ${formatted_context}")
	done < <(jq -r '.[]' <<<"${queries_json}" 2>/dev/null)

	# Return the combined search context
	printf '%s' "$(printf '%s\n' "${formatted_sections[@]}" | sed '/^[[:space:]]*$/d' | paste -sd $'\n\n' -)"
}

lowercase() {
	# Arguments:
	#   $1 - input string
	# Returns:
	#   lowercased string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_positive_int() {
	# Coerces planner numeric inputs into positive integers to keep llama.cpp
	# invocations predictable.
	# Arguments:
	#   $1 - raw value (string)
	#   $2 - fallback value used when validation fails (string)
	#   $3 - metric name for logging (string)
	# Returns:
	#   sanitized positive integer (string)
	local raw fallback metric sanitized
	raw="$1"
	fallback="$2"
	metric="$3"

	# Validate positive integer
	if [[ "${raw}" =~ ^[0-9]+$ ]] && ((raw >= 1)); then
		sanitized="${raw}"
	else
		log "WARN" "Invalid ${metric}; using fallback" "${metric}=${raw:-unset}" >&2
		sanitized="${fallback}"
	fi

	# Return sanitized value
	printf '%s' "${sanitized}"
}

validate_temperature() {
	# Normalizes planner temperature into a bounded numeric value.
	# Arguments:
	#   $1 - raw temperature (string)
	#   $2 - fallback temperature when validation fails (string)
	# Returns:
	#   sanitized temperature (string)
	local raw fallback sanitized
	raw="$1"
	fallback="$2"

	# Validate temperature in 0-1 range
	if [[ "${raw}" =~ ^[0-9]*\.?[0-9]+$ ]] && awk -v t="${raw}" 'BEGIN { exit !(t >= 0 && t <= 1) }'; then
		sanitized="${raw}"
	else
		log "WARN" "Invalid planner temperature; using fallback" "temperature=${raw:-unset}" >&2
		sanitized="${fallback}"
	fi

	# Return sanitized value
	printf '%s' "${sanitized}"
}

generate_planner_response() {
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   planner response JSON (string)
	local user_query
	local -a planner_tools=()
	user_query="$1"

	# Initialize settings for planner and executor models
	initialize_planner_models

	# Assemble the tool catalog
	local tools_decl=""
	if declare -p TOOLS >/dev/null 2>&1; then
		tools_decl="$(declare -p TOOLS)"
	fi

	if [[ -n "${tools_decl}" ]] && grep -q 'declare -a' <<<"${tools_decl}"; then
		planner_tools=("${TOOLS[@]}")
	else
		planner_tools=()
		while IFS= read -r tool_name; do
			[[ -z "${tool_name}" ]] && continue
			planner_tools+=("${tool_name}")
		done < <(tool_names)
	fi

	# Log the tool catalog for operator visibility
	local planner_tool_catalog
	planner_tool_catalog="$(printf '%s\n' "${planner_tools[@]}" | paste -sd ',' -)"
	log "DEBUG" "Planner tool catalog" "${planner_tool_catalog}" >&2

	# Build the planner prompt
	local planner_schema_text tool_lines prompt search_context
	planner_schema_text="$(load_schema_text planner_plan)"
	tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${planner_tools[@]}")" format_tool_line)"
	search_context="$(planner_fetch_search_context "${user_query}")"
	prompt="$(build_planner_prompt "${user_query}" "${tool_lines}" "${search_context}")"
	log "DEBUG" "Generated planner prompt" "${prompt}" >&2

	# Configure sampling parameters
	local sample_count temperature debug_log_dir debug_log_file max_generation_tokens
	sample_count="$(validate_positive_int "${PLANNER_SAMPLE_COUNT:-3}" 3 "PLANNER_SAMPLE_COUNT")"
	temperature="$(validate_temperature "${PLANNER_TEMPERATURE:-0.7}" 0.7)"
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

	# Max generation tokens controls the budget for each llama.cpp call.
	if ! [[ "${max_generation_tokens}" =~ ^[0-9]+$ ]] || ((max_generation_tokens < 1)); then
		max_generation_tokens=1024
	fi

	# Debug log directory defaults to TMPDIR or /tmp when unset.
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
		raw_plan="$(LLAMA_TEMPERATURE="${temperature}" llama_infer "${prompt}" '' "${max_generation_tokens}" "${planner_schema_text}" "${PLANNER_MODEL_REPO:-}" "${PLANNER_MODEL_FILE:-}" "${PLANNER_CACHE_FILE:-}" "${prompt}")"

		# Normalize the candidate plan and skip unusable outputs
		if ! normalized_plan="$(normalize_plan <<<"${raw_plan}")"; then
			log "WARN" "Planner output unusable from llama.cpp" "${raw_plan}" >&2
			continue
		fi

		# Score the candidate plan and skip scoring failures
		if ! candidate_scorecard="$(score_planner_candidate "${normalized_plan}")"; then
			log "ERROR" "Planner output failed scoring" "${normalized_plan}" >&2
			continue
		fi

		# Extract scoring details for logging and selection
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

		# Append the candidate to the debug log for post-mortem analysis.
		jq -nc \
			--argjson index "${candidate_index}" \
			--argjson score "${candidate_score}" \
			--argjson tie_breaker "${candidate_tie_breaker}" \
			--argjson rationale "${candidate_rationale}" \
			--argjson response "${normalized_plan}" \
			'{index:$index, score:$score, tie_breaker:$tie_breaker, rationale:$rationale, response:$response}' >>"${debug_log_file}" 2>/dev/null || true

		# Update the best candidate when the score or tie-breaker improves
		if ((candidate_score > best_score)) || { ((candidate_score == best_score)) && ((candidate_tie_breaker > best_tie_breaker)); }; then
			best_score=${candidate_score}
			best_tie_breaker=${candidate_tie_breaker}
			best_plan="${normalized_plan}"
		fi

	done

	# Return the best candidate or error when none are valid
	if [[ -z "${best_plan}" ]]; then
		log "ERROR" "Planner produced no usable candidates; request llama regeneration" "no_valid_candidates" >&2
		return 1
	fi

	printf '%s' "${best_plan}"
}

generate_plan_outline() {
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   plan outline text (string)
	local response_json

	# Generate the planner response
	if ! response_json="$(generate_planner_response "$1")"; then
		return 1
	fi

	# Convert the plan JSON into an outline
	plan_json_to_outline "${response_json}"
}

tool_query_deriver() {
	# Arguments:
	#   $1 - tool name (string)
	# Returns:
	#   name of the query derivation function (string)

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
	# Returns:
	#   tool query (string)
	printf '%s\n' "$1"
}

derive_tool_query() {
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - user query (string)
	# Returns:
	#   tool query (string)
	local tool_name user_query handler
	tool_name="$1"
	user_query="$2"

	# Select the appropriate derivation function
	handler="$(tool_query_deriver "${tool_name}")"

	# Invoke the derivation function
	"${handler}" "${user_query}"
}

emit_plan_json() {
	# Converts plan entries into a normalized JSON array.
	# Arguments:
	#   $1 - plan entries string
	# Returns:
	#   normalized plan JSON array (string)

	local plan_entries
	plan_entries="$1"

	# Normalize the plan entries into a JSON array
	printf '%s\n' "${plan_entries}" |
		sed '/^[[:space:]]*$/d' |
		jq -sc 'map(select(type=="object"))'
}

derive_allowed_tools_from_plan() {
	# Derives the required tool list from a planner response.
	# Arguments:
	#   $1 - planner response JSON array
	# Returns:
	#   newline-delimited list of required tool names (string)
	local plan_json tool seen
	plan_json="${1:-[]}"

	# Normalize the plan JSON
	plan_json="$(normalize_plan <<<"${plan_json}")" || return 1

	# Derive the unique tool list
	seen=""
	local -a required=()

	# Collect unique tool names
	while IFS= read -r tool; do
		[[ -z "${tool}" ]] && continue
		if grep -Fxq "${tool}" <<<"${seen}"; then
			continue
		fi
		required+=("${tool}")
		seen+="${tool}"$'\n'
	done < <(jq -r '.[] | .tool // empty' <<<"${plan_json}" 2>/dev/null || true)

	# Return the required tool list
	printf '%s\n' "${required[@]}"
}

plan_json_to_entries() {
	local plan_json
	plan_json="$1"

	# Normalize the plan JSON
	plan_json="$(normalize_plan <<<"${plan_json}")" || return 1

	# Convert the plan JSON into entries
	printf '%s' "${plan_json}"
}

EXECUTOR_ENTRYPOINT=${EXECUTOR_ENTRYPOINT:-"${PLANNING_LIB_DIR}/../executor/loop.sh"}

if [[ "${PLANNER_SKIP_TOOL_LOAD:-false}" == true ]]; then
	log "DEBUG" "Skipping executor entrypoint load" "planner_skip_tool_load=true" >&2
else
	if [[ ! -f "${EXECUTOR_ENTRYPOINT}" ]]; then
		log "ERROR" "Executor entrypoint missing" "EXECUTOR_ENTRYPOINT=${EXECUTOR_ENTRYPOINT}" >&2
		return 1 2>/dev/null
	fi

	# shellcheck source=src/lib/executor/loop.sh
	source "${EXECUTOR_ENTRYPOINT}"
fi
