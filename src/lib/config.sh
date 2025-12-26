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
#   SEARCH_REPHRASER_MODEL_SPEC (string): HF repo[:file] spec for search rephrasing llama calls.
#   SEARCH_REPHRASER_MODEL_BRANCH (string): HF branch for search rephrasing model downloads.
#   TESTING_PASSTHROUGH (bool): forces llama calls off during tests.
#   APPROVE_ALL (bool): skip prompts when true.
#   FORCE_CONFIRM (bool): always prompt when true.
#   VERBOSITY (int): logging verbosity.
#   DEFAULT_MODEL_FILE (string): fallback file name for parsing model spec.
#   OKSO_GOOGLE_CSE_API_KEY (string): Google Custom Search API key; may be overridden by environment.
#   OKSO_GOOGLE_CSE_ID (string): Google Custom Search Engine ID; may be overridden by environment.
#   OKSO_CACHE_DIR (string): base directory for prompt caches (default: ${XDG_CACHE_HOME:-${HOME}/.cache}/okso).
#   OKSO_PLANNER_CACHE_FILE (string): prompt cache file used for planning llama.cpp calls.
#   OKSO_REPHRASER_CACHE_FILE (string): prompt cache file used for search rephrasing llama.cpp calls.
#   OKSO_EXECUTOR_CACHE_FILE (string): run-scoped prompt cache file for executor llama.cpp calls.
#   OKSO_RUN_ID (string): unique identifier for the current run used to scope caches.
#
# Dependencies:
#   - bash 3.2+
#   - mkdir, cat
#
# Exit codes:
#   1 when required arguments are missing during flag parsing.
#   2 when model resolution fails.

CONFIG_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./core/logging.sh disable=SC1091
source "${CONFIG_LIB_DIR}/core/logging.sh"

: "${DEFAULT_MODEL_REPO_BASE:=bartowski/Qwen_Qwen3-4B-GGUF}"
: "${DEFAULT_MODEL_FILE_BASE:=Qwen_Qwen3-4B-Q4_K_M.gguf}"
: "${DEFAULT_MODEL_SPEC_BASE:=${DEFAULT_MODEL_REPO_BASE}:${DEFAULT_MODEL_FILE_BASE}}"
: "${DEFAULT_MODEL_BRANCH_BASE:=main}"
: "${DEFAULT_EXECUTOR_MODEL_SPEC_BASE:=${DEFAULT_MODEL_SPEC_BASE}}"
: "${DEFAULT_EXECUTOR_MODEL_BRANCH_BASE:=${DEFAULT_MODEL_BRANCH_BASE}}"

: "${DEFAULT_REPHRASER_MODEL_REPO_BASE:=bartowski/Qwen_Qwen3-1.7B-GGUF}"
: "${DEFAULT_REPHRASER_MODEL_FILE_BASE:=Qwen_Qwen3-1.7B-Q4_K_M.gguf}"
: "${DEFAULT_REPHRASER_MODEL_SPEC_BASE:=${DEFAULT_REPHRASER_MODEL_REPO_BASE}:${DEFAULT_REPHRASER_MODEL_FILE_BASE}}"
: "${DEFAULT_REPHRASER_MODEL_BRANCH_BASE:=main}"

: "${DEFAULT_PLANNER_MODEL_REPO_BASE:=bartowski/Qwen_Qwen3-8B-GGUF}"
: "${DEFAULT_PLANNER_MODEL_FILE_BASE:=Qwen_Qwen3-8B-Q4_K_M.gguf}"
: "${DEFAULT_PLANNER_MODEL_SPEC_BASE:=${DEFAULT_PLANNER_MODEL_REPO_BASE}:${DEFAULT_PLANNER_MODEL_FILE_BASE}}"
: "${DEFAULT_PLANNER_MODEL_BRANCH_BASE:=main}"

readonly DEFAULT_MODEL_REPO_BASE DEFAULT_MODEL_FILE_BASE DEFAULT_MODEL_SPEC_BASE DEFAULT_MODEL_BRANCH_BASE
readonly DEFAULT_EXECUTOR_MODEL_SPEC_BASE DEFAULT_EXECUTOR_MODEL_BRANCH_BASE
readonly DEFAULT_PLANNER_MODEL_REPO_BASE DEFAULT_PLANNER_MODEL_FILE_BASE
readonly DEFAULT_PLANNER_MODEL_SPEC_BASE DEFAULT_PLANNER_MODEL_BRANCH_BASE
readonly DEFAULT_REPHRASER_MODEL_REPO_BASE DEFAULT_REPHRASER_MODEL_FILE_BASE
readonly DEFAULT_REPHRASER_MODEL_SPEC_BASE DEFAULT_REPHRASER_MODEL_BRANCH_BASE

