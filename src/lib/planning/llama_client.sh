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
#   LLAMA_DEFAULT_CONTEXT_SIZE (int): assumed llama.cpp default context window.
#   LLAMA_CONTEXT_CAP (int): maximum context window to request for llama.cpp invocations.
#   LLAMA_CONTEXT_MARGIN_PERCENT (int): percentage safety margin added to context estimates.
#   REACT_MODEL_REPO (string): Hugging Face repository name for the ReAct loop.
#   REACT_MODEL_FILE (string): model file within the repository for the ReAct loop.
#   VERBOSITY (int): log verbosity.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Returns non-zero when llama.cpp is unavailable; otherwise mirrors llama.cpp.

PLANNING_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_LIB_DIR}/../core/logging.sh"

estimate_token_count() {
	# Estimates the number of tokens in a string based on character length.
	# Arguments:
	#   $1 - text content (string)
	local text length token_estimate
	text="$1"
	length=${#text}
	token_estimate=$(((length + 3) / 4))
	printf '%s' "${token_estimate}"
}

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
	# Runs llama.cpp with Hugging Face repository caching for inference.
	# Arguments:
	#   $1 - prompt string (string)
	#   $2 - stop string (string, optional)
	#   $3 - max tokens to generate (int, default: 256)
	#   $4 - JSON schema document for constrained decoding (string, optional)
	#   $5 - model repository override (string, optional)
	#   $6 - model file override (string, optional)
	# Returns:
	#   The generated text (string).
	local prompt stop_string number_of_tokens schema_json repo_override file_override
	prompt="$1"
	stop_string="${2:-}"
	number_of_tokens="${3:-256}"
	schema_json="${4:-}"
	repo_override="${5:-${REACT_MODEL_REPO:-}}"
	file_override="${6:-${REACT_MODEL_FILE:-}}"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "llama unavailable; skipping inference" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}"
		return 1
	fi

	local additional_args
	additional_args=()

	if [[ -n "${schema_json}" ]]; then
		additional_args+=(--json-schema "${schema_json}")
	fi

	local llama_args llama_arg_string stderr_file exit_code llama_stderr start_time_ns end_time_ns elapsed_ms llama_output
	local default_context_size context_cap margin_percent prompt_tokens total_tokens computed_context target_context
	llama_args=(
		"${LLAMA_BIN}"
		--hf-repo "${repo_override}"
		--hf-file "${file_override}"
		-no-cnv --no-display-prompt --simple-io --verbose
		-n "${number_of_tokens}"
	)

	default_context_size=${LLAMA_DEFAULT_CONTEXT_SIZE:-4096}
	context_cap=${LLAMA_CONTEXT_CAP:-8192}
	margin_percent=${LLAMA_CONTEXT_MARGIN_PERCENT:-15}

	if [[ ${context_cap} -lt ${default_context_size} ]]; then
		context_cap=${default_context_size}
	fi

	prompt_tokens=$(estimate_token_count "${prompt}")
	total_tokens=$((prompt_tokens + number_of_tokens))
	computed_context=$(((total_tokens * (100 + margin_percent) + 99) / 100))
	target_context=${computed_context}

	if [[ ${target_context} -gt ${default_context_size} ]]; then
		if [[ ${target_context} -gt ${context_cap} ]]; then
			log "INFO" "llama context capped" "required_context=${target_context} capped_context=${context_cap} default_context=${default_context_size}"
			target_context=${context_cap}
		fi

		llama_args+=(-c "${target_context}")
	fi

	if [[ -n "${stop_string}" ]]; then
		llama_args+=(-r "${stop_string}")
	fi

	llama_args+=("${additional_args[@]}")

	llama_args+=(-p "${prompt}")

	llama_arg_string=$(printf '%s ' "${llama_args[@]:1}")
	llama_arg_string=${llama_arg_string% }

	stderr_file="$(mktemp)"

	start_time_ns=$(date +%s)
	start_time_ns=$((start_time_ns * 1000000000))

	if [[ "${VERBOSITY:-0}" -ge 2 ]]; then
		log "DEBUG" "llama args" "${llama_arg_string}"
	fi

	llama_output=$(llama_with_timeout "${llama_args[@]}" 2>"${stderr_file}")
	exit_code=$?

	end_time_ns=$(date +%s)
	end_time_ns=$((end_time_ns * 1000000000))
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
