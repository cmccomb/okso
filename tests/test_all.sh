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
	TEST_ROOT="${BATS_TMPDIR}/okso-all"
	export HOME="${TEST_ROOT}/home"
	export CONFIG_FILE="${TEST_ROOT}/config.env"
	export LLAMA_BIN="${BATS_TEST_DIRNAME}/fixtures/mock_llama_relevance.sh"
	mkdir -p "${HOME}"

	cat >"${CONFIG_FILE}" <<EOF
MODEL_SPEC="example/repo:demo.gguf"
MODEL_BRANCH="main"
VERBOSITY=1
APPROVE_ALL=true
FORCE_CONFIRM=false
EOF
}

load helpers/log_parsing

@test "shows CLI help" {
	run ./src/main.sh --help -- "example query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: ./src/main.sh"* ]]
}

@test "prints version" {
	run ./src/main.sh --version -- "query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"okso assistant"* ]]
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
	missing_detail="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="llama.cpp binary not found")) | .[0].detail) catch ""')"
	execution_detail="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Execution summary")) | .[0].detail) catch ""')"
	[ "${missing_detail}" = "/definitely/missing" ]
	[[ "${execution_detail}" == *"LLM unavailable. Request received: search files"* ]]
}
