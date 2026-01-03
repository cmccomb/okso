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
#   - Select the execution strategy (direct response vs. executor loop).
#
# Expected types (namespaced JSON scoped by a settings prefix):
#   ${settings_prefix}_json.version (string): application version.
#   ${settings_prefix}_json.llama_bin (string): llama.cpp binary path.
#   ${settings_prefix}_json.default_model_file (string): default GGUF filename for executor runs.
#   ${settings_prefix}_json.default_planner_model_file (string): default GGUF filename for the planner.
#   ${settings_prefix}_json.config_dir (string): directory for config file.
#   ${settings_prefix}_json.config_file (string): path to the config file.
#   ${settings_prefix}_json.cache_dir (string): base directory for prompt caches.
#   ${settings_prefix}_json.planner_cache_file (string): prompt cache file used for planner calls.
#   ${settings_prefix}_json.executor_cache_file (string): prompt cache file used for executor calls.
#   ${settings_prefix}_json.run_id (string): run identifier scoping executor caches.
#   ${settings_prefix}_json.planner_model_spec (string): HF repo[:file] spec for planner llama.cpp.
#   ${settings_prefix}_json.planner_model_branch (string): branch or tag for planner downloads.
#   ${settings_prefix}_json.planner_model_repo (string): parsed planner HF repo.
#   ${settings_prefix}_json.planner_model_file (string): parsed planner HF file.
#   ${settings_prefix}_json.executor_model_spec (string): HF repo[:file] spec for executor llama.cpp.
#   ${settings_prefix}_json.executor_model_branch (string): branch or tag for executor downloads.
#   ${settings_prefix}_json.executor_model_repo (string): parsed executor HF repo.
#   ${settings_prefix}_json.executor_model_file (string): parsed executor HF file.
#   ${settings_prefix}_json.approve_all (bool string): true to bypass prompts.
#   ${settings_prefix}_json.force_confirm (bool string): true to force prompts.
#   ${settings_prefix}_json.dry_run (bool string): true to avoid execution.
#   ${settings_prefix}_json.plan_only (bool string): true to emit plan JSON only.
#   ${settings_prefix}_json.verbosity (int string): log verbosity level.
#   ${settings_prefix}_json.notes_dir (string): notes storage directory.
#   ${settings_prefix}_json.llama_available (bool string): llama binary availability.
#   ${settings_prefix}_json.use_executor_llama (bool string): toggle executor llama usage.
#   ${settings_prefix}_json.is_macos (bool string): detected macOS flag.
#   ${settings_prefix}_json.command (string): operational mode.
#   ${settings_prefix}_json.user_query (string): provided user query.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - config.sh, cli.sh, planner.sh
#
# Exit codes:
#   0 for success, non-zero bubbled from downstream helpers.

RUNTIME_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./core/errors.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/core/errors.sh"
# shellcheck source=./formatting.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/formatting.sh"
# shellcheck source=./tools/query.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/tools/query.sh"
# shellcheck source=./core/json_state.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/core/json_state.sh"
# shellcheck source=./core/settings.sh disable=SC1091
source "${RUNTIME_LIB_DIR}/core/settings.sh"

set_by_name() {
	# Sets a variable by name using printf for safety.
	# Arguments:
	#   $1 - variable name (string)
	#   $2 - value (string)
	# Returns:
	#   None.
	printf -v "$1" '%s' "$2"
}

settings_field_mappings() {
	# Outputs newline-delimited key-variable mappings for settings fields.
	# Each line contains a settings key and the corresponding global variable name.
	# Returns:
	#   Newline-delimited key-variable pairs on stdout.

	cat <<'EOF'
version VERSION
llama_bin LLAMA_BIN
default_model_file DEFAULT_MODEL_FILE
default_planner_model_file DEFAULT_PLANNER_MODEL_FILE
config_dir CONFIG_DIR
config_file CONFIG_FILE
run_id RUN_ID
planner_model_spec PLANNER_MODEL_SPEC
planner_model_branch PLANNER_MODEL_BRANCH
executor_model_spec EXECUTOR_MODEL_SPEC
executor_model_branch EXECUTOR_MODEL_BRANCH
rephraser_model_spec SEARCH_REPHRASER_MODEL_SPEC
rephraser_model_branch SEARCH_REPHRASER_MODEL_BRANCH
planner_model_repo PLANNER_MODEL_REPO
planner_model_file PLANNER_MODEL_FILE
executor_model_repo EXECUTOR_MODEL_REPO
executor_model_file EXECUTOR_MODEL_FILE
rephraser_model_repo SEARCH_REPHRASER_MODEL_REPO
rephraser_model_file SEARCH_REPHRASER_MODEL_FILE
approve_all APPROVE_ALL
verbosity VERBOSITY
notes_dir NOTES_DIR
llama_available LLAMA_AVAILABLE
use_executor_llama USE_EXECUTOR_LLAMA
is_macos IS_MACOS
command COMMAND
user_query USER_QUERY
EOF
}

