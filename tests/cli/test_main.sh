#!/usr/bin/env bats

setup() {
	TEST_ROOT="${BATS_TMPDIR}/okso-main"
	export HOME="${TEST_ROOT}/home"
	export CONFIG_FILE="${TEST_ROOT}/config.env"
	export LLAMA_BIN="${BATS_TEST_DIRNAME}/../fixtures/mock_llama_relevance.sh"
	mkdir -p "${HOME}"

	cat >"${CONFIG_FILE}" <<EOF
MODEL_SPEC="example/repo:demo.gguf"
MODEL_BRANCH="main"
VERBOSITY=1
APPROVE_ALL=false
FORCE_CONFIRM=false
EOF
}
load ../helpers/log_parsing.sh

@test "allows macOS baseline bash version" {
        run env OKSO_BASH_VERSION_OVERRIDE=3.2 ./src/bin/okso --help -- "example query"

        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage: ./src/bin/okso"* ]]
        [[ "$output" != *"requires bash"* ]]
}

@test "fails fast with descriptive message on too-old bash" {
        run env OKSO_BASH_VERSION_OVERRIDE=3.1 ./src/bin/okso --help -- "example query"

        [ "$status" -ne 0 ]
        [[ "$output" == *"bash 3.2"* ]]
        [[ "$output" == *"detected 3.1"* ]]
}

@test "shows help text" {
        run ./src/bin/okso --help -- "example query"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage: ./src/bin/okso"* ]]
        [[ "$output" != *"DO_MODEL"* ]]
}

@test "includes default model spec in help" {
	local default_spec
	default_spec="$(bash -c 'source ./src/lib/config.sh; printf "%s" "${DEFAULT_MODEL_SPEC_BASE}"')"

	run ./src/bin/okso --help -- "example query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"${default_spec}"* ]]
}

@test "prints version" {
	run ./src/bin/okso --version -- "query"
	[ "$status" -eq 0 ]
	[[ "$output" == *"okso assistant"* ]]
}

@test "prompts before executing when approval is required" {
	run bash -lc "printf 'n\\n' | ./src/bin/okso --config '${CONFIG_FILE}' -- 'list files'"
	[ "$status" -eq 0 ]
	[[ "$output" == *'Execute tool "terminal"? [y/N]:'* ]]

	final_answer="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Final answer")) | .[0].detail) catch ""')"
	[[ "${final_answer}" == *"Responding directly to: list files"* ]]
}

@test "--yes bypasses prompts" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --yes -- "note something"
	[ "$status" -eq 0 ]
	suggested_tools="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Suggested tools")) | .[0].detail) catch ""')"

	[[ "${suggested_tools}" == *"notes_create"* ]]
}

@test "--dry-run prints plan without execution" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --dry-run --yes -- "note something"
	[ "$status" -eq 0 ]
	dry_run_plan="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Dry run plan")) | .[0].detail) catch ""')"
	[[ "${dry_run_plan}" == *"notes_create"* ]]
	parse_json_logs <<<"${output}" | jq -e 'map(select(.message=="Planned query") | .detail | contains("something")) | any'
}

@test "--plan-only emits JSON plan" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --plan-only -- "note something"
	[ "$status" -eq 0 ]
	plan_json="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Plan JSON")) | .[0].detail) catch ""')"
	[[ "${plan_json}" == *"\"tool\""* ]]
	[[ "${plan_json}" == *"\"query\""* ]]
}

@test "casual prompts still finish with final_answer" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --yes -- "tell me a joke"
	[ "$status" -eq 0 ]
	suggested_tools="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Suggested tools")) | .[0].detail) catch ""')"
	[[ "${suggested_tools}" == *"final_answer"* ]]
}

@test "conversational phrasing suggests terminal tool" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --yes -- "could you take a quick look at the files in this folder?"
	[ "$status" -eq 0 ]
	suggested_tools="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Suggested tools")) | .[0].detail) catch ""')"
	[[ "${suggested_tools}" == *"terminal"* ]]
}

@test "reminder intent builds reminder plan" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --plan-only -- "remind me to submit grades tomorrow"
	[ "$status" -eq 0 ]
	plan_json="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Plan JSON")) | .[0].detail) catch ""')"
	[[ "${plan_json}" == *"reminders_create"* ]]
	[[ "${plan_json}" == *"submit grades tomorrow"* ]]
}

@test "terminal plan uses targeted query" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --plan-only -- "list files"
	[ "$status" -eq 0 ]
	plan_json="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Plan JSON")) | .[0].detail) catch ""')"
	[[ "${plan_json}" == *"ls -la"* ]]
}

@test "todo search plans grep step" {
	run ./src/bin/okso --config "${CONFIG_FILE}" --dry-run --yes -- "find TODOs in this repo and summarize"
	[ "$status" -eq 0 ]
	parse_json_logs <<<"${output}" | jq -e 'map(select(.message=="Planned query") | .detail | contains("rg -n \"TODO\" .")) | any'
}

@test "init writes configuration" {
	local new_config
	new_config="${BATS_TMPDIR}/fresh-config.env"
	run ./src/bin/okso init --config "${new_config}" --model "example/repo:demo.gguf" --model-branch dev
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
	ln -sf "${prefix}/src/bin/okso" "${link_path}"

	run "${link_path}" --config "${CONFIG_FILE}" --yes -- "note something"
	[ "$status" -eq 0 ]
	suggested_tools="$(parse_json_logs <<<"${output}" | jq -r 'try (map(select(.message=="Suggested tools")) | .[0].detail) catch ""')"
	[[ "${suggested_tools}" == *"notes_create"* ]]
}
