#!/usr/bin/env bats

setup() {
	TEST_ROOT="${BATS_TMPDIR}/do-main"
	export HOME="${TEST_ROOT}/home"
	export CONFIG_FILE="${TEST_ROOT}/config.env"
	MODEL_CACHE="${TEST_ROOT}/models"

	mkdir -p "${MODEL_CACHE}" "${HOME}"
	printf "stub-model-body" >"${MODEL_CACHE}/demo.gguf"

	cat >"${CONFIG_FILE}" <<EOF
MODEL_SPEC="example/repo:demo.gguf"
MODEL_BRANCH="main"
MODEL_CACHE="${MODEL_CACHE}"
VERBOSITY=0
APPROVE_ALL=false
FORCE_CONFIRM=false
EOF
}

@test "shows help text" {
	run ./src/main.sh --help -- "example query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: ./src/main.sh"* ]]
	[[ "$output" != *"DO_MODEL"* ]]
}

@test "prints version" {
	run ./src/main.sh --version -- "query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"do assistant"* ]]
}

@test "prompts before executing when approval is required" {
	run bash -lc "printf 'n\\n' | ./src/main.sh --config '${CONFIG_FILE}' -- 'list files'"
	[ "$status" -eq 0 ]
	[[ "$output" == *'Execute tool "os_nav"? [y/N]:'* ]]
	[[ "$output" == *"[os_nav skipped]"* ]]
}

@test "--yes bypasses prompts" {
	run ./src/main.sh --config "${CONFIG_FILE}" --yes -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Suggested tools"* ]]
	[[ "$output" == *"notes executed"* ]]
}

@test "--dry-run prints plan without execution" {
	run ./src/main.sh --config "${CONFIG_FILE}" --dry-run --yes -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Dry run: planned tool calls"* ]]
	[[ "$output" != *"notes executed"* ]]
}

@test "--plan-only emits JSON plan" {
	run ./src/main.sh --config "${CONFIG_FILE}" --plan-only -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"[{\"tool\""* ]]
	[[ "$output" == *"notes"* ]]
}

@test "init writes configuration" {
	local new_config
	new_config="${BATS_TMPDIR}/fresh-config.env"
	run ./src/main.sh init --config "${new_config}" --model "example/repo:demo.gguf" --model-branch dev --model-cache "${MODEL_CACHE}"
	[ "$status" -eq 0 ]
	[ -f "${new_config}" ]
	grep -q "MODEL_BRANCH=\"dev\"" "${new_config}"
}
