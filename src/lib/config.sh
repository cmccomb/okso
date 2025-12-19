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
#   REACT_MODEL_SPEC (string): HF repo[:file] spec for ReAct llama calls.
#   REACT_MODEL_BRANCH (string): HF branch for ReAct model downloads.
#   TESTING_PASSTHROUGH (bool): forces llama calls off during tests.
#   APPROVE_ALL (bool): skip prompts when true.
#   FORCE_CONFIRM (bool): always prompt when true.
#   VERBOSITY (int): logging verbosity.
#   DEFAULT_MODEL_FILE (string): fallback file name for parsing model spec.
#   OKSO_GOOGLE_CSE_API_KEY (string): Google Custom Search API key; may be overridden by environment.
#   OKSO_GOOGLE_CSE_ID (string): Google Custom Search Engine ID; may be overridden by environment.
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

: "${DEFAULT_MODEL_REPO_BASE:=bartowski/Qwen_Qwen3-1.7B-GGUF}"
: "${DEFAULT_MODEL_FILE_BASE:=Qwen_Qwen3-1.7B-Q4_K_M.gguf}"
: "${DEFAULT_MODEL_SPEC_BASE:=${DEFAULT_MODEL_REPO_BASE}:${DEFAULT_MODEL_FILE_BASE}}"
: "${DEFAULT_MODEL_BRANCH_BASE:=main}"
: "${DEFAULT_REACT_MODEL_SPEC_BASE:=${DEFAULT_MODEL_SPEC_BASE}}"
: "${DEFAULT_REACT_MODEL_BRANCH_BASE:=${DEFAULT_MODEL_BRANCH_BASE}}"

: "${DEFAULT_PLANNER_MODEL_REPO_BASE:=bartowski/Qwen_Qwen3-8B-GGUF}"
: "${DEFAULT_PLANNER_MODEL_FILE_BASE:=Qwen_Qwen3-8B-Q4_K_M.gguf}"
: "${DEFAULT_PLANNER_MODEL_SPEC_BASE:=${DEFAULT_PLANNER_MODEL_REPO_BASE}:${DEFAULT_PLANNER_MODEL_FILE_BASE}}"
: "${DEFAULT_PLANNER_MODEL_BRANCH_BASE:=main}"

