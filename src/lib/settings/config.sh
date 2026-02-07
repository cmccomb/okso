#!/usr/bin/env bash
# shellcheck shell=bash
#
# Configuration helpers for the okso assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/config.sh}/config.sh"
#
# Environment variables:
#   CONFIG_FILE (string): config path; default resolved in detect_config_file.
#   PLANNER_MODEL_SPEC (string): HF repo[:file] spec for planner llama calls.
#   PLANNER_MODEL_BRANCH (string): HF branch for planner model downloads.
#   EXECUTOR_MODEL_SPEC (string): HF repo[:file] spec for executor llama calls.
#   EXECUTOR_MODEL_BRANCH (string): HF branch for executor model downloads.
#   VALIDATOR_MODEL_SPEC (string): HF repo[:file] spec for validation llama calls.
#   VALIDATOR_MODEL_BRANCH (string): HF branch for validator model downloads.
#   SEARCH_REPHRASER_MODEL_SPEC (string): HF repo[:file] spec for search rephrasing llama calls.
#   SEARCH_REPHRASER_MODEL_BRANCH (string): HF branch for search rephrasing model downloads.
#   TESTING_PASSTHROUGH (bool): forces llama calls off during tests.
#   APPROVE_ALL (bool): skip prompts when true.
#   VERBOSITY (int): logging verbosity.
#   OKSO_CACHE_DIR (string): base directory for prompt caches (default: ${XDG_CACHE_HOME:-${HOME}/.cache}/okso).
#   OKSO_RUN_ID (string): unique identifier for the current run used to scope caches.
#
# Dependencies:
#   - bash 3.2+
#   - mkdir, cat
#
# Exit codes:
#   1 when required arguments are missing during flag parsing.
#   2 when model resolution fails.

if [[ "${OKSO_SETTINGS_CONFIG_LOADED:-false}" == true ]]; then
	return 0 2>/dev/null || exit 0
fi
OKSO_SETTINGS_CONFIG_LOADED=true

