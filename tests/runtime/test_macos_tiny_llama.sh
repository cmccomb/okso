#!/usr/bin/env bats
# macOS llama.cpp end-to-end smoke test.
#
# Usage:
#   bats tests/runtime/test_macos_tiny_llama.sh
#
# Environment variables:
#   MODEL_SPEC (string): Hugging Face repo[:file] identifier for the model.
#   MODEL_BRANCH (string): Branch or tag to fetch from the repo.
#   LLAMA_BIN (string): Path to the llama.cpp binary (default: llama-cli).
#   APPROVE_ALL (bool string): When true, skip interactive confirmations.
#   USE_REACT_LLAMA (bool string): When true, enable the React loop strategy.
#
# Dependencies:
#   - bats
#   - jq
#   - llama.cpp binary available on PATH
#
# Exit codes:
#   Follows Bats semantics; individual tests assert exit statuses explicitly.

load ../helpers/log_parsing.sh

setup() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
		skip "macOS-specific runtime smoke test"
	fi

	if ! command -v "${LLAMA_BIN:-llama-cli}" >/dev/null 2>&1; then
		skip "llama.cpp binary not available on PATH"
	fi

	export TEST_ROOT="${BATS_TMPDIR}/okso-macos-e2e"
	export HOME="${TEST_ROOT}/home"
	mkdir -p "${HOME}"
}

@test "tiny llama model drives planner and react loop" {
	export MODEL_SPEC="${MODEL_SPEC:-TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF:tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf}"
	export MODEL_BRANCH="${MODEL_BRANCH:-main}"
	export LLAMA_BIN="${LLAMA_BIN:-llama-cli}"
	export APPROVE_ALL="${APPROVE_ALL:-true}"
	export USE_REACT_LLAMA="${USE_REACT_LLAMA:-true}"
	export VERBOSITY="${VERBOSITY:-1}"

	run ./src/bin/okso --yes --model "${MODEL_SPEC}" --model-branch "${MODEL_BRANCH}" -- "what is 2 plus 2?"

	[ "$status" -eq 0 ]

	planner_tools="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Planner identified tools"))[0].detail) catch ""')"
	final_answer="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Final answer"))[0].detail) catch ""')"
	tool_executions="$(parse_json_logs <<<"${output}" | jq -r 'map(select(.message=="Recorded tool execution")) | length')"

	echo "${output}"

	[[ -n "${planner_tools}" ]]
	[[ -n "${final_answer}" ]]
	[ "${tool_executions}" -ge 1 ]
}