apply_settings_to_globals() {
	# Applies settings from the JSON state to global variables.
	# Arguments:
	#   $1 - settings namespace prefix
	# Returns:
	#   None.
	local settings_prefix
	settings_prefix="$1"

	local json key var value
	json="$(json_state_get_document "${settings_prefix}")"

	while read -r key var; do
		[[ -z "${key}" ]] && continue
		value=$(jq -r --arg key "${key}" '.[$key] // ""' <<<"${json}")
		set_by_name "${var}" "${value}"
	done <<<"$(settings_field_mappings)"
}

capture_globals_into_settings() {
	# Captures global variables back into the JSON state settings.
	# Arguments:
	#   $1 - settings namespace prefix
	# Returns:
	#   None.

	local settings_prefix
	settings_prefix="$1"

	local key var value
	while read -r key var; do
		[[ -z "${key}" ]] && continue
		value="${!var-}"
		json_state_set_key "${settings_prefix}" "${key}" "${value}"
	done <<<"$(settings_field_mappings)"
}

load_runtime_settings() {
	# Loads and applies runtime settings from defaults, config files, and CLI arguments.
	# Arguments:
	#   $1 - settings namespace prefix
	#   $@ - CLI arguments for parsing
	# Returns:
	#  None.
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

	capture_globals_into_settings "${settings_prefix}"
}

prepare_environment_with_settings() {
	# Prepares the runtime environment and tool registry using the provided settings.
	# Arguments:
	#   $1 - settings namespace prefix to use and update
	# Returns:
	#   None.

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
	# Renders plan outputs for dry-run and plan-only modes.
	# Arguments:
	#   $1 - name of variable to receive action ("continue" or "exit")
	#   $2 - settings namespace prefix
	#   $3 - required tools list (newline delimited)
	#   $4 - plan entries string
	#   $5 - plan outline text
	#   $6 - planner response JSON
	# Returns:
	#   None.
	local action_var settings_prefix
	action_var="$1"
	settings_prefix="$2"
	local required_tools plan_entries plan_outline plan_response
	required_tools="$3"
	plan_entries="$4"
	plan_outline="$5"
	plan_response="$6"

	set_by_name "${action_var}" "continue"

	# Handle plan-only mode
	local plan_json tool_list_json
	if [[ -n "${plan_response}" ]]; then
		plan_json="${plan_response}"
	else
		plan_json="$(emit_plan_json "${plan_entries}")"
	fi
	tool_list_json="$(printf '%s' "${required_tools}" | jq -Rsc 'split("\n") | map(select(length>0))')"

	# Handle plan-only mode
	if [[ -z "${required_tools}" ]]; then
		log "INFO" "Suggested tools" "none"
	else
		log_pretty "INFO" "Suggested tools" "${tool_list_json}"
	fi

	# Handle dry-run mode
	if [[ -n "${plan_outline}" ]]; then
		log_pretty "INFO" "Plan outline" "${plan_outline}"
	fi
}

select_response_strategy() {
	# Selects and invokes the response strategy based on settings.
	# Arguments:
	#   $1 - settings namespace prefix
	#   $2 - required tools string
	#   $3 - plan entries string
	#   $4 - plan outline text
	#   $5 - planner response JSON
	# Returns:
	#   None.
	local settings_prefix
	settings_prefix="$1"
	shift
	local required_tools plan_entries plan_outline plan_response
	required_tools="$1"
	plan_entries="$2"
	plan_outline="$3"
	plan_response="$4"

	apply_settings_to_globals "${settings_prefix}"

	local user_query
	user_query="$(json_state_get_key "${settings_prefix}" "user_query")"
	if [[ -z "${user_query}" ]]; then
		user_query="${USER_QUERY:-}"
	fi

	executor_loop "${user_query}" "${required_tools}" "${plan_entries}" "${plan_outline}"
}