CONFIG_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${CONFIG_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/settings/system_profile.sh
source "${CONFIG_LIB_DIR}/system_profile.sh"

# Model defaults (populated via autotune to ensure deterministic sizing)
: "${DEFAULT_EXECUTOR_MODEL_REPO:=}"
: "${DEFAULT_EXECUTOR_MODEL_FILE:=}"
: "${DEFAULT_EXECUTOR_MODEL_SPEC_BASE:=}"
: "${DEFAULT_EXECUTOR_MODEL_BRANCH_BASE:=main}"

: "${DEFAULT_PLANNER_MODEL_REPO:=}"
: "${DEFAULT_PLANNER_MODEL_FILE:=}"
: "${DEFAULT_PLANNER_MODEL_SPEC_BASE:=}"
: "${DEFAULT_PLANNER_MODEL_BRANCH_BASE:=main}"

: "${DEFAULT_VALIDATOR_MODEL_SPEC_BASE:=}"
: "${DEFAULT_VALIDATOR_MODEL_BRANCH_BASE:=main}"

: "${DEFAULT_REPHRASER_MODEL_REPO:=}"
: "${DEFAULT_REPHRASER_MODEL_FILE:=}"
: "${DEFAULT_REPHRASER_MODEL_SPEC_BASE:=}"
: "${DEFAULT_REPHRASER_MODEL_BRANCH_BASE:=main}"

: "${MODEL_AUTOTUNE_BASE_TIER:=}"
: "${MODEL_AUTOTUNE_EFFECTIVE_TIER:=}"

set_autotuned_model_defaults() {
	# Sets default model specifications based on system profile autotuning.
	# Arguments:
	#   None
	# Returns:
	#   None

	local effective_tier task_size default_size heavy_size

	# Load or detect system profile
	load_or_detect_system_profile

	# Determine base tier if not already set
	if [[ -z "${DETECTED_BASE_TIER:-}" ]]; then
		DETECTED_BASE_TIER="default"
	fi

	# Determine effective tier based on pressure and headroom
	effective_tier="${DETECTED_BASE_TIER}"
	MODEL_AUTOTUNE_BASE_TIER="${DETECTED_BASE_TIER}"
	MODEL_AUTOTUNE_EFFECTIVE_TIER="${effective_tier}"

	# Resolve model sizes based on effective tier
	resolve_autotune_model_sizes "${effective_tier}" task_size default_size heavy_size

	# Set model defaults
	DEFAULT_REPHRASER_MODEL_REPO="$(model_repo_for_size "${task_size}")"
	DEFAULT_REPHRASER_MODEL_FILE="$(model_file_for_size "${task_size}")"
	DEFAULT_REPHRASER_MODEL_SPEC_BASE="${DEFAULT_REPHRASER_MODEL_REPO}:${DEFAULT_REPHRASER_MODEL_FILE}"

	# Executor uses default size
	DEFAULT_EXECUTOR_MODEL_REPO="$(model_repo_for_size "${default_size}")"
	DEFAULT_EXECUTOR_MODEL_FILE="$(model_file_for_size "${default_size}")"
	DEFAULT_EXECUTOR_MODEL_SPEC_BASE="${DEFAULT_EXECUTOR_MODEL_REPO}:${DEFAULT_EXECUTOR_MODEL_FILE}"

	# Planner uses heavy size
	DEFAULT_PLANNER_MODEL_REPO="$(model_repo_for_size "${heavy_size}")"
	DEFAULT_PLANNER_MODEL_FILE="$(model_file_for_size "${heavy_size}")"
	DEFAULT_PLANNER_MODEL_SPEC_BASE="${DEFAULT_PLANNER_MODEL_REPO}:${DEFAULT_PLANNER_MODEL_FILE}"

	# Validator uses heavy size
	DEFAULT_VALIDATOR_MODEL_REPO="$(model_repo_for_size "${heavy_size}")"
	DEFAULT_VALIDATOR_MODEL_FILE="$(model_file_for_size "${heavy_size}")"
	DEFAULT_VALIDATOR_MODEL_SPEC_BASE="${DEFAULT_VALIDATOR_MODEL_REPO}:${DEFAULT_VALIDATOR_MODEL_FILE}"
}

log_model_autotune_summary() {
	# Logs a summary of the model autotuning decisions.
	# Arguments:
	#   None
	# Returns:
	#  None

	local base effective mem_fragment gha_fragment fragments summary_detail
	base="${MODEL_AUTOTUNE_BASE_TIER:-${DETECTED_BASE_TIER:-unknown}}"
	effective="${MODEL_AUTOTUNE_EFFECTIVE_TIER:-${base}}"

	# Build memory fragment
	if [[ -n "${DETECTED_PHYS_MEM_GB:-}" ]]; then
		mem_fragment="physmem=${DETECTED_PHYS_MEM_GB}GB"
	elif [[ -n "${DETECTED_PHYS_MEM_BYTES:-}" ]]; then
		mem_fragment="physmem_bytes=${DETECTED_PHYS_MEM_BYTES}"
	else
		mem_fragment="physmem=unknown"
	fi

	# Build GHA fragment if applicable
	gha_fragment="${DETECTED_IS_GHA:+github_actions=${DETECTED_IS_GHA}}"

	# Compile summary detail
	fragments=()
	fragments+=("${mem_fragment}")
	[[ -n "${gha_fragment}" ]] && fragments+=("${gha_fragment}")

	# Combine fragments into summary detail
	summary_detail=$(
		IFS=','
		printf '%s' "${fragments[*]}"
	)
	log "DEBUG" "model autotune: base=${base} eff=${effective}" "${summary_detail}"
}

default_run_id() {
	# Generates a stable run identifier for cache scoping.
	# Returns:
	#   run ID string on stdout.
	date -u +"%Y%m%dT%H%M%SZ"
}

detect_config_file() {
	# Parse the config path early so subsequent helpers can honor user-provided locations.
	# Arguments:
	#   $@ - command-line arguments
	# Returns:
	#   None; sets CONFIG_FILE variable.

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--config)
			if [[ $# -lt 2 ]]; then
				die "config" "usage" "--config requires a path"
			fi
			CONFIG_FILE="$2"
			shift 2
			;;
		--config=*)
			CONFIG_FILE="${1#*=}"
			shift
			;;
		*)
			shift
			;;
		esac
	done
}

