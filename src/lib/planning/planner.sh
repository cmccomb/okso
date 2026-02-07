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
#   APPROVE_ALL (bool): confirmation toggles.
#   VERBOSITY (int): log level.
#   PLANNER_SKIP_TOOL_LOAD (bool): skip sourcing the tool suite; useful for tests.
#   PLANNER_SAMPLE_COUNT (int >=1): reserved; planner sampling is currently pinned to a single candidate.
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

# shellcheck source=src/lib/core/logging.sh
source "${PLANNING_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/tools/index.sh
if [[ "${PLANNER_SKIP_TOOL_LOAD:-false}" != true ]]; then
	source "${PLANNING_LIB_DIR}/../tools/index.sh"
else
	log "DEBUG" "Skipping tool suite load" "planner_skip_tool_load=true" >&2
fi
# shellcheck source=src/lib/llm/schema.sh
source "${PLANNING_LIB_DIR}/../llm/schema.sh"
# shellcheck source=src/lib/llm/llama_client.sh
source "${PLANNING_LIB_DIR}/../llm/llama_client.sh"
# shellcheck source=src/lib/settings/config.sh
source "${PLANNING_LIB_DIR}/../settings/config.sh"
# shellcheck source=src/lib/planning/normalization.sh
source "${PLANNING_LIB_DIR}/normalization.sh"
# shellcheck source=src/lib/planning/scoring.sh
source "${PLANNING_LIB_DIR}/scoring.sh"
# shellcheck source=src/lib/planning/prompting.sh
source "${PLANNING_LIB_DIR}/prompting.sh"
# shellcheck source=src/lib/intent/intent.sh
source "${PLANNING_LIB_DIR}/../intent/intent.sh"
# shellcheck source=src/lib/planning/search.sh
source "${PLANNING_LIB_DIR}/search.sh"

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

