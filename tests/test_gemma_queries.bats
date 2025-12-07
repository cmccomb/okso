#!/usr/bin/env bats
# shellcheck shell=bash
#
# Integration tests that exercise real inference against the
# google_gemma-3-1b-it-Q4_K_M.gguf model from the
# bartowski/google_gemma-3-1b-it-GGUF repository.
#
# These tests require a working llama.cpp binary (LLAMA_BIN or llama-cli on
# PATH) and internet access to download the model on first run. Subsequent
# executions reuse the cached file in BATS_TMPDIR.
#
# Usage: bats tests/test_gemma_queries.bats
#
# Environment variables:
#   LLAMA_BIN (string): path to llama.cpp binary. If unset, the tests attempt to
#                       find llama-cli on PATH.
#   GEMMA_MODEL_PATH (string): optional path to a pre-downloaded model file.
#
# Dependencies:
#   - bats
#   - bash 5+
#   - curl
#   - llama.cpp binary with GGUF support
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

setup_file() {
	TEST_ROOT="${BATS_TMPDIR}/gemma-integration"
	MODEL_DIR="${TEST_ROOT}/models"
	export GEMMA_MODEL_PATH="${GEMMA_MODEL_PATH:-${MODEL_DIR}/google_gemma-3-1b-it-Q4_K_M.gguf}"
	mkdir -p "${MODEL_DIR}"
}

load_or_skip_llama() {
	if [[ -n "${LLAMA_BIN:-}" ]]; then
		return 0
	fi

	if command -v llama-cli >/dev/null 2>&1; then
		local discovered
		discovered="$(command -v llama-cli)"
		export LLAMA_BIN="${discovered}"
		return 0
	fi

	skip "llama.cpp binary is required to run Gemma integration tests"
}

download_model_if_missing() {
	if [[ -f "${GEMMA_MODEL_PATH}" ]]; then
		return 0
	fi

	local model_url
	model_url="https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/resolve/main/google_gemma-3-1b-it-Q4_K_M.gguf?download=1"

	if ! curl -L --fail --output "${GEMMA_MODEL_PATH}" "${model_url}"; then
		skip "Unable to download Gemma model from Hugging Face"
	fi
}

run_gemma() {
	local prompt token_limit
	prompt="$1"
	token_limit="$2"

	"${LLAMA_BIN}" \
		-m "${GEMMA_MODEL_PATH}" \
		--seed 42 \
		--temp 0 \
		--no-display-prompt \
		--simple-io \
		-n "${token_limit}" \
		-p "${prompt}" 2>/dev/null
}

@test "gemma returns the requested keyword" {
	load_or_skip_llama
	download_model_if_missing

	run run_gemma "Respond only with the word okso." 8
	[ "$status" -eq 0 ]
	[[ "$output" == *"okso"* ]]
}

@test "gemma answers a simple arithmetic prompt" {
	load_or_skip_llama
	download_model_if_missing

	run run_gemma "What is two plus two? Respond with just the numeral." 8
	[ "$status" -eq 0 ]
	[[ "$output" == *"4"* ]]
}

@test "gemma follows an instruction to provide a brief list" {
	load_or_skip_llama
	download_model_if_missing

	run run_gemma "List two colors separated by commas." 16
	[ "$status" -eq 0 ]
	[[ "$output" == *","* ]]
}