load_config() {
	# Load file-backed configuration, then apply environment variable overrides.
	# Arguments:
	#   None
	# Returns:
	#   None; sets global configuration variables.
	local preexisting_planner_model_spec preexisting_planner_model_spec_set
	local preexisting_planner_model_branch preexisting_planner_model_branch_set
	local preexisting_executor_model_spec preexisting_executor_model_spec_set
	local preexisting_executor_model_branch preexisting_executor_model_branch_set
	local preexisting_validator_model_spec preexisting_validator_model_spec_set
	local preexisting_validator_model_branch preexisting_validator_model_branch_set
	local preexisting_search_rephraser_model_spec preexisting_search_rephraser_model_spec_set
	local preexisting_search_rephraser_model_branch preexisting_search_rephraser_model_branch_set
	local preexisting_okso_google_cse_api_key preexisting_okso_google_cse_api_key_set
	local preexisting_okso_google_cse_id preexisting_okso_google_cse_id_set
	local preexisting_okso_cache_dir preexisting_okso_cache_dir_set
	local preexisting_okso_notes_dir preexisting_okso_notes_dir_set
	local preexisting_cache_dir preexisting_cache_dir_set
	local preexisting_notes_dir preexisting_notes_dir_set
	local preexisting_verbosity preexisting_verbosity_set
	local preexisting_approve_all preexisting_approve_all_set
	local preexisting_okso_run_id preexisting_okso_run_id_set
	preexisting_planner_model_spec_set=false
	preexisting_planner_model_branch_set=false
	preexisting_executor_model_spec_set=false
	preexisting_executor_model_branch_set=false
	preexisting_validator_model_spec_set=false
	preexisting_validator_model_branch_set=false
	preexisting_search_rephraser_model_spec_set=false
	preexisting_search_rephraser_model_branch_set=false
	preexisting_okso_google_cse_api_key_set=false
	preexisting_okso_google_cse_id_set=false
	preexisting_okso_cache_dir_set=false
	preexisting_okso_notes_dir_set=false
	preexisting_cache_dir_set=false
	preexisting_notes_dir_set=false
	preexisting_verbosity_set=false
	preexisting_approve_all_set=false
	preexisting_okso_run_id_set=false

	if [[ -n "${PLANNER_MODEL_SPEC+x}" ]]; then
		preexisting_planner_model_spec="${PLANNER_MODEL_SPEC}"
		preexisting_planner_model_spec_set=true
	fi
	if [[ -n "${PLANNER_MODEL_BRANCH+x}" ]]; then
		preexisting_planner_model_branch="${PLANNER_MODEL_BRANCH}"
		preexisting_planner_model_branch_set=true
	fi
	if [[ -n "${EXECUTOR_MODEL_SPEC+x}" ]]; then
		preexisting_executor_model_spec="${EXECUTOR_MODEL_SPEC}"
		preexisting_executor_model_spec_set=true
	fi
	if [[ -n "${EXECUTOR_MODEL_BRANCH+x}" ]]; then
		preexisting_executor_model_branch="${EXECUTOR_MODEL_BRANCH}"
		preexisting_executor_model_branch_set=true
	fi
	if [[ -n "${VALIDATOR_MODEL_SPEC+x}" ]]; then
		preexisting_validator_model_spec="${VALIDATOR_MODEL_SPEC}"
		preexisting_validator_model_spec_set=true
	fi
	if [[ -n "${VALIDATOR_MODEL_BRANCH+x}" ]]; then
		preexisting_validator_model_branch="${VALIDATOR_MODEL_BRANCH}"
		preexisting_validator_model_branch_set=true
	fi
	if [[ -n "${SEARCH_REPHRASER_MODEL_SPEC+x}" ]]; then
		preexisting_search_rephraser_model_spec="${SEARCH_REPHRASER_MODEL_SPEC}"
		preexisting_search_rephraser_model_spec_set=true
	fi
	if [[ -n "${SEARCH_REPHRASER_MODEL_BRANCH+x}" ]]; then
		preexisting_search_rephraser_model_branch="${SEARCH_REPHRASER_MODEL_BRANCH}"
		preexisting_search_rephraser_model_branch_set=true
	fi
	if [[ -n "${OKSO_GOOGLE_CSE_API_KEY+x}" ]]; then
		preexisting_okso_google_cse_api_key="${OKSO_GOOGLE_CSE_API_KEY}"
		preexisting_okso_google_cse_api_key_set=true
	fi
	if [[ -n "${OKSO_GOOGLE_CSE_ID+x}" ]]; then
		preexisting_okso_google_cse_id="${OKSO_GOOGLE_CSE_ID}"
		preexisting_okso_google_cse_id_set=true
	fi
	if [[ -n "${OKSO_CACHE_DIR+x}" ]]; then
		preexisting_okso_cache_dir="${OKSO_CACHE_DIR}"
		preexisting_okso_cache_dir_set=true
	fi
	if [[ -n "${OKSO_NOTES_DIR+x}" ]]; then
		preexisting_okso_notes_dir="${OKSO_NOTES_DIR}"
		preexisting_okso_notes_dir_set=true
	fi
	if [[ -n "${CACHE_DIR+x}" ]]; then
		preexisting_cache_dir="${CACHE_DIR}"
		preexisting_cache_dir_set=true
	fi
	if [[ -n "${NOTES_DIR+x}" ]]; then
		preexisting_notes_dir="${NOTES_DIR}"
		preexisting_notes_dir_set=true
	fi
	if [[ -n "${VERBOSITY+x}" ]]; then
		preexisting_verbosity="${VERBOSITY}"
		preexisting_verbosity_set=true
	fi
	if [[ -n "${APPROVE_ALL+x}" ]]; then
		preexisting_approve_all="${APPROVE_ALL}"
		preexisting_approve_all_set=true
	fi
	if [[ -n "${OKSO_RUN_ID+x}" ]]; then
		preexisting_okso_run_id="${OKSO_RUN_ID}"
		preexisting_okso_run_id_set=true
	fi

	# Load from file if it exists
	if [[ -f "${CONFIG_FILE}" ]]; then
		# shellcheck source=/dev/null
		source "${CONFIG_FILE}"
	fi

	# Preserve explicit environment values over config file values.
	if [[ "${preexisting_planner_model_spec_set}" == true ]]; then
		PLANNER_MODEL_SPEC="${preexisting_planner_model_spec}"
	fi
	if [[ "${preexisting_planner_model_branch_set}" == true ]]; then
		PLANNER_MODEL_BRANCH="${preexisting_planner_model_branch}"
	fi
	if [[ "${preexisting_executor_model_spec_set}" == true ]]; then
		EXECUTOR_MODEL_SPEC="${preexisting_executor_model_spec}"
	fi
	if [[ "${preexisting_executor_model_branch_set}" == true ]]; then
		EXECUTOR_MODEL_BRANCH="${preexisting_executor_model_branch}"
	fi
	if [[ "${preexisting_validator_model_spec_set}" == true ]]; then
		VALIDATOR_MODEL_SPEC="${preexisting_validator_model_spec}"
	fi
	if [[ "${preexisting_validator_model_branch_set}" == true ]]; then
		VALIDATOR_MODEL_BRANCH="${preexisting_validator_model_branch}"
	fi
	if [[ "${preexisting_search_rephraser_model_spec_set}" == true ]]; then
		SEARCH_REPHRASER_MODEL_SPEC="${preexisting_search_rephraser_model_spec}"
	fi
	if [[ "${preexisting_search_rephraser_model_branch_set}" == true ]]; then
		SEARCH_REPHRASER_MODEL_BRANCH="${preexisting_search_rephraser_model_branch}"
	fi
	if [[ "${preexisting_okso_google_cse_api_key_set}" == true ]]; then
		OKSO_GOOGLE_CSE_API_KEY="${preexisting_okso_google_cse_api_key}"
	fi
	if [[ "${preexisting_okso_google_cse_id_set}" == true ]]; then
		OKSO_GOOGLE_CSE_ID="${preexisting_okso_google_cse_id}"
	fi
	if [[ "${preexisting_okso_cache_dir_set}" == true ]]; then
		OKSO_CACHE_DIR="${preexisting_okso_cache_dir}"
	fi
	if [[ "${preexisting_okso_notes_dir_set}" == true ]]; then
		OKSO_NOTES_DIR="${preexisting_okso_notes_dir}"
	fi
	if [[ "${preexisting_cache_dir_set}" == true ]]; then
		CACHE_DIR="${preexisting_cache_dir}"
	fi
	if [[ "${preexisting_notes_dir_set}" == true ]]; then
		NOTES_DIR="${preexisting_notes_dir}"
	fi
	if [[ "${preexisting_verbosity_set}" == true ]]; then
		VERBOSITY="${preexisting_verbosity}"
	fi
	if [[ "${preexisting_approve_all_set}" == true ]]; then
		APPROVE_ALL="${preexisting_approve_all}"
	fi
	if [[ "${preexisting_okso_run_id_set}" == true ]]; then
		OKSO_RUN_ID="${preexisting_okso_run_id}"
	fi

	# Apply environment variable defaults
	PLANNER_MODEL_SPEC=${PLANNER_MODEL_SPEC:-"${DEFAULT_PLANNER_MODEL_SPEC_BASE}"}
	PLANNER_MODEL_BRANCH=${PLANNER_MODEL_BRANCH:-"${DEFAULT_PLANNER_MODEL_BRANCH_BASE}"}

	EXECUTOR_MODEL_SPEC=${EXECUTOR_MODEL_SPEC:-"${DEFAULT_EXECUTOR_MODEL_SPEC_BASE}"}
	EXECUTOR_MODEL_BRANCH=${EXECUTOR_MODEL_BRANCH:-"${DEFAULT_EXECUTOR_MODEL_BRANCH_BASE}"}

	VALIDATOR_MODEL_SPEC=${VALIDATOR_MODEL_SPEC:-"${DEFAULT_VALIDATOR_MODEL_SPEC_BASE}"}
	VALIDATOR_MODEL_BRANCH=${VALIDATOR_MODEL_BRANCH:-"${DEFAULT_VALIDATOR_MODEL_BRANCH_BASE}"}

	SEARCH_REPHRASER_MODEL_SPEC=${SEARCH_REPHRASER_MODEL_SPEC:-"${DEFAULT_REPHRASER_MODEL_SPEC_BASE}"}
	SEARCH_REPHRASER_MODEL_BRANCH=${SEARCH_REPHRASER_MODEL_BRANCH:-"${DEFAULT_REPHRASER_MODEL_BRANCH_BASE}"}

	# Core settings
	VERBOSITY=${VERBOSITY:-1}
	APPROVE_ALL=${APPROVE_ALL:-false}
	OKSO_RUN_ID=${OKSO_RUN_ID:-$(default_run_id)}
	GOOGLE_SEARCH_API_KEY=${GOOGLE_SEARCH_API_KEY:-${OKSO_GOOGLE_CSE_API_KEY:-}}
	GOOGLE_SEARCH_CX=${GOOGLE_SEARCH_CX:-${OKSO_GOOGLE_CSE_ID:-}}

	# Cache configuration
	local default_cache_dir
	default_cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/okso"
	CACHE_DIR="${CACHE_DIR:-${OKSO_CACHE_DIR:-${default_cache_dir}}}"
	NOTES_DIR="${NOTES_DIR:-${OKSO_NOTES_DIR:-${HOME}/.okso}}"

	log_model_autotune_summary
}

