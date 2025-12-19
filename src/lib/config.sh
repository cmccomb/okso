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
#   MODEL_SPEC (string): HF repo[:file] spec; may be overridden by OKSO_MODEL.
#   MODEL_BRANCH (string): HF branch; may be overridden by OKSO_MODEL_BRANCH.
#   PLANNER_MODEL_SPEC (string): HF repo[:file] spec for planner llama calls.
#   PLANNER_MODEL_BRANCH (string): HF branch for planner model downloads.
#   REACT_MODEL_SPEC (string): HF repo[:file] spec for ReAct llama calls.
#   REACT_MODEL_BRANCH (string): HF branch for ReAct model downloads.
#   TESTING_PASSTHROUGH (bool): forces llama calls off during tests.
#   APPROVE_ALL (bool): skip prompts when true.
#   FORCE_CONFIRM (bool): always prompt when true.
#   VERBOSITY (int): logging verbosity; may be overridden by OKSO_VERBOSITY.
#   DEFAULT_MODEL_FILE (string): fallback file name for parsing model spec.
#   OKSO_GOOGLE_CSE_API_KEY (string): Google Custom Search API key; may be overridden by environment.
#   OKSO_GOOGLE_CSE_ID (string): Google Custom Search Engine ID; may be overridden by environment.
#
#   okso-branded overrides (legacy DO_* aliases are ignored):
#     OKSO_MODEL, OKSO_MODEL_BRANCH, OKSO_SUPERVISED, OKSO_VERBOSITY
#
# Dependencies:
#   - bash 5+
#   - mkdir, cat
#
# Exit codes:
#   1 when required arguments are missing during flag parsing.
#   2 when model resolution fails.

CONFIG_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./core/logging.sh disable=SC1091
source "${CONFIG_LIB_DIR}/core/logging.sh"

readonly DEFAULT_MODEL_REPO_BASE="bartowski/Qwen_Qwen3-1.7B-GGUF"
readonly DEFAULT_MODEL_FILE_BASE="Qwen_Qwen3-1.7B-Q4_K_M.gguf"
readonly DEFAULT_MODEL_SPEC_BASE="${DEFAULT_MODEL_REPO_BASE}:${DEFAULT_MODEL_FILE_BASE}"
readonly DEFAULT_MODEL_BRANCH_BASE="main"
readonly DEFAULT_REACT_MODEL_SPEC_BASE="${DEFAULT_MODEL_SPEC_BASE}"
readonly DEFAULT_REACT_MODEL_BRANCH_BASE="${DEFAULT_MODEL_BRANCH_BASE}"

readonly DEFAULT_PLANNER_MODEL_REPO_BASE="bartowski/Qwen_Qwen3-8B-GGUF"
readonly DEFAULT_PLANNER_MODEL_FILE_BASE="Qwen_Qwen3-8B-Q4_K_M.gguf"
readonly DEFAULT_PLANNER_MODEL_SPEC_BASE="${DEFAULT_PLANNER_MODEL_REPO_BASE}:${DEFAULT_PLANNER_MODEL_FILE_BASE}"
readonly DEFAULT_PLANNER_MODEL_BRANCH_BASE="main"

normalize_boolean_input() {
	# Arguments:
	#   $1 - input value (string)
	#   $2 - fallback value when input is invalid (string; defaults to "false")
	local value fallback
	value="$1"
	fallback="${2:-false}"

	case "${value}" in
	true | True | TRUE | 1)
		printf 'true'
		;;
	false | False | FALSE | 0)
		printf 'false'
		;;
	*)
		printf '%s' "${fallback}"
		;;
	esac
}

apply_supervised_overrides() {
	local supervised_raw supervised
	supervised_raw="${OKSO_SUPERVISED:-}"
	if [[ -z "${supervised_raw}" ]]; then
		return 0
	fi

	supervised=$(normalize_boolean_input "${supervised_raw}" "true")
	if [[ "${supervised}" == false ]]; then
		APPROVE_ALL=true
	else
		APPROVE_ALL=false
	fi
}

