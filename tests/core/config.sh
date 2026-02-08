#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for config.sh.

setup() {
	# shellcheck disable=SC2155 # TD-003: test setup keeps declaration-plus-assignment for concise fixtures.
	export REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "parse_model_spec fills in default file when none provided" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/settings/config.sh
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
source ./src/lib/settings/config.sh
VERBOSITY=0
APPROVE_ALL="notabool"
normalize_approval_flags 2>/dev/null
printf "%s\n" "${APPROVE_ALL}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "false" ]
}

@test "init_environment disables llama when testing passthrough is set" {
	run bash <<'SCRIPT'
set -euo pipefail
export TESTING_PASSTHROUGH=true
export OKSO_NOTES_DIR="$(mktemp -d)"
export OKSO_CACHE_DIR="$(mktemp -d)"
source ./src/lib/settings/config.sh
load_config
init_environment
printf "%s\n" "${LLAMA_AVAILABLE}"
rm -rf "${OKSO_NOTES_DIR}"
rm -rf "${OKSO_CACHE_DIR}"
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
source ./src/lib/settings/config.sh
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
source ./src/lib/settings/config.sh
load_config
printf "%s\n%s\n" "${GOOGLE_SEARCH_API_KEY}" "${GOOGLE_SEARCH_CX}"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "env-key" ]
	[ "${lines[1]}" = "env-id" ]
}

@test "load_config preserves environment overrides for model and approval settings" {
	run bash <<'SCRIPT'
set -euo pipefail
config_file="$(mktemp)"
cat >"${config_file}" <<'EOF'
PLANNER_MODEL_SPEC="config/planner:plan.gguf"
PLANNER_MODEL_BRANCH="config-plan"
EXECUTOR_MODEL_SPEC="config/executor:exec.gguf"
EXECUTOR_MODEL_BRANCH="config-exec"
VERBOSITY=0
APPROVE_ALL=false
EOF
export PLANNER_MODEL_SPEC="env/planner:plan.gguf"
export PLANNER_MODEL_BRANCH="env-plan"
export EXECUTOR_MODEL_SPEC="env/executor:exec.gguf"
export EXECUTOR_MODEL_BRANCH="env-exec"
export VERBOSITY=2
export APPROVE_ALL=true
CONFIG_FILE="${config_file}"
source ./src/lib/settings/config.sh 2>/dev/null
load_config 2>/dev/null
printf "%s\n" \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${EXECUTOR_MODEL_SPEC}" "${EXECUTOR_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "env/planner:plan.gguf" ]
	[ "${lines[1]}" = "env-plan" ]
	[ "${lines[2]}" = "env/executor:exec.gguf" ]
	[ "${lines[3]}" = "env-exec" ]
	[ "${lines[4]}" = "2" ]
	[ "${lines[5]}" = "true" ]
}

