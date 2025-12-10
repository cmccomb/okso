#!/usr/bin/env bash
# shellcheck shell=bash
#
# llama.cpp client helpers for local inference.
#
# Usage:
#   source "${BASH_SOURCE[0]%/llama_client.sh}/llama_client.sh"
#
# Environment variables:
#   LLAMA_AVAILABLE (bool): whether llama.cpp is available for inference.
#   LLAMA_BIN (string): path to llama.cpp binary.
#   MODEL_REPO (string): Hugging Face repository name.
#   MODEL_FILE (string): model file within the repository.
#   VERBOSITY (int): log verbosity.
#
# Dependencies:
#   - bash 5+
#   - jq
#
# Exit codes:
#   Returns non-zero when llama.cpp is unavailable; otherwise mirrors llama.cpp.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./logging.sh disable=SC1091
source "${LIB_DIR}/logging.sh"

llama_infer() {
	# Runs llama.cpp with HF caching enabled for the configured model.
	# Arguments:
	#   $1 - prompt string
	#   $2 - stop string (optional)
	#   $3 - max tokens (optional)
	#   $4 - grammar file path (optional)
	local prompt stop_string number_of_tokens grammar_file_path
	prompt="$1"
	stop_string="${2:-}"
	number_of_tokens="${3:-256}"
	grammar_file_path="${4:-}"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "llama unavailable; skipping inference" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}"
		return 1
	fi

	local additional_args
	additional_args=()

	if [[ -n "${grammar_file_path}" ]]; then
		if [[ "${grammar_file_path}" == *.json ]]; then
			additional_args+=(--json-schema-file "${grammar_file_path}")
		else
			additional_args+=(--grammar-file "${grammar_file_path}")
		fi
	fi

        local llama_args llama_arg_string stderr_file exit_code llama_stderr
        llama_args=(
                "${LLAMA_BIN}"
                --hf-repo "${MODEL_REPO}"
                --hf-file "${MODEL_FILE}"
                -no-cnv --no-display-prompt --simple-io --verbose
                -n "${number_of_tokens}"
                -p "${prompt}"
        )

        if [[ -n "${stop_string}" ]]; then
                llama_args+=(-r "${stop_string}")
        fi

        llama_args+=("${additional_args[@]}")

        llama_arg_string=$(printf '%s ' "${llama_args[@]:1}")
        llama_arg_string=${llama_arg_string% }

        stderr_file="$(mktemp)"

        "${llama_args[@]}" 2>"${stderr_file}"
        exit_code=$?

        if [[ ${exit_code} -ne 0 ]]; then
                llama_stderr="$(<"${stderr_file}")"
                log "ERROR" "llama inference failed" "bin=${LLAMA_BIN} args=${llama_arg_string} stderr=${llama_stderr}"
                rm -f "${stderr_file}"
                return "${exit_code}"
        fi

        rm -f "${stderr_file}"
}
