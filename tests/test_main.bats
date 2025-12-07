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
	[[ "$output" == *"Responding directly to: list files"* ]]
}

@test "--yes bypasses prompts" {
	run ./src/main.sh --config "${CONFIG_FILE}" --yes -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Suggested tools"* ]]
	[[ "$output" == *"notes_create"* ]]
}

@test "--dry-run prints plan without execution" {
	run ./src/main.sh --config "${CONFIG_FILE}" --dry-run --yes -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Dry run: planned tool calls"* ]]
	[[ "$output" == *"notes_create"* ]]
}

@test "--plan-only emits JSON plan" {
	run ./src/main.sh --config "${CONFIG_FILE}" --plan-only -- "note something"
	[ "$status" -eq 0 ]
	[[ "$output" == *"[{\"tool\""* ]]
	[[ "$output" == *"\"query\""* ]]
}

@test "casual prompts skip tools" {
	run ./src/main.sh --config "${CONFIG_FILE}" --yes -- "tell me a joke"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Suggested tools: none."* ]]
	[[ "$output" != *"executed"* ]]
}

@test "conversational phrasing suggests terminal tool" {
	run ./src/main.sh --config "${CONFIG_FILE}" --yes -- "could you take a quick look at the files in this folder?"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Suggested tools"* ]]
	[[ "$output" == *"terminal"* ]]
}

@test "direct responses log fallback when no tools apply" {
	run ./src/main.sh --config "${CONFIG_FILE}" --yes -- "just chat with me"
	[ "$status" -eq 0 ]
	[[ "$output" == *"No tools selected; responding directly"* ]]
	[[ "$output" == *"Responding directly to: just chat with me"* ]]
}

@test "reminder intent builds reminder plan" {
	run ./src/main.sh --config "${CONFIG_FILE}" --plan-only -- "remind me to submit grades tomorrow"
	[ "$status" -eq 0 ]
	[[ "$output" == *"reminders_create"* ]]
	[[ "$output" == *"submit grades tomorrow"* ]]
}

@test "terminal plan uses targeted query" {
	run ./src/main.sh --config "${CONFIG_FILE}" --plan-only -- "list files"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ls -la"* ]]
}

@test "todo search plans grep step" {
	run ./src/main.sh --config "${CONFIG_FILE}" --dry-run --yes -- "find TODOs in this repo and summarize"
	[ "$status" -eq 0 ]
	[[ "$output" == *"rg -n \"TODO\" ."* ]]
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
	[[ "$output" == *"notes_create"* ]]
}
