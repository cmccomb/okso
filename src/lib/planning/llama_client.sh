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
#   LLAMA_TIMEOUT_SECONDS (int): timeout in seconds for llama.cpp invocations (0 disables the timeout).
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

# shellcheck source=../core/logging.sh disable=SC1091
source "${LIB_DIR}/../core/logging.sh"

sanitize_llama_output() {
	# Normalizes llama.cpp output before downstream usage.
	# Arguments:
	#   $1 - raw llama output (string)
	local raw sanitized
	raw="$1"
	sanitized="${raw//$'\r\n'/$'\n'}"
	sanitized="${sanitized//$'\r'/$'\n'}"
	sanitized="${sanitized//$'\t'/ }"
	sanitized="${sanitized//\[end of text\]/}"
	sanitized="$(printf '%s' "${sanitized}" | sed -e 's/[[:space:]]\+$//')"
	printf '%s' "${sanitized}"
}

llama_with_timeout() {
	# Executes llama.cpp with an optional timeout.
	# Arguments:
	#   $@ - command and arguments to execute
	local timeout_seconds
	timeout_seconds=${LLAMA_TIMEOUT_SECONDS:-0}

	if [[ ${timeout_seconds} -gt 0 ]]; then
		if command -v timeout >/dev/null 2>&1; then
			timeout "${timeout_seconds}" "$@"
			return $?
		fi

		if command -v perl >/dev/null 2>&1; then
			perl -e '$timeout = shift; eval { local $SIG{ALRM} = sub { die "TIMEOUT\n" }; alarm $timeout; system(@ARGV); alarm 0; }; if ($@ eq "TIMEOUT\n") { exit 124 } else { exit ($? >> 8) }' "${timeout_seconds}" "$@"
			return $?
		fi

		log "WARN" "Timeout requested but unsupported; running without it" "requested_timeout=${timeout_seconds}"
	fi

	"$@"
}

llama_infer() {
	# Runs llama.cpp with HF caching enabled for the configured model.
	# Arguments:
	#   $1 - prompt string
	#   $2 - stop string (optional)
	#   $3 - max tokens (optional)
	#   $4 - schema file path (optional)
	local prompt stop_string number_of_tokens schema_file_path schema_content
	prompt="$1"
	stop_string="${2:-}"
	number_of_tokens="${3:-256}"
	schema_file_path="${4:-}"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "llama unavailable; skipping inference" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}"
		return 1
	fi

	local additional_args
	additional_args=()

	if [[ -n "${schema_file_path}" ]]; then
		if [[ "${schema_file_path}" == *.json ]]; then
			if ! schema_content=$(cat -- "${schema_file_path}" 2>/dev/null); then
				log "ERROR" "failed to read JSON schema" "path=${schema_file_path}"
				return 1
			fi
			additional_args+=(--json-schema "${schema_content}")
		else
			additional_args+=(--grammar-file "${schema_file_path}")
		fi
	fi

	local llama_args llama_arg_string stderr_file exit_code llama_stderr start_time_ns end_time_ns elapsed_ms llama_output
	llama_args=(
		"${LLAMA_BIN}"
		--hf-repo "${MODEL_REPO}"
		--hf-file "${MODEL_FILE}"
		-no-cnv --no-display-prompt --simple-io --verbose
		-n "${number_of_tokens}"
	)

	if [[ -n "${stop_string}" ]]; then
		llama_args+=(-r "${stop_string}")
	fi

	llama_args+=("${additional_args[@]}")

	llama_args+=(-p "${prompt}")

	llama_arg_string=$(printf '%s ' "${llama_args[@]:1}")
	llama_arg_string=${llama_arg_string% }

	stderr_file="$(mktemp)"

	start_time_ns=$(date +%s%N)

	if [[ "${VERBOSITY:-0}" -ge 2 ]]; then
		log "DEBUG" "llama prompt" "${prompt}"
	fi

	llama_output=$(llama_with_timeout "${llama_args[@]}" 2>"${stderr_file}")
	exit_code=$?

	end_time_ns=$(date +%s%N)
	elapsed_ms=$(((end_time_ns - start_time_ns) / 1000000))

	if [[ ${exit_code} -eq 124 || ${exit_code} -eq 137 || ${exit_code} -eq 143 ]]; then
		llama_stderr="$(<"${stderr_file}")"
		log "ERROR" "llama inference timed out" "bin=${LLAMA_BIN} args=${llama_arg_string} timeout_seconds=${LLAMA_TIMEOUT_SECONDS:-0} elapsed_ms=${elapsed_ms} stderr=${llama_stderr}"
		rm -f "${stderr_file}"
		return "${exit_code}"
	fi

	if [[ ${exit_code} -ne 0 ]]; then
		llama_stderr="$(<"${stderr_file}")"
		log "ERROR" "llama inference failed" "bin=${LLAMA_BIN} args=${llama_arg_string} elapsed_ms=${elapsed_ms} stderr=${llama_stderr}"
		rm -f "${stderr_file}"
		return "${exit_code}"
	fi

	llama_output="$(sanitize_llama_output "${llama_output}")"
	printf '%s' "${llama_output}"
	rm -f "${stderr_file}"
}