default_run_id() {
	# Generates a stable run identifier for cache scoping.
	date -u +"%Y%m%dT%H%M%SZ"
}

detect_config_file() {
	# Parse the config path early so subsequent helpers can honor user-provided
	# locations before any other arguments are interpreted.
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
	# 1) Source config file (if any). Whatever it sets wins over caller env.
	if [[ -f "${CONFIG_FILE}" ]]; then
		# shellcheck source=/dev/null
		source "${CONFIG_FILE}"
	fi

	# 2) Defaults (only fill if still unset).
	: "${PLANNER_MODEL_SPEC:=bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf}"
	: "${PLANNER_MODEL_BRANCH:=main}"

	: "${EXECUTOR_MODEL_SPEC:=bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf}"
	: "${EXECUTOR_MODEL_BRANCH:=main}"

	: "${SEARCH_REPHRASER_MODEL_SPEC:=bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf}"
	: "${SEARCH_REPHRASER_MODEL_BRANCH:=main}"

	: "${VERBOSITY:=1}"
	: "${APPROVE_ALL:=false}"
	: "${FORCE_CONFIRM:=false}"

	: "${OKSO_RUN_ID:=$(default_run_id)}"

	local default_cache_dir
	default_cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/okso"
	: "${OKSO_CACHE_DIR:=${default_cache_dir}}"
	CACHE_DIR="${OKSO_CACHE_DIR}"

	: "${OKSO_PLANNER_CACHE_FILE:=${CACHE_DIR}/planner.prompt-cache}"
	PLANNER_CACHE_FILE="${OKSO_PLANNER_CACHE_FILE}"

	: "${OKSO_EXECUTOR_CACHE_FILE:=${CACHE_DIR}/runs/${OKSO_RUN_ID}/executor.prompt-cache}"
	EXECUTOR_CACHE_FILE="${OKSO_EXECUTOR_CACHE_FILE}"

	: "${OKSO_REPHRASER_CACHE_FILE:=${CACHE_DIR}/rephraser.prompt-cache}"
	SEARCH_REPHRASER_CACHE_FILE="${OKSO_REPHRASER_CACHE_FILE}"

	# Google search vars (keep simple)
	GOOGLE_SEARCH_API_KEY="${GOOGLE_SEARCH_API_KEY:-${OKSO_GOOGLE_CSE_API_KEY:-}}"
	GOOGLE_SEARCH_CX="${GOOGLE_SEARCH_CX:-${OKSO_GOOGLE_CSE_ID:-}}"
}

write_config_file() {
	# Persist the current configuration in a shell-friendly format. Values are
	# shell-escaped to preserve strings with spaces or special characters when the
	# file is sourced later.
	# Arguments:
	#   CONFIG_FILE (string, global): destination path for the config file.
	quote_config_value() {
		# Arguments:
		#   $1 - value to escape (string)
		local value
		value="$1"

		printf '%q' "${value}"
	}

	mkdir -p "$(dirname "${CONFIG_FILE}")"
	cat >"${CONFIG_FILE}" <<EOF_CONFIG
PLANNER_MODEL_SPEC=$(quote_config_value "${PLANNER_MODEL_SPEC}")
PLANNER_MODEL_BRANCH=$(quote_config_value "${PLANNER_MODEL_BRANCH}")
EXECUTOR_MODEL_SPEC=$(quote_config_value "${EXECUTOR_MODEL_SPEC}")
EXECUTOR_MODEL_BRANCH=$(quote_config_value "${EXECUTOR_MODEL_BRANCH}")
SEARCH_REPHRASER_MODEL_SPEC=$(quote_config_value "${SEARCH_REPHRASER_MODEL_SPEC}")
SEARCH_REPHRASER_MODEL_BRANCH=$(quote_config_value "${SEARCH_REPHRASER_MODEL_BRANCH}")
OKSO_CACHE_DIR=$(quote_config_value "${CACHE_DIR}")
OKSO_PLANNER_CACHE_FILE=$(quote_config_value "${PLANNER_CACHE_FILE}")
OKSO_EXECUTOR_CACHE_FILE=$(quote_config_value "${OKSO_EXECUTOR_CACHE_FILE}")
VERBOSITY=${VERBOSITY}
APPROVE_ALL=${APPROVE_ALL}
FORCE_CONFIRM=${FORCE_CONFIRM}
EOF_CONFIG
	printf 'Wrote config to %s\n' "${CONFIG_FILE}"
}