write_config_file() {
	# Persist the current configuration in a shell-friendly format.
	# Arguments:
	#   None
	# Returns:
	#   None; writes to CONFIG_FILE.

	# Helper to quote config values
	quote_config_value() {
		local value="$1"
		printf '%q' "${value}"
	}

	# Ensure config directory exists
	mkdir -p "$(dirname "${CONFIG_FILE}")"

	# Write config file
	cat >"${CONFIG_FILE}" <<EOF_CONFIG
PLANNER_MODEL_SPEC=$(quote_config_value "${PLANNER_MODEL_SPEC}")
PLANNER_MODEL_BRANCH=$(quote_config_value "${PLANNER_MODEL_BRANCH}")
EXECUTOR_MODEL_SPEC=$(quote_config_value "${EXECUTOR_MODEL_SPEC}")
EXECUTOR_MODEL_BRANCH=$(quote_config_value "${EXECUTOR_MODEL_BRANCH}")
VALIDATOR_MODEL_SPEC=$(quote_config_value "${VALIDATOR_MODEL_SPEC}")
VALIDATOR_MODEL_BRANCH=$(quote_config_value "${VALIDATOR_MODEL_BRANCH}")
SEARCH_REPHRASER_MODEL_SPEC=$(quote_config_value "${SEARCH_REPHRASER_MODEL_SPEC}")
SEARCH_REPHRASER_MODEL_BRANCH=$(quote_config_value "${SEARCH_REPHRASER_MODEL_BRANCH}")
CACHE_DIR=$(quote_config_value "${CACHE_DIR}")
VERBOSITY=${VERBOSITY}
APPROVE_ALL=${APPROVE_ALL}
EOF_CONFIG

	# Log completion
	printf 'Wrote config to %s\n' "${CONFIG_FILE}"
}

