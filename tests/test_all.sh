#!/usr/bin/env bats
#
# Usage: bats tests/test_all.sh
#
# Environment variables:
#   LLAMA_BIN (string): path to llama.cpp binary or stub.
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes explicitly.

setup() {
	TEST_ROOT="${BATS_TMPDIR}/do-all"
	export HOME="${TEST_ROOT}/home"
	export CONFIG_FILE="${TEST_ROOT}/config.env"
	MODEL_CACHE="${TEST_ROOT}/models"

	mkdir -p "${MODEL_CACHE}" "${HOME}"
	printf "stub-model-body" >"${MODEL_CACHE}/demo.gguf"

	cat >"${CONFIG_FILE}" <<EOF
MODEL_SPEC="example/repo:demo.gguf"
MODEL_BRANCH="main"
MODEL_CACHE="${MODEL_CACHE}"
VERBOSITY=1
APPROVE_ALL=true
FORCE_CONFIRM=false
EOF
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
	run bash -lc "printf 'n\\n' | ./src/main.sh --config '${CONFIG_FILE}' --confirm -- 'list files'"
	[ "$status" -eq 0 ]
	[[ "$output" == *'Execute tool "terminal"? [y/N]:'* ]]
	[[ "$output" == *"[terminal skipped]"* ]]
}

@test "warns when llama.cpp dependency is missing but continues" {
	run env LLAMA_BIN=/definitely/missing ./src/main.sh --config "${CONFIG_FILE}" --yes -- "search files"
	[ "$status" -eq 0 ]
	[[ "$output" == *"binary not found"* ]]
	[[ "$output" == *"Execution summary"* ]]
}
