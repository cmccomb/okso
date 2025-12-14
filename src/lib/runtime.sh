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
#   ${settings_prefix}_json.default_model_file (string): default GGUF filename.
#   ${settings_prefix}_json.config_dir (string): directory for config file.
#   ${settings_prefix}_json.config_file (string): path to the config file.
#   ${settings_prefix}_json.model_spec (string): HF repo[:file] spec for downloads.
#   ${settings_prefix}_json.model_branch (string): branch or tag for downloads.
#   ${settings_prefix}_json.model_repo (string): parsed HF repo.
#   ${settings_prefix}_json.model_file (string): parsed HF file.
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
#   - bash 3+
#   - jq
#   - config.sh, cli.sh, planner.sh, respond.sh
#
# Exit codes:
#   0 for success, non-zero bubbled from downstream helpers.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./errors.sh disable=SC1091
source "${LIB_DIR}/errors.sh"
# shellcheck source=./formatting.sh disable=SC1091
source "${LIB_DIR}/formatting.sh"
# shellcheck source=./json_state.sh disable=SC1091
source "${LIB_DIR}/json_state.sh"

if ! command -v jq >/dev/null 2>&1; then
	die runtime dependency "Missing jq dependency. Install jq with your package manager (e.g., apt-get install jq or brew install jq) and re-run."
fi

settings_namespace_json_var() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	json_state_namespace_var "$@"
}

settings_get_json_document() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	json_state_get_document "$1" '{}'
}

settings_set_json_document() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - JSON document (string)
	json_state_set_document "$@"
}

settings_clear_namespace() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	settings_set_json_document "$1" '{}'
}

settings_set() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	#   $3 - value (string)
	settings_set_json "$1" "$2" "$3"
}

settings_get() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	settings_get_json "$1" "$2"
}

settings_set_json() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	#   $3 - value (string)
	json_state_set_key "$@"
}

settings_get_json() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	json_state_get_key "$@"
}

set_by_name() {
	# Arguments:
	#   $1 - variable name (string)
	#   $2 - value (string)
	printf -v "$1" '%s' "$2"
}

create_default_settings() {
	# Arguments:
	#   $1 - settings namespace prefix
	local settings_prefix config_dir default_model_file config_file model_spec new_settings_json
	settings_prefix="$1"

	settings_clear_namespace "${settings_prefix}"

	config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
	default_model_file="${DEFAULT_MODEL_FILE_BASE:-Qwen_Qwen3-4B-Q4_K_M.gguf}"
	config_file="${config_dir}/config.env"
	model_spec="${DEFAULT_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-4B-GGUF:${default_model_file}}"

	new_settings_json=$(jq -c -n \
		--arg version "0.1.0" \
		--arg llama_bin "${LLAMA_BIN:-llama-cli}" \
		--arg default_model_file "${default_model_file}" \
		--arg config_dir "${config_dir}" \
		--arg config_file "${config_file}" \
		--arg model_spec "${model_spec}" \
		--arg model_branch "${DEFAULT_MODEL_BRANCH_BASE:-main}" \
		--arg notes_dir "${HOME}/.okso" \
		--arg use_react_llama "${USE_REACT_LLAMA:-true}" \
		'{
                        version: $version,
                        llama_bin: $llama_bin,
                        default_model_file: $default_model_file,
                        config_dir: $config_dir,
                        config_file: $config_file,
                        model_spec: $model_spec,
                        model_branch: $model_branch,
                        model_repo: "",
                        model_file: "",
                        approve_all: "false",
                        force_confirm: "false",
                        dry_run: "false",
                        plan_only: "false",
                        verbosity: "1",
                        notes_dir: $notes_dir,
                        llama_available: "true",
                        use_react_llama: $use_react_llama,
                        is_macos: "false",
                        command: "run",
                        user_query: ""
                }')

	settings_set_json_document "${settings_prefix}" "${new_settings_json}"
}

settings_field_mappings() {
	cat <<'EOF'
version VERSION
llama_bin LLAMA_BIN
default_model_file DEFAULT_MODEL_FILE
config_dir CONFIG_DIR
config_file CONFIG_FILE
model_spec MODEL_SPEC
model_branch MODEL_BRANCH
model_repo MODEL_REPO
model_file MODEL_FILE
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
	hydrate_model_spec

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
		while IFS='|' read -r _tool query _score; do
			[[ -z "${query}" ]] && continue
			log "INFO" "Planned query" "${query}"
		done <<<"${plan_entries}"
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