parse_model_spec() {
	# Parse model spec into repo[:file] components.
	# Arguments:
	#   $1 - model spec repo[:file]
	#   $2 - default file fallback
	# Returns:
	#   repo and file on separate lines.
	local spec default_file repo file
	spec="$1"
	default_file="$2"

	# Parse spec
	if [[ "${spec}" == *:* ]]; then
		repo="${spec%%:*}"
		file="${spec#*:}"
	else
		repo="${spec}"
		file="${default_file}"
	fi

	printf '%s\n%s\n' "${repo}" "${file}"
}

normalize_approval_flags() {
	# Normalize approval toggles to strict booleans.
	# Arguments:
	#   None
	# Returns:
	#   None; sets APPROVE_ALL variable.

	case "${APPROVE_ALL}" in
	true | True | TRUE | 1)
		APPROVE_ALL=true
		;;
	false | False | FALSE | 0)
		APPROVE_ALL=false
		;;
	*)
		log "WARN" "Invalid approval flag; defaulting to prompts" "${APPROVE_ALL}"
		APPROVE_ALL=false
		;;
	esac
}

hydrate_model_spec_to_vars() {
	# Normalize a model spec into repo and file variables.
	# Arguments:
	#   $1 - model spec string (repo[:file])
	#   $2 - default file name
	#   $3 - repo variable name to populate
	#   $4 - file variable name to populate
	# Returns:
	#   None; sets specified variables.

	local model_parts repo_var file_var
	model_parts=()
	repo_var="$3"
	file_var="$4"

	while IFS= read -r line; do
		model_parts+=("$line")
	done < <(parse_model_spec "$1" "$2")

	printf -v "${repo_var}" '%s' "${model_parts[0]}"
	printf -v "${file_var}" '%s' "${model_parts[1]}"
}

