#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2154,SC2178
#
# Runtime orchestration helpers for the okso assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/runtime.sh}/runtime.sh"
#
# Responsibilities:
#   - Build structured settings from defaults, config files, and CLI arguments.
#   - Prepare the environment and tool registry using the provided settings.
#   - Render plan output handling dry-run and plan-only flows.
#   - Select the execution strategy (direct response vs. react loop).
#
# Expected types (namespaced JSON scoped by a settings prefix):
#   ${settings_prefix}_json.version (string): application version.
#   ${settings_prefix}_json.llama_bin (string): llama.cpp binary path.
#   ${settings_prefix}_json.default_model_file (string): default GGUF filename for ReAct.
#   ${settings_prefix}_json.default_planner_model_file (string): default GGUF filename for the planner.
#   ${settings_prefix}_json.config_dir (string): directory for config file.
#   ${settings_prefix}_json.config_file (string): path to the config file.
#   ${settings_prefix}_json.cache_dir (string): base directory for prompt caches.
#   ${settings_prefix}_json.planner_cache_file (string): prompt cache file used for planner calls.
#   ${settings_prefix}_json.react_cache_file (string): prompt cache file used for ReAct calls.
#   ${settings_prefix}_json.run_id (string): run identifier scoping ReAct caches.
#   ${settings_prefix}_json.planner_model_spec (string): HF repo[:file] spec for planner llama.cpp.
#   ${settings_prefix}_json.planner_model_branch (string): branch or tag for planner downloads.
#   ${settings_prefix}_json.planner_model_repo (string): parsed planner HF repo.
#   ${settings_prefix}_json.planner_model_file (string): parsed planner HF file.
#   ${settings_prefix}_json.react_model_spec (string): HF repo[:file] spec for ReAct llama.cpp.
#   ${settings_prefix}_json.react_model_branch (string): branch or tag for ReAct downloads.
#   ${settings_prefix}_json.react_model_repo (string): parsed ReAct HF repo.
#   ${settings_prefix}_json.react_model_file (string): parsed ReAct HF file.
#   ${settings_prefix}_json.approve_all (bool string): true to bypass prompts.
#   ${settings_prefix}_json.force_confirm (bool string): true to force prompts.
#   ${settings_prefix}_json.dry_run (bool string): true to avoid execution.
#   ${settings_prefix}_json.plan_only (bool string): true to emit plan JSON only.
#   ${settings_prefix}_json.verbosity (int string): log verbosity level.
#   ${settings_prefix}_json.notes_dir (string): notes storage directory.
#   ${settings_prefix}_json.llama_available (bool string): llama binary availability.
#   ${settings_prefix}_json.use_react_llama (bool string): toggle react llama usage.
#   ${settings_prefix}_json.is_macos (bool string): detected macOS flag.
#   ${settings_prefix}_json.command (string): operational mode.
#   ${settings_prefix}_json.user_query (string): provided user query.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - config.sh, cli.sh, planner.sh, assistant/respond.sh
#
# Exit codes:
#   0 for success, non-zero bubbled from downstream helpers.

RUNTIME_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./core/errors.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/core/errors.sh"
# shellcheck source=./formatting.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/formatting.sh"
# shellcheck source=./core/settings.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/core/settings.sh"

if ! command -v jq >/dev/null 2>&1; then
	die runtime dependency "Missing jq dependency. Install jq with your package manager (e.g., apt-get install jq or brew install jq) and re-run."
fi

set_by_name() {
	# Arguments:
	#   $1 - variable name (string)
	#   $2 - value (string)
	printf -v "$1" '%s' "$2"
}

settings_field_mappings() {
	cat <<'EOF'
version VERSION
llama_bin LLAMA_BIN
default_model_file DEFAULT_MODEL_FILE
default_planner_model_file DEFAULT_PLANNER_MODEL_FILE
config_dir CONFIG_DIR
config_file CONFIG_FILE
cache_dir CACHE_DIR
planner_cache_file PLANNER_CACHE_FILE
react_cache_file REACT_CACHE_FILE
run_id RUN_ID
planner_model_spec PLANNER_MODEL_SPEC
planner_model_branch PLANNER_MODEL_BRANCH
react_model_spec REACT_MODEL_SPEC
react_model_branch REACT_MODEL_BRANCH
planner_model_repo PLANNER_MODEL_REPO
planner_model_file PLANNER_MODEL_FILE
react_model_repo REACT_MODEL_REPO
react_model_file REACT_MODEL_FILE
approve_all APPROVE_ALL
force_confirm FORCE_CONFIRM
dry_run DRY_RUN
plan_only PLAN_ONLY
verbosity VERBOSITY
notes_dir NOTES_DIR
llama_available LLAMA_AVAILABLE
use_react_llama USE_REACT_LLAMA
is_macos IS_MACOS
command COMMAND
user_query USER_QUERY
EOF
}

