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
normalize_approval_flags
printf "%s\n" "${APPROVE_ALL}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "false" ]
}

@test "init_environment disables llama when testing passthrough is set" {
	run bash <<'SCRIPT'
set -euo pipefail
export TESTING_PASSTHROUGH=true
CONFIG_FILE="$(mktemp)"
DEFAULT_MODEL_FILE="demo.gguf"
APPROVE_ALL=false
NOTES_DIR="$(mktemp -d)"
CONFIG_FILE=""
source ./src/lib/config.sh
load_config
init_environment
printf "%s\n" "${LLAMA_AVAILABLE}"
rm -f "${CONFIG_FILE}"
rm -rf "${NOTES_DIR}"
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

@test "load_config preserves environment overrides for model and approval settings" {
	run bash <<'SCRIPT'
set -euo pipefail
config_file="$(mktemp)"
cat >"${config_file}" <<'EOF'
PLANNER_MODEL_SPEC="config/planner:plan.gguf"
PLANNER_MODEL_BRANCH="config-plan"
REACT_MODEL_SPEC="config/react:react.gguf"
REACT_MODEL_BRANCH="config-react"
VERBOSITY=0
APPROVE_ALL=false
EOF
export PLANNER_MODEL_SPEC="env/planner:plan.gguf"
export PLANNER_MODEL_BRANCH="env-plan"
export REACT_MODEL_SPEC="env/react:react.gguf"
export REACT_MODEL_BRANCH="env-react"
export VERBOSITY=2
export APPROVE_ALL=true
CONFIG_FILE="${config_file}"
source ./src/lib/config.sh
load_config
printf "%s\n" \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${REACT_MODEL_SPEC}" "${REACT_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "env/planner:plan.gguf" ]
	[ "${lines[1]}" = "env-plan" ]
	[ "${lines[2]}" = "env/react:react.gguf" ]
	[ "${lines[3]}" = "env-react" ]
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
VERBOSITY=2
APPROVE_ALL=true
CONFIG_FILE="${config_file}"
source ./src/lib/config.sh
load_config
write_config_file >/dev/null
bash -n "${config_file}"
PLANNER_MODEL_SPEC="placeholder"
PLANNER_MODEL_BRANCH="placeholder"
EXECUTOR_MODEL_SPEC="placeholder"
EXECUTOR_MODEL_BRANCH="placeholder"
VERBOSITY=0
APPROVE_ALL=false
source "${config_file}"
printf '%s\n' \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${REACT_MODEL_SPEC}" "${REACT_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}" \
        "$(wc -l < "${config_file}" | tr -d ' ')"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "planner/model:planner.gguf" ]
	[ "${lines[1]}" = "planner-branch" ]
	[ "${lines[2]}" = "executor/model:executor.gguf" ]
	[ "${lines[3]}" = "executor-branch" ]
	[ "${lines[4]}" = "2" ]
	[ "${lines[5]}" = "true" ]
	[ "${lines[6]}" = "6" ]
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
unset PLANNER_MODEL_SPEC PLANNER_MODEL_BRANCH REACT_MODEL_SPEC REACT_MODEL_BRANCH VERBOSITY APPROVE_ALL
source "${config_file}"
printf '%s\n' \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${REACT_MODEL_SPEC}" "${REACT_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}" \
        "$(grep -E '^[A-Z_]+=.*' "${config_file}" | wc -l | tr -d ' ')" \
        "$(wc -l < "${config_file}" | tr -d ' ')"
rm -rf "${config_dir}"
SCRIPT

	[ "$status" -eq 0 ]
	# Check that the values match defaults (not custom)
	[ "${lines[4]}" = "1" ]
	[ "${lines[5]}" = "false" ]
	[ "${lines[6]}" = "6" ]
	[ "${lines[7]}" = "6" ]
}

@test "planner and react specs hydrate defaults and shared overrides" {
	run bash <<'SCRIPT'
set -euo pipefail
CONFIG_FILE="$(mktemp)"
NOTES_DIR="$(mktemp -d)"
export DEFAULT_MODEL_REPO_BASE="custom/react-repo"
export DEFAULT_MODEL_FILE_BASE="react-base.gguf"
export DEFAULT_MODEL_BRANCH_BASE="release"
export DEFAULT_PLANNER_MODEL_REPO_BASE="custom/planner-repo"
export DEFAULT_PLANNER_MODEL_FILE_BASE="planner-base.gguf"
export DEFAULT_PLANNER_MODEL_BRANCH_BASE="release"
export DEFAULT_REACT_MODEL_SPEC_BASE="${DEFAULT_MODEL_REPO_BASE}:${DEFAULT_MODEL_FILE_BASE}"
export DEFAULT_REACT_MODEL_BRANCH_BASE="${DEFAULT_MODEL_BRANCH_BASE}"
source ./src/lib/config.sh
load_config
hydrate_model_specs
printf '%s\n' \
        "${PLANNER_MODEL_REPO}" "${PLANNER_MODEL_FILE}" \
        "${REACT_MODEL_REPO}" "${REACT_MODEL_FILE}" \
        "${PLANNER_MODEL_SPEC}" "${REACT_MODEL_SPEC}"
MODEL_SPEC="override/repo:react.gguf"
MODEL_BRANCH="dev"
PLANNER_MODEL_SPEC=""
REACT_MODEL_SPEC=""
PLANNER_MODEL_BRANCH=""
REACT_MODEL_BRANCH=""
hydrate_model_specs
printf '%s\n' "${PLANNER_MODEL_SPEC}" "${REACT_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" "${REACT_MODEL_BRANCH}"
PLANNER_MODEL_SPEC="planner/model:plan.gguf"
REACT_MODEL_SPEC="react/model:react.gguf"
PLANNER_MODEL_BRANCH="stable"
REACT_MODEL_BRANCH="beta"
hydrate_model_specs
printf '%s\n' "${PLANNER_MODEL_SPEC}" "${REACT_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" "${REACT_MODEL_BRANCH}"
rm -f "${CONFIG_FILE}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "custom/planner-repo" ]
	[ "${lines[1]}" = "planner-base.gguf" ]
	[ "${lines[2]}" = "custom/react-repo" ]
	[ "${lines[3]}" = "react-base.gguf" ]
	[ "${lines[4]}" = "custom/planner-repo:planner-base.gguf" ]
	[ "${lines[5]}" = "custom/react-repo:react-base.gguf" ]
	[ "${lines[6]}" = "custom/planner-repo:planner-base.gguf" ]
	[ "${lines[7]}" = "custom/react-repo:react-base.gguf" ]
	[ "${lines[8]}" = "release" ]
	[ "${lines[9]}" = "release" ]
	[ "${lines[10]}" = "planner/model:plan.gguf" ]
	[ "${lines[11]}" = "react/model:react.gguf" ]
	[ "${lines[12]}" = "stable" ]
	[ "${lines[13]}" = "beta" ]
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