planner_collect_tools() {
	# Builds the planner tool catalog from caller-provided overrides or the
	# registered tool registry.
	# Arguments:
	#   $1 - optional newline-delimited tool list override (string)
	# Returns:
	#   newline-delimited list of tool names on stdout.

	local -a catalog=()
	local tool_override
	tool_override="${1:-}"

	if [[ -n "${tool_override}" ]]; then
		while IFS= read -r tool_name; do
			[[ -z "${tool_name}" ]] && continue
			catalog+=("${tool_name}")
		done <<<"${tool_override}"
	fi

	# Reuse caller-provided TOOLS array when available.
	# shellcheck disable=SC2153
	if [[ ${#catalog[@]} -eq 0 ]] && declare -p TOOLS >/dev/null 2>&1; then
		local tools_decl
		tools_decl="$(declare -p TOOLS 2>/dev/null || true)"
		if [[ "${tools_decl}" == declare\ -a* || "${tools_decl}" == declare\ -ax* ]]; then
			local tool_name
			for tool_name in "${TOOLS[@]-}"; do
				[[ -z "${tool_name}" ]] && continue
				catalog+=("${tool_name}")
			done
		fi
	fi

	# Fall back to the registry if no explicit TOOLS were supplied.
	if [[ ${#catalog[@]} -eq 0 ]]; then
		if command -v tool_names >/dev/null 2>&1; then
			while IFS= read -r tool_name; do
				[[ -z "${tool_name}" ]] && continue
				catalog+=("${tool_name}")
			done < <(tool_names)
		else
			log "WARN" "Tool catalog unavailable; no tools registered" "planner_tools=0" >&2
		fi
	fi

	if [[ ${#catalog[@]} -gt 0 ]]; then
		printf '%s\n' "${catalog[@]-}"
	fi
}

planner_build_plan_schema() {
	# Compiles the planner schema using registered tool argument schemas.
	# Arguments:
	#   $@ - tool names available to the planner (strings)
	# Returns:
	#   Planner plan schema JSON on stdout; non-zero on failure.
	local base_schema tool_schema_json tools_json branches

	base_schema="$(load_schema_text planner_plan | jq -c '.')" || return 1

	tool_schema_json="$(
		canonicalize_schema_for_llama "$(tool_schema_map)" | jq -c '
    def fill_placeholder:
      {
        type: "object",
        additionalProperties: false,
        required: ["__fill__"],
        properties: {"__fill__": {const: true}}
      };
    def allow_fill_top_level:
      if type != "object" then .
      else
        (
          .
          | if has("properties") and (.properties | type == "object") then
              .properties |= with_entries(.value |= {anyOf: [., fill_placeholder]})
            else
              .
            end
        )
        | {anyOf: [., fill_placeholder]}
      end;

    map_values(allow_fill_top_level)
  '
	)" || return 1
	tools_json="$(printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(length > 0))')"

	if [[ "${tools_json}" == "[]" ]]; then
		printf '%s' "${base_schema}"
		return 0
	fi

	branches=$(jq -nc \
		--argjson toolSchemas "${tool_schema_json}" \
		--argjson tools "${tools_json}" \
		'[
                        $tools[] |
                        {
                                type: "object",
                                additionalProperties: false,
                                required: ["thought", "tool", "args"],
                                properties: {
                                        thought: {type: "string", minLength: 5},
                                        tool: {type: "string", enum: [.]},
                                        args: ($toolSchemas[.] // {type: "object"})
                                }
                        }
                ]') || return 1

	jq -n -c --argjson base "${base_schema}" --argjson anyOf "${branches}" '
                $base | .items = {anyOf: $anyOf}
        '
}
export -f planner_build_plan_schema

# planner_format_search_context and planner_fetch_search_context moved to search.sh

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

planner_format_intent_context() {
	# Formats intent data for the planner prompt.
	# Arguments:
	#   $1 - intent JSON payload (string)
	#   $2... - allowed tool names (strings)
	# Returns:
	#   intent context string on stdout.
	local intent_json intent_labels rationale tool_catalog
	intent_json="$1"
	shift

	if [[ -z "${intent_json}" ]]; then
		printf '%s' "None provided."
		return 0
	fi

	intent_labels="$(jq -r 'if .intents and (.intents | length > 0) then (.intents | join(",")) else .intent // "" end' <<<"${intent_json}" 2>/dev/null)"
	rationale="$(jq -r '.rationale // ""' <<<"${intent_json}" 2>/dev/null)"

	if [[ -z "${intent_labels}" ]]; then
		printf '%s' "None provided."
		return 0
	fi

	tool_catalog="$(printf '%s\n' "$@" | paste -sd ',' -)"
	if [[ -z "${tool_catalog}" ]]; then
		tool_catalog="none"
	fi

	printf '%s' "intents=${intent_labels} rationale=${rationale} allowed_tools=${tool_catalog}"
}

generate_planner_response_with_context() {
	# Arguments:
	#   $1 - user query (string)
	#   $2 - preformatted search context (string)
	#   $3 - allowed tool list override (string, optional)
	#   $4 - intent JSON payload (string, optional)
	# Returns:
	#   planner response JSON (string)
	local user_query search_context tool_override intent_json
	local -a planner_tools=()
	user_query="$1"
	search_context="$2"
	tool_override="${3:-}"
	intent_json="${4:-}"

	# Initialize settings for planner and executor models
	initialize_planner_models

	# Assemble the tool catalog
	planner_tools=()
	while IFS= read -r tool_name; do
		[[ -z "${tool_name}" ]] && continue
		planner_tools+=("${tool_name}")
	done < <(planner_collect_tools "${tool_override}")

	# Log the tool catalog for operator visibility
	local planner_tool_catalog
	planner_tool_catalog="$(printf '%s\n' "${planner_tools[@]-}" | paste -sd ',' -)"
	log "DEBUG" "Planner tool catalog" "${planner_tool_catalog}" >&2

	if [[ "${LLAMA_AVAILABLE:-true}" != true ]]; then
		log "WARN" "LLM unavailable; emitting fallback planner response" "llama_available=false" >&2
		jq -nc '[{
			tool: "final_answer",
			args: {input: "Model unavailable. Responding directly without tool execution."},
			thought: "Provide a safe fallback response when planner inference is unavailable."
		}]'
		return 0
	fi

	# Build the planner prompt
	local planner_schema_text tool_lines prompt intent_context
	planner_schema_text="$(planner_build_plan_schema "${planner_tools[@]-}")"
	tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${planner_tools[@]-}")" format_tool_line)"
	intent_context="$(planner_format_intent_context "${intent_json}" "${planner_tools[@]-}")"
	prompt="$(build_planner_prompt "${user_query}" "${tool_lines}" "${search_context}" "${PLANNER_FEEDBACK_CONTEXT:-}" "${planner_schema_text}" "${intent_context}")"
	log "DEBUG" "Generated planner prompt" "${prompt}" >&2

	# Configure generation parameters
	local temperature debug_log_dir debug_log_file max_generation_tokens
	local raw_plan normalized_plan criteria_report replan_feedback prompt_feedback
	temperature="$(validate_temperature "${PLANNER_TEMPERATURE:-0.7}" 0.7)"
	max_generation_tokens="$(validate_positive_int "${PLANNER_MAX_OUTPUT_TOKENS:-1024}" 1024 "PLANNER_MAX_OUTPUT_TOKENS")"

	log "INFO" "Planner generation configuration" "$(jq -nc --arg temperature "${temperature}" '{mode:"single_pass",temperature:$temperature}')" >&2

	if ! [[ "${max_generation_tokens}" =~ ^[0-9]+$ ]] || ((max_generation_tokens < 1)); then
		max_generation_tokens=1024
	fi

	debug_log_dir="${TMPDIR:-/tmp}"
	debug_log_file="${PLANNER_DEBUG_LOG:-${debug_log_dir%/}/okso_planner_candidates.log}"
	mkdir -p "$(dirname "${debug_log_file}")" 2>/dev/null || true
	: >"${debug_log_file}" 2>/dev/null || true

	raw_plan="$(LLAMA_TEMPERATURE="${temperature}" llama_infer "${prompt}" '' "${max_generation_tokens}" "${planner_schema_text}" "${PLANNER_MODEL_REPO:-}" "${PLANNER_MODEL_FILE:-}" "${PLANNER_CACHE_FILE:-}" "${prompt}")"
	if ! normalized_plan="$(normalize_plan <<<"${raw_plan}")"; then
		log "ERROR" "Planner output unusable from llama.cpp" "${raw_plan}" >&2
		return 1
	fi

	if ! criteria_report="$(planner_plan_criteria_report "${normalized_plan}")"; then
		log "ERROR" "Planner criteria check failed" "criteria_evaluation_error" >&2
		return 1
	fi

	jq -nc \
		--argjson attempt 1 \
		--argjson response "${normalized_plan}" \
		--argjson criteria "${criteria_report}" \
		'{attempt:$attempt,response:$response,criteria:$criteria}' >>"${debug_log_file}" 2>/dev/null || true

	if jq -e '.ok == true' <<<"${criteria_report}" >/dev/null 2>&1; then
		printf '%s' "${normalized_plan}"
		return 0
	fi

	replan_feedback="$(jq -r '.reasons | join(" ")' <<<"${criteria_report}" 2>/dev/null || printf 'Planner criteria failed.')"
	log "WARN" "Planner candidate failed required criteria; replanning once" "${replan_feedback}" >&2

	prompt_feedback="${PLANNER_FEEDBACK_CONTEXT:-}"
	if [[ -n "${prompt_feedback}" ]]; then
		prompt_feedback+=$'\n'
	fi
	prompt_feedback+="Criteria retry request: ${replan_feedback}"
	prompt="$(build_planner_prompt "${user_query}" "${tool_lines}" "${search_context}" "${prompt_feedback}" "${planner_schema_text}" "${intent_context}")"

	raw_plan="$(LLAMA_TEMPERATURE="${temperature}" llama_infer "${prompt}" '' "${max_generation_tokens}" "${planner_schema_text}" "${PLANNER_MODEL_REPO:-}" "${PLANNER_MODEL_FILE:-}" "${PLANNER_CACHE_FILE:-}" "${prompt}")"
	if ! normalized_plan="$(normalize_plan <<<"${raw_plan}")"; then
		log "ERROR" "Planner retry output unusable from llama.cpp" "${raw_plan}" >&2
		return 1
	fi

	if ! criteria_report="$(planner_plan_criteria_report "${normalized_plan}")"; then
		log "ERROR" "Planner retry criteria check failed" "criteria_evaluation_error" >&2
		return 1
	fi

	jq -nc \
		--argjson attempt 2 \
		--argjson response "${normalized_plan}" \
		--argjson criteria "${criteria_report}" \
		'{attempt:$attempt,response:$response,criteria:$criteria}' >>"${debug_log_file}" 2>/dev/null || true

	if ! jq -e '.ok == true' <<<"${criteria_report}" >/dev/null 2>&1; then
		log "ERROR" "Planner retry failed required criteria" "$(jq -c '.reasons // []' <<<"${criteria_report}" 2>/dev/null || printf '[]')" >&2
		return 1
	fi

	printf '%s' "${normalized_plan}"
}

generate_planner_response() {
	# Arguments:
	#   $1 - user query (string)
	# Returns:
	#   planner response JSON (string)
	local user_query search_context
	user_query="$1"
	search_context="$(planner_fetch_search_context "${user_query}" "")"
	generate_planner_response_with_context "${user_query}" "${search_context}" "" ""
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

planner_fallback_plan() {
	# Returns a minimal safe plan when planner output is invalid.
	jq -nc '[{
		tool: "final_answer",
		args: {},
		thought: "Respond directly to the user."
	}]'
}

planner_extract_plan_array() {
	# Extracts a plan array from planner output objects or arrays.
	# Arguments:
	#   $1 - planner response payload (string)
	# Returns:
	#   JSON array on stdout.
	local payload extracted
	payload="${1:-[]}"

	if extracted="$(jq -c '
		if type == "array" then .
		elif type == "object" and (.plan | type == "array") then .plan
		elif type == "object" and (.plan | type == "string") then (try (.plan | fromjson) catch null)
		else null
		end
	' <<<"${payload}" 2>/dev/null)" && jq -e 'type == "array"' <<<"${extracted}" >/dev/null 2>&1; then
		printf '%s' "${extracted}"
		return 0
	fi

	planner_fallback_plan
}

derive_allowed_tools_from_plan() {
	# Derives the required tool list from a planner response.
	# Arguments:
	#   $1 - planner response JSON array
	# Returns:
	#   newline-delimited list of required tool names (string)
	local plan_json tool seen
	plan_json="${1:-[]}"

	plan_json="$(planner_extract_plan_array "${plan_json}")"

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

	if ! grep -Fxq "final_answer" <<<"${seen}"; then
		required+=("final_answer")
	fi

	# Return the required tool list
	printf '%s\n' "${required[@]}"
}

plan_json_to_entries() {
	local plan_json
	plan_json="$1"

	plan_json="$(planner_extract_plan_array "${plan_json}")"

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
