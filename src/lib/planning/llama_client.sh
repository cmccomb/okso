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

prompt_cache_metadata_path() {
	# Arguments:
	#   $1 - cache file path (string)
	printf '%s.meta.json' "$1"
}

derive_prompt_cache_key() {
	# Arguments:
	#   $1 - model repo (string)
	#   $2 - model file (string)
	#   $3 - context window (string)
	#   $4 - rope freq base (string)
	#   $5 - rope freq scale (string)
	#   $6 - template descriptor (string)
	#   $7 - grammar descriptor (string)
	local fingerprint
	fingerprint=$(printf '%s' "$1|$2|$3|$4|$5|$6|$7")
	printf '%s' "${fingerprint}" | sha256sum | awk '{print $1}'
}

prompt_cache_metadata_json() {
	# Arguments:
	#   $1 - cache key (string)
	#   $2 - model repo (string)
	#   $3 - model file (string)
	#   $4 - context window (string)
	#   $5 - rope freq base (string)
	#   $6 - rope freq scale (string)
	#   $7 - template descriptor (string)
	#   $8 - grammar descriptor (string)
	jq -nc \
		--arg key "$1" \
		--arg model_repo "$2" \
		--arg model_file "$3" \
		--argjson context "${4:-0}" \
		--arg rope_freq_base "$5" \
		--arg rope_freq_scale "$6" \
		--arg template "$7" \
		--arg grammar "$8" \
		'{
                        key: $key,
                        model: {repo: $model_repo, file: $model_file},
                        context: $context,
                        rope: {freq_base: $rope_freq_base, freq_scale: $rope_freq_scale},
                        template: $template,
                        grammar: $grammar
                }'
}

rotate_prompt_cache_if_stale() {
	# Arguments:
	#   $1 - cache file path (string)
	#   $2 - expected cache key (string)
	local cache_file cache_key metadata_path existing_key rotation_suffix
	cache_file="$1"
	cache_key="$2"
	metadata_path="$(prompt_cache_metadata_path "${cache_file}")"

	if [[ -f "${metadata_path}" ]]; then
		existing_key=$(jq -r '.key // ""' "${metadata_path}" 2>/dev/null || printf '')
	fi

	if [[ -n "${existing_key:-}" && "${existing_key}" != "${cache_key}" ]]; then
		rotation_suffix="$(date -u +"%Y%m%dT%H%M%SZ")"
		mv "${cache_file}" "${cache_file}.${rotation_suffix}.bak" 2>/dev/null || true
		mv "${metadata_path}" "${metadata_path}.${rotation_suffix}.bak" 2>/dev/null || true
		log "INFO" "Rotated prompt cache" "cache=${cache_file} old_key=${existing_key} new_key=${cache_key}"
	fi
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
	#   $7 - prompt cache path (string, optional)
	#   $8 - static prompt prefix for llama.cpp cache priming (string, optional)
	# Returns:
	#   The generated text (string).
	local prompt stop_string number_of_tokens schema_json repo_override file_override cache_file static_prompt
	prompt="$1"
	stop_string="${2:-}"
	number_of_tokens="${3:-256}"
	schema_json="${4:-}"
	repo_override="${5:-${REACT_MODEL_REPO:-}}"
	file_override="${6:-${REACT_MODEL_FILE:-}}"
	cache_file="${7:-}"
	static_prompt="${8:-}"

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "llama unavailable; skipping inference" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}"
		return 1
	fi

	local additional_args
	additional_args=()

	if [[ -n "${schema_json}" ]]; then
		additional_args+=(--json-schema "${schema_json}")
	fi

	if [[ -n "${static_prompt}" ]]; then
		additional_args+=(--prompt-cache-static "${static_prompt}")
	fi

	local llama_args llama_arg_string stderr_file exit_code llama_stderr start_time_ns end_time_ns elapsed_ms llama_output
	local default_context_size context_cap margin_percent prompt_tokens total_tokens computed_context target_context
	local rope_freq_base rope_freq_scale template_descriptor grammar_descriptor grammar_hash cache_key metadata_path metadata_json
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
	target_context=${default_context_size}

	if [[ ${computed_context} -gt ${default_context_size} ]]; then
		target_context=${computed_context}
		if [[ ${target_context} -gt ${context_cap} ]]; then
			log "INFO" "llama context capped" "required_context=${target_context} capped_context=${context_cap} default_context=${default_context_size}"
			target_context=${context_cap}
		fi

		llama_args+=(-c "${target_context}")
	fi

	if [[ -n "${stop_string}" ]]; then
		llama_args+=(-r "${stop_string}")
	fi

	rope_freq_base="${LLAMA_ROPE_FREQ_BASE:-}"
	rope_freq_scale="${LLAMA_ROPE_FREQ_SCALE:-}"
	template_descriptor="${LLAMA_TEMPLATE:-}"
	grammar_descriptor=""

	if [[ -n "${rope_freq_base}" ]]; then
		llama_args+=(--rope-freq-base "${rope_freq_base}")
	fi

	if [[ -n "${rope_freq_scale}" ]]; then
		llama_args+=(--rope-freq-scale "${rope_freq_scale}")
	fi

	if [[ -n "${template_descriptor}" ]]; then
		llama_args+=(--template "${template_descriptor}")
	fi

	if [[ -n "${schema_json}" ]]; then
		grammar_hash=$(printf '%s' "${schema_json}" | sha256sum | awk '{print $1}')
		grammar_descriptor="json-schema:${grammar_hash}"
	fi

	if [[ -n "${LLAMA_GRAMMAR:-}" ]]; then
		llama_args+=(--grammar "${LLAMA_GRAMMAR}")
		if [[ -z "${grammar_descriptor}" ]]; then
			grammar_descriptor="grammar:${LLAMA_GRAMMAR}"
		else
			grammar_descriptor="${grammar_descriptor}|grammar:${LLAMA_GRAMMAR}"
		fi
	fi

	llama_args+=("${additional_args[@]}")

	if [[ -n "${cache_file}" ]]; then
		cache_key=$(derive_prompt_cache_key "${repo_override}" "${file_override}" "${target_context}" "${rope_freq_base}" "${rope_freq_scale}" "${template_descriptor}" "${grammar_descriptor}")
		metadata_json=$(prompt_cache_metadata_json "${cache_key}" "${repo_override}" "${file_override}" "${target_context}" "${rope_freq_base}" "${rope_freq_scale}" "${template_descriptor}" "${grammar_descriptor}")
		rotate_prompt_cache_if_stale "${cache_file}" "${cache_key}"
		metadata_path="$(prompt_cache_metadata_path "${cache_file}")"
		printf '%s\n' "${metadata_json}" >"${metadata_path}"
		llama_args+=(--prompt-cache "${cache_file}" --prompt-cache-all)
	fi

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