@test "write_config_file emits shell-parsable assignments" {
	run bash <<'SCRIPT'
set -euo pipefail
config_file="$(mktemp)"
PLANNER_MODEL_SPEC="planner/model:planner.gguf"
PLANNER_MODEL_BRANCH="planner-branch"
EXECUTOR_MODEL_SPEC="executor/model:executor.gguf"
EXECUTOR_MODEL_BRANCH="executor-branch"
VALIDATOR_MODEL_SPEC="validator/model:validator.gguf"
VALIDATOR_MODEL_BRANCH="validator-branch"
SEARCH_REPHRASER_MODEL_SPEC="search/model:search.gguf"
SEARCH_REPHRASER_MODEL_BRANCH="search-branch"
CACHE_DIR="$(mktemp -d)"
VERBOSITY=2
APPROVE_ALL=true
CONFIG_FILE="${config_file}"
source ./src/lib/settings/config.sh 2>/dev/null
load_config 2>/dev/null
write_config_file >/dev/null
bash -n "${config_file}"
PLANNER_MODEL_SPEC="placeholder"
PLANNER_MODEL_BRANCH="placeholder"
EXECUTOR_MODEL_SPEC="placeholder"
EXECUTOR_MODEL_BRANCH="placeholder"
VALIDATOR_MODEL_SPEC="placeholder"
VALIDATOR_MODEL_BRANCH="placeholder"
SEARCH_REPHRASER_MODEL_SPEC="placeholder"
SEARCH_REPHRASER_MODEL_BRANCH="placeholder"
CACHE_DIR="placeholder"
VERBOSITY=0
APPROVE_ALL=false
source "${config_file}"
printf '%s\n' \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${EXECUTOR_MODEL_SPEC}" "${EXECUTOR_MODEL_BRANCH}" \
        "${VALIDATOR_MODEL_SPEC}" "${VALIDATOR_MODEL_BRANCH}" \
        "${SEARCH_REPHRASER_MODEL_SPEC}" "${SEARCH_REPHRASER_MODEL_BRANCH}" \
        "${CACHE_DIR}" \
        "${VERBOSITY}" "${APPROVE_ALL}" \
        "$(wc -l < "${config_file}" | tr -d ' ')"
rm -rf "${CACHE_DIR}"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "planner/model:planner.gguf" ]
	[ "${lines[1]}" = "planner-branch" ]
	[ "${lines[2]}" = "executor/model:executor.gguf" ]
	[ "${lines[3]}" = "executor-branch" ]
	[ "${lines[4]}" = "validator/model:validator.gguf" ]
	[ "${lines[5]}" = "validator-branch" ]
	[ "${lines[6]}" = "search/model:search.gguf" ]
	[ "${lines[7]}" = "search-branch" ]
	[[ "${lines[8]}" = /* ]]
	[ "${lines[9]}" = "2" ]
	[ "${lines[10]}" = "true" ]
	[ "${lines[11]}" = "11" ]
}

@test "okso init writes clean config without stray characters" {
	run bash <<'SCRIPT'
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
config_dir="$(mktemp -d)"
export XDG_CONFIG_HOME="${config_dir}"
config_file="${config_dir}/okso/config.env"
cd "${repo_root}"
./src/bin/okso init --yes >/dev/null 2>&1
bash -n "${config_file}"
unset PLANNER_MODEL_SPEC PLANNER_MODEL_BRANCH EXECUTOR_MODEL_SPEC EXECUTOR_MODEL_BRANCH VALIDATOR_MODEL_SPEC VALIDATOR_MODEL_BRANCH SEARCH_REPHRASER_MODEL_SPEC SEARCH_REPHRASER_MODEL_BRANCH VERBOSITY APPROVE_ALL
source "${config_file}"
printf '%s\n' \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${EXECUTOR_MODEL_SPEC}" "${EXECUTOR_MODEL_BRANCH}" \
        "${VALIDATOR_MODEL_SPEC}" "${VALIDATOR_MODEL_BRANCH}" \
        "${SEARCH_REPHRASER_MODEL_SPEC}" "${SEARCH_REPHRASER_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}" \
        "$(grep -E '^[A-Z_]+=.*' "${config_file}" | wc -l | tr -d ' ')" \
        "$(wc -l < "${config_file}" | tr -d ' ')"
rm -rf "${config_dir}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[8]}" = "0" ]
	[ "${lines[9]}" = "true" ]
	[ "${lines[10]}" = "11" ]
	[ "${lines[11]}" = "11" ]
}

@test "planner/executor/rephraser specs hydrate defaults and explicit overrides" {
	run bash <<'SCRIPT'
set -euo pipefail
CONFIG_FILE="$(mktemp)"
source ./src/lib/settings/config.sh
load_config
hydrate_model_specs
printf '%s\n' \
        "${PLANNER_MODEL_REPO}" "${PLANNER_MODEL_FILE}" \
        "${EXECUTOR_MODEL_REPO}" "${EXECUTOR_MODEL_FILE}" \
        "${SEARCH_REPHRASER_MODEL_REPO}" "${SEARCH_REPHRASER_MODEL_FILE}" \
        "${PLANNER_MODEL_SPEC}" "${EXECUTOR_MODEL_SPEC}" "${SEARCH_REPHRASER_MODEL_SPEC}"
PLANNER_MODEL_SPEC="planner/model:plan.gguf"
EXECUTOR_MODEL_SPEC="executor/model:exec.gguf"
SEARCH_REPHRASER_MODEL_SPEC="rephraser/model:search.gguf"
hydrate_model_specs
printf '%s\n' \
        "${PLANNER_MODEL_REPO}" "${PLANNER_MODEL_FILE}" \
        "${EXECUTOR_MODEL_REPO}" "${EXECUTOR_MODEL_FILE}" \
        "${SEARCH_REPHRASER_MODEL_REPO}" "${SEARCH_REPHRASER_MODEL_FILE}"
rm -f "${CONFIG_FILE}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ -n "${lines[0]}" ]]
	[[ -n "${lines[1]}" ]]
	[[ -n "${lines[2]}" ]]
	[[ -n "${lines[3]}" ]]
	[[ -n "${lines[4]}" ]]
	[[ -n "${lines[5]}" ]]
	[[ -n "${lines[6]}" ]]
	[ "${lines[9]}" = "planner/model" ]
	[ "${lines[10]}" = "plan.gguf" ]
	[ "${lines[11]}" = "executor/model" ]
	[ "${lines[12]}" = "exec.gguf" ]
	[ "${lines[13]}" = "rephraser/model" ]
	[ "${lines[14]}" = "search.gguf" ]
}

@test "log_model_autotune_summary uses debug level" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/settings/config.sh
log() { printf '%s\n' "$1"; }
MODEL_AUTOTUNE_BASE_TIER="default"
MODEL_AUTOTUNE_EFFECTIVE_TIER="default"
MODEL_AUTOTUNE_PRESSURE_LEVEL="normal"
MODEL_AUTOTUNE_HEADROOM_CLASS="comfortable"
DETECTED_PHYS_MEM_GB=16
DETECTED_IS_GHA=0
log_model_autotune_summary
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "DEBUG" ]
}

@test "cli --yes flag sets APPROVE_ALL" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/cli/cli.sh
COMMAND="run"
APPROVE_ALL=false
parse_args --yes -- "demo query"
printf '%s\n' "${APPROVE_ALL}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "true" ]
}

@test "cli -v flag sets verbosity to provided integer" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/cli/cli.sh
COMMAND="run"
VERBOSITY=0
parse_args -v 2 -- "demo query"
printf '%s\n' "${VERBOSITY}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "2" ]
}

@test "cli -q flag sets VERBOSITY to 0" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/cli/cli.sh
COMMAND="run"
VERBOSITY=1
parse_args -q -- "demo query"
printf '%s\n' "${VERBOSITY}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "0" ]
}

@test "verbosity maps to progress and trace flags" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/settings/runtime.sh
VERBOSITY=0
unset OKSO_PROGRESS OKSO_TRACE OKSO_TRACE_VERBOSE
configure_ui_flags
printf '%s,%s,%s\n' "${OKSO_PROGRESS}" "${OKSO_TRACE}" "${OKSO_TRACE_VERBOSE}"
VERBOSITY=1
unset OKSO_PROGRESS OKSO_TRACE OKSO_TRACE_VERBOSE
configure_ui_flags
printf '%s,%s,%s\n' "${OKSO_PROGRESS}" "${OKSO_TRACE}" "${OKSO_TRACE_VERBOSE}"
VERBOSITY=2
unset OKSO_PROGRESS OKSO_TRACE OKSO_TRACE_VERBOSE
configure_ui_flags
printf '%s,%s,%s\n' "${OKSO_PROGRESS}" "${OKSO_TRACE}" "${OKSO_TRACE_VERBOSE}"
VERBOSITY=3
unset OKSO_PROGRESS OKSO_TRACE OKSO_TRACE_VERBOSE
configure_ui_flags
printf '%s,%s,%s\n' "${OKSO_PROGRESS}" "${OKSO_TRACE}" "${OKSO_TRACE_VERBOSE}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "0,0,0" ]
	[ "${lines[1]}" = "1,0,0" ]
	[ "${lines[2]}" = "1,1,0" ]
	[ "${lines[3]}" = "1,1,1" ]
}
