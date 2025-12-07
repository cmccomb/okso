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
#   MODEL_SPEC (string): HF repo[:file] spec; may be overridden by DO_MODEL.
#   MODEL_BRANCH (string): HF branch; may be overridden by DO_MODEL_BRANCH.
#   TESTING_PASSTHROUGH (bool): forces llama calls off during tests.
#   APPROVE_ALL (bool): skip prompts when true.
#   FORCE_CONFIRM (bool): always prompt when true.
#   VERBOSITY (int): logging verbosity.
#   DEFAULT_MODEL_FILE (string): fallback file name for parsing model spec.
#
# Dependencies:
#   - bash 5+
#   - mkdir, cat
#
# Exit codes:
#   1 when required arguments are missing during flag parsing.
#   2 when model resolution fails.

# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/config.sh}/logging.sh"

detect_config_file() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--config)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--config requires a path"
				exit 1
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
	if [[ -f "${CONFIG_FILE}" ]]; then
		# shellcheck source=/dev/null
		source "${CONFIG_FILE}"
	fi

	MODEL_SPEC=${MODEL_SPEC:-"Qwen/Qwen3-1.5B-Instruct-GGUF:${DEFAULT_MODEL_FILE}"}
	MODEL_BRANCH=${MODEL_BRANCH:-main}
	VERBOSITY=${VERBOSITY:-1}
	APPROVE_ALL=${APPROVE_ALL:-false}
	FORCE_CONFIRM=${FORCE_CONFIRM:-false}

	if [[ -n "${DO_MODEL:-}" ]]; then
		MODEL_SPEC="${DO_MODEL}"
	fi
	if [[ -n "${DO_MODEL_BRANCH:-}" ]]; then
		MODEL_BRANCH="${DO_MODEL_BRANCH}"
	fi
	if [[ -n "${DO_SUPERVISED:-}" ]]; then
		case "${DO_SUPERVISED}" in
		false | False | FALSE | 0)
			APPROVE_ALL=true
			;;
		*)
			APPROVE_ALL=false
			;;
		esac
	fi
	if [[ -n "${DO_VERBOSITY:-}" ]]; then
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
		repo="${spec}"
		file="${default_file}"
	fi

	printf '%s\n%s\n' "${repo}" "${file}"
}

normalize_approval_flags() {
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
	mapfile -t model_parts < <(parse_model_spec "${MODEL_SPEC}" "${DEFAULT_MODEL_FILE}")
	# shellcheck disable=SC2034
	MODEL_REPO="${model_parts[0]}"
	# shellcheck disable=SC2034
	MODEL_FILE="${model_parts[1]}"
}

init_environment() {
	normalize_approval_flags
	hydrate_model_spec

	if command -v uname >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
		# shellcheck disable=SC2034
		IS_MACOS=true
	fi

        if [[ "${TESTING_PASSTHROUGH:-false}" == true ]]; then
                LLAMA_AVAILABLE=false
        else
                LLAMA_AVAILABLE=true
        fi

        if [[ "${LLAMA_AVAILABLE}" == true && ! -x "${LLAMA_BIN}" ]]; then
                log "WARN" "llama.cpp binary not found" "${LLAMA_BIN}"
                LLAMA_AVAILABLE=false
        fi

	mkdir -p "${NOTES_DIR}"
}