parse_model_spec() {
	# Arguments:
	#   $1 - model spec repo[:file]
	#   $2 - default file fallback
	local spec default_file repo file
	spec="$1"
	default_file="$2"

	if [[ "${spec}" == *:* ]]; then
		repo="${spec%%:*}"
		file="${spec#*:}"
	else
		# If no file component is provided we assume the default quantization file
		# to keep CLI usage ergonomic.
		repo="${spec}"
		file="${default_file}"
	fi

	printf '%s\n%s\n' "${repo}" "${file}"
}

normalize_approval_flags() {
	# Normalize approval toggles to strict booleans to avoid surprising behavior
	# from varied casing or numeric inputs.
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

	case "${FORCE_CONFIRM}" in
	true | True | TRUE | 1)
		FORCE_CONFIRM=true
		;;
	false | False | FALSE | 0)
		FORCE_CONFIRM=false
		;;
	*)
		log "WARN" "Invalid confirm flag; defaulting to prompts" "${FORCE_CONFIRM}"
		FORCE_CONFIRM=false
		;;
	esac
}

hydrate_model_spec_to_vars() {
	# Normalizes a model spec into repo and file components for llama.cpp calls.
	# Arguments:
	#   $1 - model spec string
	#   $2 - default file name
	#   $3 - repo variable name to populate
	#   $4 - file variable name to populate
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
	# Normalizes planner and executor model specs into repo and file components.
	DEFAULT_PLANNER_MODEL_FILE=${DEFAULT_PLANNER_MODEL_FILE:-${DEFAULT_PLANNER_MODEL_FILE_BASE}}
	DEFAULT_MODEL_FILE=${DEFAULT_MODEL_FILE:-${DEFAULT_MODEL_FILE_BASE}}

	PLANNER_MODEL_SPEC=${PLANNER_MODEL_SPEC:-"${DEFAULT_PLANNER_MODEL_SPEC_BASE}"}
	PLANNER_MODEL_BRANCH=${PLANNER_MODEL_BRANCH:-"${DEFAULT_PLANNER_MODEL_BRANCH_BASE}"}
	EXECUTOR_MODEL_SPEC=${EXECUTOR_MODEL_SPEC:-"${DEFAULT_EXECUTOR_MODEL_SPEC_BASE}"}
	EXECUTOR_MODEL_BRANCH=${EXECUTOR_MODEL_BRANCH:-"${DEFAULT_EXECUTOR_MODEL_BRANCH_BASE}"}
	SEARCH_REPHRASER_MODEL_SPEC=${SEARCH_REPHRASER_MODEL_SPEC:-"${DEFAULT_REPHRASER_MODEL_SPEC_BASE}"}
	SEARCH_REPHRASER_MODEL_BRANCH=${SEARCH_REPHRASER_MODEL_BRANCH:-"${DEFAULT_REPHRASER_MODEL_BRANCH_BASE}"}

	hydrate_model_spec_to_vars "${PLANNER_MODEL_SPEC}" "${DEFAULT_PLANNER_MODEL_FILE}" PLANNER_MODEL_REPO PLANNER_MODEL_FILE
	hydrate_model_spec_to_vars "${EXECUTOR_MODEL_SPEC}" "${DEFAULT_MODEL_FILE}" EXECUTOR_MODEL_REPO EXECUTOR_MODEL_FILE
	hydrate_model_spec_to_vars "${SEARCH_REPHRASER_MODEL_SPEC}" "${DEFAULT_REPHRASER_MODEL_FILE_BASE}" SEARCH_REPHRASER_MODEL_REPO SEARCH_REPHRASER_MODEL_FILE

}

init_environment() {
	normalize_approval_flags
	hydrate_model_specs

	if command -v uname >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
		# Downstream tools sometimes need macOS-specific flags; stash a boolean
		# rather than repeatedly shelling out.
		# shellcheck disable=SC2034
		IS_MACOS=true
	fi

	if [[ "${TESTING_PASSTHROUGH:-false}" == true ]]; then
		# During bats runs we suppress llama.cpp invocation for determinism.
		LLAMA_AVAILABLE=false
	else
		LLAMA_AVAILABLE=true
	fi

	if [[ "${LLAMA_AVAILABLE}" == true ]] && ! command -v "${LLAMA_BIN:-llama-cli}" >/dev/null 2>&1; then
		log "WARN" "llama.cpp binary not found" "${LLAMA_BIN:-llama-cli}"
		LLAMA_AVAILABLE=false
	fi

	mkdir -p "${CACHE_DIR}" "$(dirname "${PLANNER_CACHE_FILE}")" "$(dirname "${EXECUTOR_CACHE_FILE}")" "$(dirname "${SEARCH_REPHRASER_CACHE_FILE}")"
	mkdir -p "${NOTES_DIR}"
}
