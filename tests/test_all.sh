#!/usr/bin/env bats
#
# Usage: bats tests/test_all.sh
#
# Environment variables:
#   DO_VERBOSITY (int): 0=quiet, 1=info, 2=debug log output.
#   DO_SUPERVISED (bool): true to require confirmations before running tools.
#   LLAMA_BIN (string): path to llama.cpp binary or stub.
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes explicitly.

setup() {
	export DO_VERBOSITY=0
	export DO_SUPERVISED=false
	export DO_MODEL="example/repo:demo.gguf"
	export DO_MODEL_CACHE="${BATS_TMPDIR}/do-models"
	mkdir -p "${DO_MODEL_CACHE}"
	printf "stub-model-body" >"${DO_MODEL_CACHE}/demo.gguf"
}

@test "shows CLI help" {
	run ./src/main.sh --help -- "example query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: ./src/main.sh"* ]]
}

@test "prints version" {
	run ./src/main.sh --version -- "query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"do assistant"* ]]
}

@test "prompts in supervised mode and respects decline" {
	run env DO_SUPERVISED=true DO_VERBOSITY=1 bash -c 'printf "n\n" | ./src/main.sh --supervised -- "list files"'
	[ "$status" -eq 0 ]
	[[ "$output" == *'Execute tool "os_nav"? [y/N]:'* ]]
	[[ "$output" == *"[os_nav skipped]"* ]]
}

@test "uses mock llama.cpp scoring to rank notes highest" {
	local llama_log
	llama_log="$(mktemp)"
	run env DO_SUPERVISED=false \
		DO_VERBOSITY=0 \
		LLAMA_BIN="$(pwd)/tests/fixtures/mock_llama.sh" \
		MOCK_LLAMA_LOG="${llama_log}" \
		DO_MODEL_PATH="$(pwd)/tests/fixtures/mock-model.gguf" \
		DO_MODEL="example/repo:demo.gguf" \
		DO_MODEL_CACHE="${DO_MODEL_CACHE}" \
		./src/main.sh -- "save reminder"
	[ "$status" -eq 0 ]
	[[ "$output" == *"notes(score=5"* ]]
	[[ "$output" == *"[notes executed]"* ]]
	grep -q "Available tools:" "${llama_log}"
	[[ "$(grep -c "Available tools:" "${llama_log}")" -eq 1 ]]
}

@test "warns when llama.cpp dependency is missing but continues" {
	run env LLAMA_BIN=/definitely/missing DO_VERBOSITY=1 ./src/main.sh --unsupervised -- "search files"
	[ "$status" -eq 0 ]
	[[ "$output" == *"binary not found"* ]]
	[[ "$output" == *"Execution summary"* ]]
}
