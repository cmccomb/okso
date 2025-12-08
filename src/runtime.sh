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
# Expected types (namespaced variables scoped by a settings prefix):
#   ${settings_prefix}__version (string): application version.
#   ${settings_prefix}__llama_bin (string): llama.cpp binary path.
#   ${settings_prefix}__default_model_file (string): default GGUF filename.
#   ${settings_prefix}__config_dir (string): directory for config file.
#   ${settings_prefix}__config_file (string): path to the config file.
#   ${settings_prefix}__model_spec (string): HF repo[:file] spec for downloads.
#   ${settings_prefix}__model_branch (string): branch or tag for downloads.
#   ${settings_prefix}__model_repo (string): parsed HF repo.
#   ${settings_prefix}__model_file (string): parsed HF file.
#   ${settings_prefix}__approve_all (bool string): true to bypass prompts.
#   ${settings_prefix}__force_confirm (bool string): true to force prompts.
#   ${settings_prefix}__dry_run (bool string): true to avoid execution.
#   ${settings_prefix}__plan_only (bool string): true to emit plan JSON only.
#   ${settings_prefix}__verbosity (int string): log verbosity level.
#   ${settings_prefix}__notes_dir (string): notes storage directory.
#   ${settings_prefix}__llama_available (bool string): llama binary availability.
#   ${settings_prefix}__use_react_llama (bool string): toggle react llama usage.
#   ${settings_prefix}__is_macos (bool string): detected macOS flag.
#   ${settings_prefix}__command (string): operational mode.
#   ${settings_prefix}__user_query (string): provided user query.
#
# Dependencies:
#   - bash 3+
#   - config.sh, cli.sh, planner.sh, respond.sh
#
# Exit codes:
#   0 for success, non-zero bubbled from downstream helpers.

# shellcheck source=./errors.sh disable=SC1091
source "${BASH_SOURCE[0]%/runtime.sh}/errors.sh"

# Simple namespaced settings helpers to avoid associative-array dependencies on
# macOS's legacy Bash 3.2. All values are stored as ${namespace}__<key>
# variables and accessed via indirection to keep the call sites readable.
settings_namespace_var() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	printf '%s__%s' "$1" "$2"
}

settings_clear_namespace() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	local prefix var
	prefix="$1__"

	while IFS= read -r var; do
		unset "${var}"
	done < <(compgen -v | while IFS= read -r candidate; do
		case "${candidate}" in
		"${prefix}"*) printf '%s\n' "${candidate}" ;;
		esac
	done)
}

settings_set() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	#   $3 - value (string)
	local var_name
	var_name=$(settings_namespace_var "$1" "$2")
	printf -v "${var_name}" '%s' "$3"
}

settings_get() {
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	local var_name
	var_name=$(settings_namespace_var "$1" "$2")
	printf '%s' "${!var_name-}"
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
	local settings_prefix
	settings_prefix="$1"

	settings_clear_namespace "${settings_prefix}"

	# Defaults mirror the baked-in CLI behavior; downstream layers can override
	# via config files, environment variables, and argument parsing.
	settings_set "${settings_prefix}" "version" "0.1.0"
	settings_set "${settings_prefix}" "llama_bin" "${LLAMA_BIN:-llama-cli}"
	settings_set "${settings_prefix}" "default_model_file" "${DEFAULT_MODEL_FILE_BASE:-Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf}"
	settings_set "${settings_prefix}" "config_dir" "${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
	settings_set "${settings_prefix}" "config_file" "$(settings_get "${settings_prefix}" "config_dir")/config.env"
	settings_set "${settings_prefix}" "model_spec" "${DEFAULT_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF:$(settings_get "${settings_prefix}" "default_model_file")}"
	settings_set "${settings_prefix}" "model_branch" "${DEFAULT_MODEL_BRANCH_BASE:-main}"
	settings_set "${settings_prefix}" "model_repo" ""
	settings_set "${settings_prefix}" "model_file" ""
	settings_set "${settings_prefix}" "approve_all" "false"
	settings_set "${settings_prefix}" "force_confirm" "false"
	settings_set "${settings_prefix}" "dry_run" "false"
	settings_set "${settings_prefix}" "plan_only" "false"
	settings_set "${settings_prefix}" "verbosity" "1"
	settings_set "${settings_prefix}" "notes_dir" "${HOME}/.okso"
	settings_set "${settings_prefix}" "llama_available" "true"
	settings_set "${settings_prefix}" "use_react_llama" "${USE_REACT_LLAMA:-false}"
	settings_set "${settings_prefix}" "is_macos" "false"
	settings_set "${settings_prefix}" "command" "run"
	settings_set "${settings_prefix}" "user_query" ""
}