readonly DEFAULT_MODEL_REPO_BASE DEFAULT_MODEL_FILE_BASE DEFAULT_MODEL_SPEC_BASE DEFAULT_MODEL_BRANCH_BASE
readonly DEFAULT_REACT_MODEL_SPEC_BASE DEFAULT_REACT_MODEL_BRANCH_BASE
readonly DEFAULT_PLANNER_MODEL_REPO_BASE DEFAULT_PLANNER_MODEL_FILE_BASE
readonly DEFAULT_PLANNER_MODEL_SPEC_BASE DEFAULT_PLANNER_MODEL_BRANCH_BASE

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
	# Load file-backed configuration first so environment overrides and CLI flags
	# can layer on top in a predictable order.
	local preexisting_okso_google_cse_api_key preexisting_okso_google_cse_api_key_set
	local preexisting_okso_google_cse_id preexisting_okso_google_cse_id_set
	local preexisting_planner_model_spec preexisting_planner_model_spec_set
	local preexisting_planner_model_branch preexisting_planner_model_branch_set
	local preexisting_react_model_spec preexisting_react_model_spec_set
	local preexisting_react_model_branch preexisting_react_model_branch_set
	local preexisting_default_model_file preexisting_default_model_file_set
	local preexisting_default_planner_model_file preexisting_default_planner_model_file_set
	local preexisting_verbosity preexisting_verbosity_set
	local preexisting_approve_all preexisting_approve_all_set
	local preexisting_force_confirm preexisting_force_confirm_set

	preexisting_okso_google_cse_api_key_set=false
	preexisting_okso_google_cse_id_set=false
	preexisting_planner_model_spec_set=false
	preexisting_planner_model_branch_set=false
	preexisting_react_model_spec_set=false
	preexisting_react_model_branch_set=false
	preexisting_default_model_file_set=false
	preexisting_default_planner_model_file_set=false
	preexisting_verbosity_set=false
	preexisting_approve_all_set=false
	preexisting_force_confirm_set=false

	if [[ -n "${OKSO_GOOGLE_CSE_API_KEY+x}" ]]; then
		preexisting_okso_google_cse_api_key="${OKSO_GOOGLE_CSE_API_KEY}"
		preexisting_okso_google_cse_api_key_set=true
	fi
	if [[ -n "${OKSO_GOOGLE_CSE_ID+x}" ]]; then
		preexisting_okso_google_cse_id="${OKSO_GOOGLE_CSE_ID}"
		preexisting_okso_google_cse_id_set=true
	fi
	if [[ -n "${PLANNER_MODEL_SPEC+x}" ]]; then
		preexisting_planner_model_spec="${PLANNER_MODEL_SPEC}"
		preexisting_planner_model_spec_set=true
	fi
	if [[ -n "${PLANNER_MODEL_BRANCH+x}" ]]; then
		preexisting_planner_model_branch="${PLANNER_MODEL_BRANCH}"
		preexisting_planner_model_branch_set=true
	fi
	if [[ -n "${REACT_MODEL_SPEC+x}" ]]; then
		preexisting_react_model_spec="${REACT_MODEL_SPEC}"
		preexisting_react_model_spec_set=true
	fi
	if [[ -n "${REACT_MODEL_BRANCH+x}" ]]; then
		preexisting_react_model_branch="${REACT_MODEL_BRANCH}"
		preexisting_react_model_branch_set=true
	fi
	if [[ -n "${DEFAULT_MODEL_FILE+x}" ]]; then
		preexisting_default_model_file="${DEFAULT_MODEL_FILE}"
		preexisting_default_model_file_set=true
	fi
	if [[ -n "${DEFAULT_PLANNER_MODEL_FILE+x}" ]]; then
		preexisting_default_planner_model_file="${DEFAULT_PLANNER_MODEL_FILE}"
		preexisting_default_planner_model_file_set=true
	fi
	if [[ -n "${VERBOSITY+x}" ]]; then
		preexisting_verbosity="${VERBOSITY}"
		preexisting_verbosity_set=true
	fi
	if [[ -n "${APPROVE_ALL+x}" ]]; then
		preexisting_approve_all="${APPROVE_ALL}"
		preexisting_approve_all_set=true
	fi
	if [[ -n "${FORCE_CONFIRM+x}" ]]; then
		preexisting_force_confirm="${FORCE_CONFIRM}"
		preexisting_force_confirm_set=true
	fi

	if [[ -f "${CONFIG_FILE}" ]]; then
		# shellcheck source=/dev/null
		source "${CONFIG_FILE}"
	fi

	if [[ "${preexisting_okso_google_cse_api_key_set}" == true ]]; then
		OKSO_GOOGLE_CSE_API_KEY="${preexisting_okso_google_cse_api_key}"
	fi
	if [[ "${preexisting_okso_google_cse_id_set}" == true ]]; then
		OKSO_GOOGLE_CSE_ID="${preexisting_okso_google_cse_id}"
	fi
	if [[ "${preexisting_default_model_file_set}" == true ]]; then
		DEFAULT_MODEL_FILE="${preexisting_default_model_file}"
	else
		DEFAULT_MODEL_FILE=${DEFAULT_MODEL_FILE:-${DEFAULT_MODEL_FILE_BASE}}
	fi
	if [[ "${preexisting_default_planner_model_file_set}" == true ]]; then
		DEFAULT_PLANNER_MODEL_FILE="${preexisting_default_planner_model_file}"
	else
		DEFAULT_PLANNER_MODEL_FILE=${DEFAULT_PLANNER_MODEL_FILE:-${DEFAULT_PLANNER_MODEL_FILE_BASE}}
	fi
	if [[ "${preexisting_planner_model_spec_set}" == true ]]; then
		PLANNER_MODEL_SPEC="${preexisting_planner_model_spec}"
	else
		PLANNER_MODEL_SPEC=${PLANNER_MODEL_SPEC:-"${DEFAULT_PLANNER_MODEL_SPEC_BASE}"}
	fi
	if [[ "${preexisting_planner_model_branch_set}" == true ]]; then
		PLANNER_MODEL_BRANCH="${preexisting_planner_model_branch}"
	else
		PLANNER_MODEL_BRANCH=${PLANNER_MODEL_BRANCH:-${DEFAULT_PLANNER_MODEL_BRANCH_BASE}}
	fi
	if [[ "${preexisting_react_model_spec_set}" == true ]]; then
		REACT_MODEL_SPEC="${preexisting_react_model_spec}"
	else
		REACT_MODEL_SPEC=${REACT_MODEL_SPEC:-"${DEFAULT_REACT_MODEL_SPEC_BASE}"}
	fi
	if [[ "${preexisting_react_model_branch_set}" == true ]]; then
		REACT_MODEL_BRANCH="${preexisting_react_model_branch}"
	else
		REACT_MODEL_BRANCH=${REACT_MODEL_BRANCH:-${DEFAULT_REACT_MODEL_BRANCH_BASE}}
	fi
	if [[ "${preexisting_verbosity_set}" == true ]]; then
		VERBOSITY="${preexisting_verbosity}"
	else
		VERBOSITY=${VERBOSITY:-1}
	fi
	if [[ "${preexisting_approve_all_set}" == true ]]; then
		APPROVE_ALL="${preexisting_approve_all}"
	else
		APPROVE_ALL=${APPROVE_ALL:-false}
	fi
	if [[ "${preexisting_force_confirm_set}" == true ]]; then
		FORCE_CONFIRM="${preexisting_force_confirm}"
	else
		FORCE_CONFIRM=${FORCE_CONFIRM:-false}
	fi

	GOOGLE_SEARCH_API_KEY=${GOOGLE_SEARCH_API_KEY:-${OKSO_GOOGLE_CSE_API_KEY:-}}
	GOOGLE_SEARCH_CX=${GOOGLE_SEARCH_CX:-${OKSO_GOOGLE_CSE_ID:-}}
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
REACT_MODEL_SPEC=$(quote_config_value "${REACT_MODEL_SPEC}")
REACT_MODEL_BRANCH=$(quote_config_value "${REACT_MODEL_BRANCH}")
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
	# Normalizes planner and react model specs into repo and file components.
	DEFAULT_PLANNER_MODEL_FILE=${DEFAULT_PLANNER_MODEL_FILE:-${DEFAULT_PLANNER_MODEL_FILE_BASE}}
	DEFAULT_MODEL_FILE=${DEFAULT_MODEL_FILE:-${DEFAULT_MODEL_FILE_BASE}}

	PLANNER_MODEL_SPEC=${PLANNER_MODEL_SPEC:-"${DEFAULT_PLANNER_MODEL_SPEC_BASE}"}
	PLANNER_MODEL_BRANCH=${PLANNER_MODEL_BRANCH:-"${DEFAULT_PLANNER_MODEL_BRANCH_BASE}"}
	REACT_MODEL_SPEC=${REACT_MODEL_SPEC:-"${DEFAULT_REACT_MODEL_SPEC_BASE}"}
	REACT_MODEL_BRANCH=${REACT_MODEL_BRANCH:-"${DEFAULT_REACT_MODEL_BRANCH_BASE}"}

	hydrate_model_spec_to_vars "${PLANNER_MODEL_SPEC}" "${DEFAULT_PLANNER_MODEL_FILE}" PLANNER_MODEL_REPO PLANNER_MODEL_FILE
	hydrate_model_spec_to_vars "${REACT_MODEL_SPEC}" "${DEFAULT_MODEL_FILE}" REACT_MODEL_REPO REACT_MODEL_FILE

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

	mkdir -p "${NOTES_DIR}"
}
