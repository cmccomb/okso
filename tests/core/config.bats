#!/usr/bin/env bats

setup() {
	#shellcheck disable=SC2155
	export REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "parse_model_spec fills in default file when none provided" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/config.sh
mapfile -t parts < <(parse_model_spec "demo/model" "fallback.gguf")
printf "%s\n" "${parts[@]}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "demo/model" ]
	[ "${lines[1]}" = "fallback.gguf" ]
}

@test "normalize_approval_flags coerces unexpected input to prompts" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/config.sh
VERBOSITY=0
APPROVE_ALL="notabool"
FORCE_CONFIRM="maybe"
normalize_approval_flags
printf "%s\n%s\n" "${APPROVE_ALL}" "${FORCE_CONFIRM}"
SCRIPT

	[ "$status" -eq 0 ]
	readarray -t approval_lines <<<"$(printf '%s\n' "${output}" | tail -n 2)"
	[ "${approval_lines[0]}" = "false" ]
	[ "${approval_lines[1]}" = "false" ]
}

@test "init_environment disables llama when testing passthrough is set" {
	run bash <<'SCRIPT'
set -euo pipefail
export TESTING_PASSTHROUGH=true
MODEL_SPEC="demo/repo:demo.gguf"
DEFAULT_MODEL_FILE="demo.gguf"
APPROVE_ALL=false
FORCE_CONFIRM=false
NOTES_DIR="$(mktemp -d)"
source ./src/lib/config.sh
init_environment
printf "%s\n" "${LLAMA_AVAILABLE}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "false" ]
}