hydrate_model_specs() {
	# Normalize all model specs into repo and file components.
	hydrate_model_spec_to_vars "${PLANNER_MODEL_SPEC}" "${DEFAULT_PLANNER_MODEL_FILE}" PLANNER_MODEL_REPO PLANNER_MODEL_FILE
	hydrate_model_spec_to_vars "${EXECUTOR_MODEL_SPEC}" "${DEFAULT_EXECUTOR_MODEL_FILE}" EXECUTOR_MODEL_REPO EXECUTOR_MODEL_FILE
	hydrate_model_spec_to_vars "${VALIDATOR_MODEL_SPEC}" "${DEFAULT_VALIDATOR_MODEL_SPEC_BASE##*:}" VALIDATOR_MODEL_REPO VALIDATOR_MODEL_FILE
	hydrate_model_spec_to_vars "${SEARCH_REPHRASER_MODEL_SPEC}" "${DEFAULT_REPHRASER_MODEL_FILE}" SEARCH_REPHRASER_MODEL_REPO SEARCH_REPHRASER_MODEL_FILE
}

init_environment() {
	# Initialize the runtime environment.
	normalize_approval_flags
	hydrate_model_specs

	# Platform detection
	if [[ "$(uname -s)" == "Darwin" ]]; then
		# shellcheck disable=SC2034
		IS_MACOS=true
	fi

	# LLM availability
	if [[ "${TESTING_PASSTHROUGH:-false}" == true ]]; then
		LLAMA_AVAILABLE=false
	else
		LLAMA_AVAILABLE=true
	fi

	if [[ "${LLAMA_AVAILABLE}" == true ]] && ! command -v "${LLAMA_BIN:-llama-completion}" >/dev/null 2>&1; then
		log "WARN" "llama.cpp binary not found" "${LLAMA_BIN:-llama-completion}"
		LLAMA_AVAILABLE=false
	fi

	# Create required directories
	mkdir -p "${CACHE_DIR}" \
		"${NOTES_DIR}"
}

# Auto-initialize configuration when module is sourced
CONFIG_FILE="${CONFIG_FILE:-${XDG_CONFIG_HOME:-${HOME}/.config}/okso/config.env}"

set_autotuned_model_defaults
load_config
init_environment
