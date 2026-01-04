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
#   EXECUTOR_MODEL_REPO (string): Hugging Face repository name for the executor.
#   EXECUTOR_MODEL_FILE (string): model file within the repository for the executor.
#   EXECUTOR_CACHE_FILE (string): prompt cache path for executor llama.cpp calls.
#   LLAMA_EXTRA_ARGS (string): optional additional llama.cpp arguments appended before the prompt.
#   VERBOSITY (int): log verbosity.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Returns non-zero when llama.cpp is unavailable; otherwise mirrors llama.cpp.

LLM_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${LLM_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/llm/tokens.sh
source "${LLM_LIB_DIR}/tokens.sh"

llama_with_timeout() {
	# Executes llama.cpp with an optional timeout.
	# Arguments:
	#   $@ - command and arguments to execute
	# Returns:
	#   The exit code of the command, or 124 if timed out.

	local timeout_seconds
	timeout_seconds=${LLAMA_TIMEOUT_SECONDS:-0}

	if [[ ${timeout_seconds} -gt 0 ]]; then
		perl - "${timeout_seconds}" "$@" <<'PERL'
my $timeout = shift @ARGV;

eval {
  local $SIG{ALRM} = sub { die "TIMEOUT\n" };
  alarm $timeout;
  system @ARGV;
  alarm 0;
};

if ($@ eq "TIMEOUT\n") {
  exit 124;
} else {
  exit ($? >> 8);
}
PERL
		return $?
	fi

	"$@"
}

sanitize_llama_output() {
	# Normalizes llama.cpp output before downstream usage.
	# Arguments:
	#   $1 - raw llama output (string)
	local raw sanitized
	raw="$1"

	# Replace CRLF and CR line endings with LF
	sanitized="${raw//$'\r\n'/$'\n'}"

	# Replace carriage returns with newlines
	sanitized="${sanitized//$'\r'/$'\n'}"

	# Replace newlines with spaces
	sanitized="${sanitized//$'\t'/ }"

	# Collapse multiple spaces
	sanitized="${sanitized//\[end of text\]/}"

	# Collapse multiple spaces
	sanitized="$(printf '%s' "${sanitized}" | sed -e 's/[[:space:]]\+$//')"

	# Return sanitized output
	printf '%s' "${sanitized}"
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
	repo_override="${5:-${EXECUTOR_MODEL_REPO:-}}"
	file_override="${6:-${EXECUTOR_MODEL_FILE:-}}"

	# Check llama availability
	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "llama unavailable; skipping inference" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}"
		return 1
	fi

	# Build llama.cpp arguments
	local llama_args llama_arg_string stderr_file exit_code llama_stderr start_time_ns end_time_ns elapsed_ms llama_output
	local default_context_size context_cap margin_percent prompt_tokens total_tokens computed_context target_context
	local rope_freq_base rope_freq_scale template_descriptor prompt_context_detail
	llama_args=(
		"${LLAMA_BIN}"
		--hf-repo "${repo_override}"
		--hf-file "${file_override}"
		-no-cnv --no-display-prompt --simple-io --verbose
		-n "${number_of_tokens}"
	)

	# Determine context size
	default_context_size=${LLAMA_DEFAULT_CONTEXT_SIZE:-4096}
	context_cap=${LLAMA_CONTEXT_CAP:-8192}
	margin_percent=${LLAMA_CONTEXT_MARGIN_PERCENT:-15}

	# Ensure context cap is at least the default context size
	if [[ ${context_cap} -lt ${default_context_size} ]]; then
		context_cap=${default_context_size}
	fi

	# Estimate required context size
	prompt_tokens=$(estimate_token_count "${prompt}")
	total_tokens=$((prompt_tokens + number_of_tokens))
	computed_context=$(((total_tokens * (100 + margin_percent) + 99) / 100))
	target_context=${default_context_size}

	# Adjust context size if needed
	if [[ ${computed_context} -gt ${default_context_size} ]]; then
		target_context=${computed_context}
		if [[ ${target_context} -gt ${context_cap} ]]; then
			log "INFO" "llama context capped" "required_context=${target_context} capped_context=${context_cap} default_context=${default_context_size}"
			target_context=${context_cap}
		fi

		llama_args+=(-c "${target_context}")
	fi

	# Add stop string if provided
	if [[ -n "${stop_string}" ]]; then
		llama_args+=(-r "${stop_string}")
	fi

	# Add temperature if provided
	if [[ -n "${LLAMA_TEMPERATURE:-}" ]]; then
		llama_args+=(--temp "${LLAMA_TEMPERATURE}")
	fi

	# Add JSON schema if provided
	if [[ -n "${schema_json}" ]]; then
		llama_args+=(--json-schema "${schema_json}")
	fi

	# Add optional rope frequency parameters
	rope_freq_base="${LLAMA_ROPE_FREQ_BASE:-}"
	rope_freq_scale="${LLAMA_ROPE_FREQ_SCALE:-}"
	if [[ -n "${rope_freq_base}" ]]; then
		llama_args+=(--rope-freq-base "${rope_freq_base}")
	fi
	if [[ -n "${rope_freq_scale}" ]]; then
		llama_args+=(--rope-freq-scale "${rope_freq_scale}")
	fi

	# Add template descriptor if provided
	template_descriptor="${LLAMA_TEMPLATE:-}"
	if [[ -n "${template_descriptor}" ]]; then
		llama_args+=(--template "${template_descriptor}")
	fi

	# Add grammar file if provided
	if [[ -n "${LLAMA_GRAMMAR:-}" ]]; then
		llama_args+=(--grammar "${LLAMA_GRAMMAR}")
	fi

	# Append additional llama.cpp arguments when provided
	if [[ -n "${LLAMA_EXTRA_ARGS:-}" ]]; then
		local extra_args
		# shellcheck disable=SC2206 # intended splitting into an array
		extra_args=(${LLAMA_EXTRA_ARGS})
		llama_args+=("${extra_args[@]}")
	fi

	# Prepare prompt context details for logging
	prompt_context_detail=$(jq -nc \
		--arg stop_string "${stop_string}" \
		--argjson schema_provided "$(if [[ -n "${schema_json}" ]]; then printf 'true'; else printf 'false'; fi)" \
		--argjson prompt_tokens "${prompt_tokens}" \
		--argjson target_context "${target_context}" \
		'{stop_string:$stop_string, schema_provided:$schema_provided, prompt_tokens:$prompt_tokens, target_context:$target_context}')
	log "INFO" "llama prompt inputs" "${prompt_context_detail}"

	# Add prompt at the end
	llama_args+=(-p "${prompt}")

	# Construct argument string for logging
	llama_arg_string=$(printf '%s ' "${llama_args[@]:1}")
	llama_arg_string=${llama_arg_string% }

	# Create temporary file for stderr capture
	stderr_file="$(mktemp)"

	# Measure start time
	start_time_ns=$(date +%s)
	start_time_ns=$((start_time_ns * 1000000000))

	# Log debug info
	if [[ "${VERBOSITY:-0}" -ge 2 ]]; then
		log "DEBUG" "llama args" "${llama_arg_string}"
	fi

	# Run llama.cpp with timeout
	llama_output=$(llama_with_timeout "${llama_args[@]}" 2>"${stderr_file}")
	exit_code=$?

	# Measure elapsed time
	end_time_ns=$(date +%s)
	end_time_ns=$((end_time_ns * 1000000000))
	elapsed_ms=$(((end_time_ns - start_time_ns) / 1000000))

	# Handle timeouts
	if [[ ${exit_code} -eq 124 || ${exit_code} -eq 137 || ${exit_code} -eq 143 ]]; then
		llama_stderr="$(<"${stderr_file}")"
		log "ERROR" "llama inference timed out" "bin=${LLAMA_BIN} args=${llama_arg_string} timeout_seconds=${LLAMA_TIMEOUT_SECONDS:-0} elapsed_ms=${elapsed_ms} stderr=${llama_stderr} prompt_context=${prompt_context_detail}"
		rm -f "${stderr_file}"
		return "${exit_code}"
	fi

	# Handle llama.cpp errors
	if [[ ${exit_code} -ne 0 ]]; then
		llama_stderr="$(<"${stderr_file}")"
		log "ERROR" "llama inference failed" "bin=${LLAMA_BIN} args=${llama_arg_string} elapsed_ms=${elapsed_ms} stderr=${llama_stderr} prompt_context=${prompt_context_detail}"
		rm -f "${stderr_file}"
		return "${exit_code}"
	fi

	# Sanitize and return output
	llama_output="$(sanitize_llama_output "${llama_output}")"
	printf '%s' "${llama_output}"

	# Clean up
	rm -f "${stderr_file}"
}