apply_settings_to_globals() {
	# Arguments:
	#   $1 - settings namespace prefix
	local settings_prefix
	settings_prefix="$1"

	VERSION="$(settings_get "${settings_prefix}" "version")"
	LLAMA_BIN="$(settings_get "${settings_prefix}" "llama_bin")"
	DEFAULT_MODEL_FILE="$(settings_get "${settings_prefix}" "default_model_file")"
	CONFIG_DIR="$(settings_get "${settings_prefix}" "config_dir")"
	CONFIG_FILE="$(settings_get "${settings_prefix}" "config_file")"
	MODEL_SPEC="$(settings_get "${settings_prefix}" "model_spec")"
	MODEL_BRANCH="$(settings_get "${settings_prefix}" "model_branch")"
	MODEL_REPO="$(settings_get "${settings_prefix}" "model_repo")"
	MODEL_FILE="$(settings_get "${settings_prefix}" "model_file")"
	APPROVE_ALL="$(settings_get "${settings_prefix}" "approve_all")"
	FORCE_CONFIRM="$(settings_get "${settings_prefix}" "force_confirm")"
	DRY_RUN="$(settings_get "${settings_prefix}" "dry_run")"
	PLAN_ONLY="$(settings_get "${settings_prefix}" "plan_only")"
	VERBOSITY="$(settings_get "${settings_prefix}" "verbosity")"
	NOTES_DIR="$(settings_get "${settings_prefix}" "notes_dir")"
	LLAMA_AVAILABLE="$(settings_get "${settings_prefix}" "llama_available")"
	USE_REACT_LLAMA="$(settings_get "${settings_prefix}" "use_react_llama")"
	IS_MACOS="$(settings_get "${settings_prefix}" "is_macos")"
	COMMAND="$(settings_get "${settings_prefix}" "command")"
	USER_QUERY="$(settings_get "${settings_prefix}" "user_query")"
}

capture_globals_into_settings() {
	# Arguments:
	#   $1 - settings namespace prefix
	local settings_prefix
	settings_prefix="$1"

	settings_set "${settings_prefix}" "version" "${VERSION}"
	settings_set "${settings_prefix}" "llama_bin" "${LLAMA_BIN}"
	settings_set "${settings_prefix}" "default_model_file" "${DEFAULT_MODEL_FILE}"
	settings_set "${settings_prefix}" "config_dir" "${CONFIG_DIR}"
	settings_set "${settings_prefix}" "config_file" "${CONFIG_FILE}"
	settings_set "${settings_prefix}" "model_spec" "${MODEL_SPEC}"
	settings_set "${settings_prefix}" "model_branch" "${MODEL_BRANCH}"
	settings_set "${settings_prefix}" "model_repo" "${MODEL_REPO}"
	settings_set "${settings_prefix}" "model_file" "${MODEL_FILE}"
	settings_set "${settings_prefix}" "approve_all" "${APPROVE_ALL}"
	settings_set "${settings_prefix}" "force_confirm" "${FORCE_CONFIRM}"
	settings_set "${settings_prefix}" "dry_run" "${DRY_RUN}"
	settings_set "${settings_prefix}" "plan_only" "${PLAN_ONLY}"
	settings_set "${settings_prefix}" "verbosity" "${VERBOSITY}"
	settings_set "${settings_prefix}" "notes_dir" "${NOTES_DIR}"
	settings_set "${settings_prefix}" "llama_available" "${LLAMA_AVAILABLE}"
	settings_set "${settings_prefix}" "use_react_llama" "${USE_REACT_LLAMA}"
	settings_set "${settings_prefix}" "is_macos" "${IS_MACOS}"
	settings_set "${settings_prefix}" "command" "${COMMAND}"
	settings_set "${settings_prefix}" "user_query" "${USER_QUERY}"
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

	if [[ "$(settings_get "${settings_prefix}" "plan_only")" == true ]]; then
		# plan-only short-circuits execution and dry-run emission; callers handle
		# the resulting action_ref to exit early.
		emit_plan_json "${plan_entries}"
		set_by_name "${action_var}" "exit"
		return 0
	fi

	if [[ "$(settings_get "${settings_prefix}" "dry_run")" == true ]]; then
		# Dry run prints the intended commands for operator inspection while still
		# providing the serialized JSON plan for automation.
		printf 'Dry run: planned tool calls (no execution).\n'
		emit_plan_json "${plan_entries}"
		while IFS='|' read -r _tool query _score; do
			[[ -z "${query}" ]] && continue
			printf '%s\n' "${query}"
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
	local required_tools plan_entries plan_outline
	required_tools="$1"
	plan_entries="$2"
	plan_outline="$3"

	apply_settings_to_globals "${settings_prefix}"

	if [[ -z "${required_tools}" ]]; then
		# The planner may occasionally decline tools; fall back to direct text
		# responses so the user still receives output.
		log "WARN" "No tools selected; responding directly" "${USER_QUERY}"
		printf 'No tools selected; responding directly.\n'
		printf '%s\n' "$(respond_text "${USER_QUERY}" 256)"
		printf 'Execution summary: no tool runs.\n'
		return 0
	fi

	react_loop "${USER_QUERY}" "${required_tools}" "${plan_entries}" "${plan_outline}"
}
