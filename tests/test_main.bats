#!/usr/bin/env bats

setup() {
        export DO_VERBOSITY=0
        export DO_SUPERVISED=false
        export DO_MODEL="example/repo:demo.gguf"
        export DO_MODEL_CACHE="${BATS_TMPDIR}/do-models"
        mkdir -p "${DO_MODEL_CACHE}"
        printf "stub-model-body" >"${DO_MODEL_CACHE}/demo.gguf"
}

@test "shows help text" {
	run ./src/main.sh --help -- "example query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: ./src/main.sh"* ]]
}

@test "prints version" {
	run ./src/main.sh --version -- "query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"do assistant"* ]]
}

@test "runs planner in unsupervised mode" {
	run ./src/main.sh --unsupervised -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Suggested tools"* ]]
	[[ "$output" == *"notes executed"* ]]
}
