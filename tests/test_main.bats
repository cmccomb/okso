#!/usr/bin/env bats

setup() {
	TEST_ROOT="${BATS_TMPDIR}/okso-main"
	export HOME="${TEST_ROOT}/home"
	export CONFIG_FILE="${TEST_ROOT}/config.env"
	mkdir -p "${HOME}"

	cat >"${CONFIG_FILE}" <<EOF
MODEL_SPEC="example/repo:demo.gguf"
MODEL_BRANCH="main"
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
	[[ "$output" == *"okso assistant"* ]]
}

@test "prompts before executing when approval is required" {
	run bash -lc "printf 'n\\n' | ./src/main.sh --config '${CONFIG_FILE}' -- 'list files'"
	[ "$status" -eq 0 ]
	[[ "$output" == *'Execute tool "terminal"? [y/N]:'* ]]
	[[ "$output" == *"[terminal skipped]"* ]]
}

@test "--yes bypasses prompts" {
	run ./src/main.sh --config "${CONFIG_FILE}" --yes -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Suggested tools"* ]]
	[[ "$output" == *"notes_create executed"* ]]
}

@test "--dry-run prints plan without execution" {
	run ./src/main.sh --config "${CONFIG_FILE}" --dry-run --yes -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Dry run: planned tool calls"* ]]
	[[ "$output" != *"notes_create executed"* ]]
}

@test "--plan-only emits JSON plan" {
	run ./src/main.sh --config "${CONFIG_FILE}" --plan-only -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"[{\"tool\""* ]]
	[[ "$output" == *"notes_create"* ]]
}

@test "init writes configuration" {
	local new_config
	new_config="${BATS_TMPDIR}/fresh-config.env"
	run ./src/main.sh init --config "${new_config}" --model "example/repo:demo.gguf" --model-branch dev
	[ "$status" -eq 0 ]
	[ -f "${new_config}" ]
	grep -q "MODEL_BRANCH=\"dev\"" "${new_config}"
}

@test "resolves sources when executed via symlink" {
	local prefix link_path
	prefix="${BATS_TMPDIR}/symlink-prefix"
	link_path="${BATS_TMPDIR}/okso"

	mkdir -p "${prefix}"
	cp -R src "${prefix}"
	ln -sf "${prefix}/src/main.sh" "${link_path}"

	run "${link_path}" --config "${CONFIG_FILE}" --yes -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"notes_create executed"* ]]
}