react_run_cache_dir() {
	# Derives the directory that scopes the ReAct prompt cache for the current run.
	# Returns:
	#   The directory path (string) or empty string when unset.
	if [[ -z "${REACT_CACHE_FILE:-}" ]]; then
		printf ''
		return
	fi

	printf '%s' "$(dirname "${REACT_CACHE_FILE}")"
}

coerce_react_run_cache_path() {
	# Ensures the ReAct prompt cache is scoped to the current run directory.
	# Arguments:
	#   $1 - settings namespace prefix
	local settings_prefix cache_dir run_id cache_basename run_cache_dir coerced_path
	settings_prefix="$1"

	cache_dir="${CACHE_DIR:-$(settings_get "${settings_prefix}" "cache_dir")}" || cache_dir=""
	run_id="${RUN_ID:-$(settings_get "${settings_prefix}" "run_id")}" || run_id=""
	cache_basename="$(basename "${REACT_CACHE_FILE:-react.prompt-cache}")"

	if [[ -z "${cache_dir}" || -z "${run_id}" ]]; then
		return
	fi

	run_cache_dir="${cache_dir}/runs/${run_id}"
	coerced_path="${run_cache_dir}/${cache_basename}"
	settings_set "${settings_prefix}" "react_cache_file" "${coerced_path}"
	REACT_CACHE_FILE="${coerced_path}"
}

ensure_react_run_cache_dir() {
	# Ensures the run-scoped ReAct cache directory exists for llama.cpp caching.
	local cache_dir
	cache_dir="$(react_run_cache_dir)"

	if [[ -z "${cache_dir}" ]]; then
		return
	fi

	mkdir -p "${cache_dir}"
	REACT_RUN_CACHE_DIR="${cache_dir}"
	log "INFO" "Prepared ReAct run cache" "path=${cache_dir}"
}

cleanup_react_run_cache_dir() {
	# Cleans up the run-scoped ReAct cache directory on success and retains it on failure.
	# Arguments:
	#   $1 - exit status to evaluate
	local status cache_dir
	status="${1:-0}"
	cache_dir="${REACT_RUN_CACHE_DIR:-$(react_run_cache_dir)}"

	if [[ -z "${cache_dir}" || ! -d "${cache_dir}" ]]; then
		return
	fi

	if [[ "${status}" -eq 0 ]]; then
		rm -rf "${cache_dir}"
		log "INFO" "Cleaned ReAct run cache" "path=${cache_dir}"
		return
	fi

	log "INFO" "Retaining ReAct run cache for debugging" "path=${cache_dir} status=${status}"
}

apply_settings_to_globals() {
	# Arguments:
	#   $1 - settings namespace prefix
	local settings_prefix
	settings_prefix="$1"

	local json key var value
	json="$(settings_get_json_document "${settings_prefix}")"

	while read -r key var; do
		[[ -z "${key}" ]] && continue
		value=$(jq -r --arg key "${key}" '.[$key] // ""' <<<"${json}")
		set_by_name "${var}" "${value}"
	done <<<"$(settings_field_mappings)"
}

capture_globals_into_settings() {
	# Arguments:
	#   $1 - settings namespace prefix
	local settings_prefix
	settings_prefix="$1"

	local key var value
	while read -r key var; do
		[[ -z "${key}" ]] && continue
		value="${!var-}"
		settings_set_json "${settings_prefix}" "${key}" "${value}"
	done <<<"$(settings_field_mappings)"
}

