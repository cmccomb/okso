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
#   TESTING_PASSTHROUGH (bool): forces llama calls off during tests.
#   APPROVE_ALL (bool): skip prompts when true.
#   FORCE_CONFIRM (bool): always prompt when true.
#   VERBOSITY (int): logging verbosity; may be overridden by OKSO_VERBOSITY.
#   DEFAULT_MODEL_FILE (string): fallback file name for parsing model spec.
#
#   The following okso-branded variables take precedence over legacy aliases:
#     OKSO_MODEL, OKSO_MODEL_BRANCH, OKSO_SUPERVISED, OKSO_VERBOSITY
#   Legacy aliases retained for compatibility:
#     DO_MODEL, DO_MODEL_BRANCH, DO_SUPERVISED, DO_VERBOSITY
#
# Dependencies:
#   - bash 5+
#   - mkdir, cat
#
# Exit codes:
#   1 when required arguments are missing during flag parsing.
#   2 when model resolution fails.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./logging.sh disable=SC1091
source "${LIB_DIR}/logging.sh"

readonly DEFAULT_MODEL_REPO_BASE="bartowski/Qwen_Qwen3-4B-GGUF"
readonly DEFAULT_MODEL_FILE_BASE="Qwen_Qwen3-4B-Q4_K_M.gguf"
#readonly DEFAULT_MODEL_REPO_BASE="bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF"
#readonly DEFAULT_MODEL_FILE_BASE="Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
readonly DEFAULT_MODEL_SPEC_BASE="${DEFAULT_MODEL_REPO_BASE}:${DEFAULT_MODEL_FILE_BASE}"
readonly DEFAULT_MODEL_BRANCH_BASE="main"

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
	if [[ -f "${CONFIG_FILE}" ]]; then
		# shellcheck source=/dev/null
		source "${CONFIG_FILE}"
	fi

	MODEL_SPEC=${MODEL_SPEC:-"${DEFAULT_MODEL_SPEC_BASE}"}
	MODEL_BRANCH=${MODEL_BRANCH:-${DEFAULT_MODEL_BRANCH_BASE}}
	VERBOSITY=${VERBOSITY:-1}
	APPROVE_ALL=${APPROVE_ALL:-false}
	FORCE_CONFIRM=${FORCE_CONFIRM:-false}

	if [[ -n "${OKSO_MODEL:-}" ]]; then
		MODEL_SPEC="${OKSO_MODEL}"
	elif [[ -n "${DO_MODEL:-}" ]]; then
		MODEL_SPEC="${DO_MODEL}"
	fi
	if [[ -n "${OKSO_MODEL_BRANCH:-}" ]]; then
		MODEL_BRANCH="${OKSO_MODEL_BRANCH}"
	elif [[ -n "${DO_MODEL_BRANCH:-}" ]]; then
		MODEL_BRANCH="${DO_MODEL_BRANCH}"
	fi
	if [[ -n "${OKSO_SUPERVISED:-}" ]]; then
		# OKSO_SUPERVISED mirrors the hosted behavior where "false" should allow
		# automated tool execution without a prompt.
		case "${OKSO_SUPERVISED}" in
		false | False | FALSE | 0)
			APPROVE_ALL=true
			;;
		*)
			APPROVE_ALL=false
			;;
		esac
	elif [[ -n "${DO_SUPERVISED:-}" ]]; then
		# DO_SUPERVISED mirrors the hosted behavior where "false" should allow
		# automated tool execution without a prompt.
		case "${DO_SUPERVISED}" in
		false | False | FALSE | 0)
			APPROVE_ALL=true
			;;
		*)
			APPROVE_ALL=false
			;;
		esac
	fi
	if [[ -n "${OKSO_VERBOSITY:-}" ]]; then
		VERBOSITY="${OKSO_VERBOSITY}"
	elif [[ -n "${DO_VERBOSITY:-}" ]]; then
		VERBOSITY="${DO_VERBOSITY}"
	fi
}

write_config_file() {
	mkdir -p "$(dirname "${CONFIG_FILE}")"
	cat >"${CONFIG_FILE}" <<EOF_CONFIG
	MODEL_SPEC="${MODEL_SPEC}"
	MODEL_BRANCH="${MODEL_BRANCH}"
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

hydrate_model_spec() {
	# Normalizes MODEL_SPEC into repo and file components for llama.cpp calls.
	local model_parts
	# parse_model_spec prints repo then file on separate lines for easy mapfile
	# consumption; we preserve that order here explicitly.
	model_parts=()
	while IFS= read -r line; do
		model_parts+=("$line")
	done < <(parse_model_spec "$MODEL_SPEC" "$DEFAULT_MODEL_FILE")
	# shellcheck disable=SC2034
	MODEL_REPO="${model_parts[0]}"
	# shellcheck disable=SC2034
	MODEL_FILE="${model_parts[1]}"
}

init_environment() {
	normalize_approval_flags
	hydrate_model_spec

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
