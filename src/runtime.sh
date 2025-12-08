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
# Expected types (Bash associative array values are strings unless noted):
#   settings_ref[version] (string): application version.
#   settings_ref[llama_bin] (string): llama.cpp binary path.
#   settings_ref[default_model_file] (string): default GGUF filename.
#   settings_ref[config_dir] (string): directory for config file.
#   settings_ref[config_file] (string): path to the config file.
#   settings_ref[model_spec] (string): HF repo[:file] spec for downloads.
#   settings_ref[model_branch] (string): branch or tag for downloads.
#   settings_ref[model_repo] (string): parsed HF repo.
#   settings_ref[model_file] (string): parsed HF file.
#   settings_ref[approve_all] (bool string): true to bypass prompts.
#   settings_ref[force_confirm] (bool string): true to force prompts.
#   settings_ref[dry_run] (bool string): true to avoid execution.
#   settings_ref[plan_only] (bool string): true to emit plan JSON only.
#   settings_ref[verbosity] (int string): log verbosity level.
#   settings_ref[notes_dir] (string): notes storage directory.
#   settings_ref[llama_available] (bool string): llama binary availability.
#   settings_ref[use_react_llama] (bool string): toggle react llama usage.
#   settings_ref[is_macos] (bool string): detected macOS flag.
#   settings_ref[command] (string): operational mode.
#   settings_ref[user_query] (string): provided user query.
#
# Dependencies:
#   - bash 5+
#   - config.sh, cli.sh, planner.sh, respond.sh
#
# Exit codes:
#   0 for success, non-zero bubbled from downstream helpers.

create_default_settings() {
	# Arguments:
	#   $1 - name of associative array to populate
	local settings_name
	settings_name="$1"
	declare -gA "${settings_name}"
	local -n settings_ref=$settings_name

	settings_ref=()

	settings_ref[version]="0.1.0"
	settings_ref[llama_bin]="${LLAMA_BIN:-llama-cli}"
	settings_ref[default_model_file]="Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
	settings_ref[config_dir]="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
	settings_ref[config_file]="${settings_ref[config_dir]}/config.env"
	settings_ref[model_spec]="bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF:${settings_ref[default_model_file]}"
	settings_ref[model_branch]="main"
	settings_ref[model_repo]=""
	settings_ref[model_file]=""
	settings_ref[approve_all]="false"
	settings_ref[force_confirm]="false"
	settings_ref[dry_run]="false"
	settings_ref[plan_only]="false"
	settings_ref[verbosity]="1"
	settings_ref[notes_dir]="${HOME}/.okso"
	settings_ref[llama_available]="true"
	settings_ref[use_react_llama]="${USE_REACT_LLAMA:-false}"
	settings_ref[is_macos]="false"
	settings_ref[command]="run"
	settings_ref[user_query]=""
}

apply_settings_to_globals() {
	# Arguments:
	#   $1 - name of associative array containing settings
	local -n settings_ref=$1

	VERSION="${settings_ref[version]}"
	LLAMA_BIN="${settings_ref[llama_bin]}"
	DEFAULT_MODEL_FILE="${settings_ref[default_model_file]}"
	CONFIG_DIR="${settings_ref[config_dir]}"
	CONFIG_FILE="${settings_ref[config_file]}"
	MODEL_SPEC="${settings_ref[model_spec]}"
	MODEL_BRANCH="${settings_ref[model_branch]}"
	MODEL_REPO="${settings_ref[model_repo]}"
	MODEL_FILE="${settings_ref[model_file]}"
	APPROVE_ALL="${settings_ref[approve_all]}"
	FORCE_CONFIRM="${settings_ref[force_confirm]}"
	DRY_RUN="${settings_ref[dry_run]}"
	PLAN_ONLY="${settings_ref[plan_only]}"
	VERBOSITY="${settings_ref[verbosity]}"
	NOTES_DIR="${settings_ref[notes_dir]}"
	LLAMA_AVAILABLE="${settings_ref[llama_available]}"
	USE_REACT_LLAMA="${settings_ref[use_react_llama]}"
	IS_MACOS="${settings_ref[is_macos]}"
	COMMAND="${settings_ref[command]}"
	USER_QUERY="${settings_ref[user_query]}"
}