load_runtime_settings() {
	# Arguments:
	#   $1 - settings namespace prefix
	#   $@ - CLI arguments for parsing
	local settings_prefix
	settings_prefix="$1"
	shift

	create_default_settings "${settings_prefix}"
	apply_settings_to_globals "${settings_prefix}"

	# Ordering matters: config file may update globals before CLI args take
	# precedence, matching typical UNIX expectations.
	detect_config_file "$@"
	load_config
	parse_args "$@"
	normalize_approval_flags
	hydrate_model_specs
	coerce_react_run_cache_path "${settings_prefix}"

	capture_globals_into_settings "${settings_prefix}"
}

prepare_environment_with_settings() {
	# Arguments:
	#   $1 - settings namespace prefix to use and update
	local settings_prefix
	settings_prefix="$1"

	apply_settings_to_globals "${settings_prefix}"
	init_environment
	init_tool_registry
	initialize_tools
	# Capture any mutations (e.g., resolved model paths, OS flags) back into the
	# settings structure for downstream consumers.
	capture_globals_into_settings "${settings_prefix}"
}
# shellcheck disable=SC2034
render_plan_outputs() {
	# Arguments:
	#   $1 - name of variable to receive action ("continue" or "exit")
	#   $2 - settings namespace prefix
	#   $3 - required tools list (newline delimited)
	#   $4 - plan entries string
	#   $5 - plan outline text
	local action_var settings_prefix
	action_var="$1"
	settings_prefix="$2"
	local required_tools plan_entries plan_outline
	required_tools="$3"
	plan_entries="$4"
	plan_outline="$5"

	set_by_name "${action_var}" "continue"

	local plan_json tool_list_json
	plan_json="$(emit_plan_json "${plan_entries}")"
	tool_list_json="$(printf '%s' "${required_tools}" | jq -Rsc 'split("\n") | map(select(length>0))')"

	if [[ -z "${required_tools}" ]]; then
		log "INFO" "Suggested tools" "none"
	else
		log_pretty "INFO" "Suggested tools" "${tool_list_json}"
	fi

	if [[ -n "${plan_outline}" ]]; then
		log_pretty "INFO" "Plan outline" "${plan_outline}"
	fi

	if [[ "$(settings_get "${settings_prefix}" "plan_only")" == true ]]; then
		# plan-only short-circuits execution and dry-run emission; callers handle
		# the resulting action_ref to exit early.
		log_pretty "INFO" "Plan JSON" "${plan_json}"
		set_by_name "${action_var}" "exit"
		return 0
	fi

	if [[ "$(settings_get "${settings_prefix}" "dry_run")" == true ]]; then
		# Dry run prints the intended commands for operator inspection while still
		# providing the serialized JSON plan for automation.
		log_pretty "INFO" "Dry run plan" "${plan_json}"
		printf '%s\n' "${plan_entries}" | sed '/^[[:space:]]*$/d' | while IFS= read -r entry; do
			local tool_name args_json planned_query
			tool_name="$(printf '%s' "${entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
			args_json="$(printf '%s' "${entry}" | jq -c '.args // {}' 2>/dev/null || printf '{}')"
			planned_query="$(extract_tool_query "${tool_name}" "${args_json}")"
			[[ -z "${planned_query}" ]] && continue
			log "INFO" "Planned query" "${planned_query}"
		done
		set_by_name "${action_var}" "exit"
	fi
}

select_response_strategy() {
	# Arguments:
	#   $1 - settings namespace prefix
	#   $2 - required tools string
	#   $3 - plan entries string
	#   $4 - plan outline text
	local settings_prefix
	settings_prefix="$1"
	shift
	local required_tools plan_entries plan_outline direct_response
	required_tools="$1"
	plan_entries="$2"
	plan_outline="$3"

	apply_settings_to_globals "${settings_prefix}"

	if [[ -z "${required_tools}" ]]; then
		# The planner may occasionally decline tools; fall back to direct text
		# responses so the user still receives output.
		log "ERROR" "No tools selected; responding directly" "${USER_QUERY}"
		log "INFO" "Planner emitted no tools; using direct response" "${USER_QUERY}"
		direct_response="$(respond_text "${USER_QUERY}" 256)"
		log_pretty "INFO" "Final answer" "${direct_response}"
		log "INFO" "Execution summary" "No tool runs"
		emit_boxed_summary "${USER_QUERY}" "${plan_outline}" "" "${direct_response}"
		return 0
	fi

	react_loop "${USER_QUERY}" "${required_tools}" "${plan_entries}" "${plan_outline}"
}
