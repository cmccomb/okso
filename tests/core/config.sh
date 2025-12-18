#!/usr/bin/env bats

setup() {
	#shellcheck disable=SC2155
	export REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "parse_model_spec fills in default file when none provided" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/config.sh
parts=()
while IFS= read -r line; do
	parts+=("$line")
done < <(parse_model_spec "demo/model" "fallback.gguf")
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
	approval_lines=()
	while IFS= read -r line; do
		approval_lines+=("$line")
	done <<<"$(printf '%s\n' "${output}" | tail -n 2)"
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

@test "load_config uses config file Google CSE values" {
	run bash <<'SCRIPT'
set -euo pipefail
config_file="$(mktemp)"
cat >"${config_file}" <<'EOF'
OKSO_GOOGLE_CSE_API_KEY="config-key"
OKSO_GOOGLE_CSE_ID="config-id"
EOF
CONFIG_FILE="${config_file}"
source ./src/lib/config.sh
load_config
printf "%s\n%s\n" "${GOOGLE_SEARCH_API_KEY}" "${GOOGLE_SEARCH_CX}"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "config-key" ]
	[ "${lines[1]}" = "config-id" ]
}

@test "load_config prefers environment Google CSE overrides" {
	run bash <<'SCRIPT'
set -euo pipefail
config_file="$(mktemp)"
cat >"${config_file}" <<'EOF'
OKSO_GOOGLE_CSE_API_KEY="config-key"
OKSO_GOOGLE_CSE_ID="config-id"
EOF
export OKSO_GOOGLE_CSE_API_KEY="env-key"
export OKSO_GOOGLE_CSE_ID="env-id"
CONFIG_FILE="${config_file}"
source ./src/lib/config.sh
load_config
printf "%s\n%s\n" "${GOOGLE_SEARCH_API_KEY}" "${GOOGLE_SEARCH_CX}"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "env-key" ]
	[ "${lines[1]}" = "env-id" ]
}