capture_globals_into_settings() {
	# Arguments:
	#   $1 - name of associative array to update
	local -n settings_ref=$1

	settings_ref[version]="${VERSION}"
	settings_ref[llama_bin]="${LLAMA_BIN}"
	settings_ref[default_model_file]="${DEFAULT_MODEL_FILE}"
	settings_ref[config_dir]="${CONFIG_DIR}"
	settings_ref[config_file]="${CONFIG_FILE}"
	settings_ref[model_spec]="${MODEL_SPEC}"
	settings_ref[model_branch]="${MODEL_BRANCH}"
	settings_ref[model_repo]="${MODEL_REPO}"
	settings_ref[model_file]="${MODEL_FILE}"
	settings_ref[approve_all]="${APPROVE_ALL}"
	settings_ref[force_confirm]="${FORCE_CONFIRM}"
	settings_ref[dry_run]="${DRY_RUN}"
	settings_ref[plan_only]="${PLAN_ONLY}"
	settings_ref[verbosity]="${VERBOSITY}"
	settings_ref[notes_dir]="${NOTES_DIR}"
	settings_ref[llama_available]="${LLAMA_AVAILABLE}"
	settings_ref[use_react_llama]="${USE_REACT_LLAMA}"
	settings_ref[is_macos]="${IS_MACOS}"
	settings_ref[command]="${COMMAND}"
	settings_ref[user_query]="${USER_QUERY}"
}

load_runtime_settings() {
	# Arguments:
	#   $1 - name of associative array to populate
	#   $@ - CLI arguments for parsing
	local settings_name
	settings_name="$1"
	shift
	local -n settings_ref=$settings_name

	create_default_settings "${settings_name}"
	apply_settings_to_globals "${settings_name}"

	detect_config_file "$@"
	load_config
	parse_args "$@"
	normalize_approval_flags
	hydrate_model_spec

	capture_globals_into_settings "${settings_name}"
}

prepare_environment_with_settings() {
	# Arguments:
	#   $1 - name of associative array to use and update
	local settings_name
	settings_name="$1"
	local -n settings_ref=$settings_name

	apply_settings_to_globals "${settings_name}"
	init_environment
	init_tool_registry
	initialize_tools
	capture_globals_into_settings "${settings_name}"
}
# shellcheck disable=SC2034
render_plan_outputs() {
	# Arguments:
	#   $1 - name of variable to receive action ("continue" or "exit")
	#   $2 - name of settings associative array
	#   $3 - required tools list (newline delimited)
	#   $4 - plan entries string
	#   $5 - plan outline text
	local -n action_ref=$1
	local -n settings_ref=$2
	local required_tools plan_entries plan_outline
	required_tools="$3"
	plan_entries="$4"
	plan_outline="$5"

	action_ref="continue"

	if [[ -z "${required_tools}" ]]; then
		printf 'Suggested tools: none.\n'
	else
		printf 'Suggested tools:\n'
		while IFS= read -r tool; do
			[[ -z "${tool}" ]] && continue
			printf ' - %s\n' "${tool}"
		done <<<"${required_tools}"
	fi

	if [[ -n "${plan_outline}" ]]; then
		printf 'Plan outline:\n%s\n' "${plan_outline}"
	fi

	if [[ "${settings_ref[plan_only]}" == true ]]; then
		emit_plan_json "${plan_entries}"
		action_ref="exit"
		return 0
	fi

	if [[ "${settings_ref[dry_run]}" == true ]]; then
		printf 'Dry run: planned tool calls (no execution).\n'
		emit_plan_json "${plan_entries}"
		while IFS='|' read -r _tool query _score; do
			[[ -z "${query}" ]] && continue
			printf '%s\n' "${query}"
		done <<<"${plan_entries}"
		action_ref="exit"
	fi
}

select_response_strategy() {
	# Arguments:
	#   $1 - name of settings associative array
	#   $2 - required tools string
	#   $3 - plan entries string
	#   $4 - plan outline text
	local settings_name
	settings_name="$1"
	shift
	local -n settings_ref=$settings_name
	local required_tools plan_entries plan_outline
	required_tools="$1"
	plan_entries="$2"
	plan_outline="$3"

	apply_settings_to_globals "${settings_name}"

	if [[ -z "${required_tools}" ]]; then
		log "WARN" "No tools selected; responding directly" "${USER_QUERY}"
		printf 'No tools selected; responding directly.\n'
		printf '%s\n' "$(respond_text "${USER_QUERY}" 256)"
		printf 'Execution summary: no tool runs.\n'
		return 0
	fi

	react_loop "${USER_QUERY}" "${required_tools}" "${plan_entries}" "${plan_outline}"
}