apply_verbosity_overrides() {
	local verbosity_override
	verbosity_override="${OKSO_VERBOSITY:-}"
	if [[ -z "${verbosity_override}" ]]; then
		return 0
	fi

	VERBOSITY="${verbosity_override}"
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
	# Load file-backed configuration first so environment overrides and CLI flags
	# can layer on top in a predictable order.
	local model_spec_override model_branch_override preexisting_okso_google_cse_api_key preexisting_okso_google_cse_id
	local model_spec_was_set planner_model_spec_was_set model_branch_was_set planner_model_branch_was_set
	# string: preserve preexisting environment values so they can override config file entries.
	preexisting_okso_google_cse_api_key="${OKSO_GOOGLE_CSE_API_KEY:-}"
	preexisting_okso_google_cse_id="${OKSO_GOOGLE_CSE_ID:-}"
	if [[ -f "${CONFIG_FILE}" ]]; then
		# shellcheck source=/dev/null
		source "${CONFIG_FILE}"
	fi

	OKSO_GOOGLE_CSE_API_KEY="${preexisting_okso_google_cse_api_key:-${OKSO_GOOGLE_CSE_API_KEY:-}}"
	OKSO_GOOGLE_CSE_ID="${preexisting_okso_google_cse_id:-${OKSO_GOOGLE_CSE_ID:-}}"

	model_spec_was_set=${MODEL_SPEC+x}
	planner_model_spec_was_set=${PLANNER_MODEL_SPEC+x}
	model_branch_was_set=${MODEL_BRANCH+x}
	planner_model_branch_was_set=${PLANNER_MODEL_BRANCH+x}

	DEFAULT_MODEL_FILE=${DEFAULT_MODEL_FILE:-${DEFAULT_MODEL_FILE_BASE}}
	DEFAULT_PLANNER_MODEL_FILE=${DEFAULT_PLANNER_MODEL_FILE:-${DEFAULT_PLANNER_MODEL_FILE_BASE}}

	MODEL_SPEC=${MODEL_SPEC:-"${DEFAULT_REACT_MODEL_SPEC_BASE}"}
	MODEL_BRANCH=${MODEL_BRANCH:-${DEFAULT_REACT_MODEL_BRANCH_BASE}}
	PLANNER_MODEL_SPEC=${PLANNER_MODEL_SPEC:-"${DEFAULT_PLANNER_MODEL_SPEC_BASE}"}
	PLANNER_MODEL_BRANCH=${PLANNER_MODEL_BRANCH:-${DEFAULT_PLANNER_MODEL_BRANCH_BASE}}
	REACT_MODEL_SPEC=${REACT_MODEL_SPEC:-"${MODEL_SPEC}"}
	REACT_MODEL_BRANCH=${REACT_MODEL_BRANCH:-${MODEL_BRANCH}}
	VERBOSITY=${VERBOSITY:-1}
	APPROVE_ALL=${APPROVE_ALL:-false}
	FORCE_CONFIRM=${FORCE_CONFIRM:-false}

	if [[ -n "${OKSO_MODEL:-}" ]]; then
		model_spec_override="${OKSO_MODEL}"
		MODEL_SPEC="${model_spec_override}"
	fi

	if [[ -n "${OKSO_MODEL_BRANCH:-}" ]]; then
		model_branch_override="${OKSO_MODEL_BRANCH}"
		MODEL_BRANCH="${model_branch_override}"
	fi

	REACT_MODEL_SPEC=${REACT_MODEL_SPEC:-"${MODEL_SPEC}"}
	REACT_MODEL_BRANCH=${REACT_MODEL_BRANCH:-"${MODEL_BRANCH}"}

	if [[ -z "${planner_model_spec_was_set:-}" && -n "${model_spec_was_set:-}" ]]; then
		PLANNER_MODEL_SPEC="${MODEL_SPEC}"
	fi
	if [[ -z "${planner_model_branch_was_set:-}" && -n "${model_branch_was_set:-}" ]]; then
		PLANNER_MODEL_BRANCH="${MODEL_BRANCH}"
	fi

	GOOGLE_SEARCH_API_KEY=${GOOGLE_SEARCH_API_KEY:-${OKSO_GOOGLE_CSE_API_KEY:-}}
	GOOGLE_SEARCH_CX=${GOOGLE_SEARCH_CX:-${OKSO_GOOGLE_CSE_ID:-}}

	apply_supervised_overrides
	apply_verbosity_overrides
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
MODEL_SPEC=$(quote_config_value "${MODEL_SPEC}")
MODEL_BRANCH=$(quote_config_value "${MODEL_BRANCH}")
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
	local model_spec_was_set model_branch_was_set

	model_spec_was_set=${MODEL_SPEC+x}
	model_branch_was_set=${MODEL_BRANCH+x}

	DEFAULT_PLANNER_MODEL_FILE=${DEFAULT_PLANNER_MODEL_FILE:-${DEFAULT_PLANNER_MODEL_FILE_BASE}}
	DEFAULT_MODEL_FILE=${DEFAULT_MODEL_FILE:-${DEFAULT_MODEL_FILE_BASE}}

	MODEL_SPEC=${MODEL_SPEC:-"${DEFAULT_REACT_MODEL_SPEC_BASE}"}
	MODEL_BRANCH=${MODEL_BRANCH:-"${DEFAULT_REACT_MODEL_BRANCH_BASE}"}

	REACT_MODEL_SPEC=${REACT_MODEL_SPEC:-"${MODEL_SPEC}"}
	REACT_MODEL_BRANCH=${REACT_MODEL_BRANCH:-"${MODEL_BRANCH}"}

	if [[ -z "${PLANNER_MODEL_SPEC:-}" ]]; then
		if [[ -n "${model_spec_was_set}" ]]; then
			PLANNER_MODEL_SPEC="${MODEL_SPEC}"
		else
			PLANNER_MODEL_SPEC="${DEFAULT_PLANNER_MODEL_SPEC_BASE}"
		fi
	fi

	if [[ -z "${PLANNER_MODEL_BRANCH:-}" ]]; then
		if [[ -n "${model_branch_was_set}" ]]; then
			PLANNER_MODEL_BRANCH="${MODEL_BRANCH}"
		else
			PLANNER_MODEL_BRANCH="${DEFAULT_PLANNER_MODEL_BRANCH_BASE}"
		fi
	fi

	PLANNER_MODEL_BRANCH=${PLANNER_MODEL_BRANCH:-"${DEFAULT_PLANNER_MODEL_BRANCH_BASE}"}
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
