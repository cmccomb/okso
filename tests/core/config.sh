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
FORCE_CONFIRM=true
EOF
export PLANNER_MODEL_SPEC="env/planner:plan.gguf"
export PLANNER_MODEL_BRANCH="env-plan"
export REACT_MODEL_SPEC="env/react:react.gguf"
export REACT_MODEL_BRANCH="env-react"
export VERBOSITY=2
export APPROVE_ALL=true
export FORCE_CONFIRM=false
CONFIG_FILE="${config_file}"
source ./src/lib/config.sh
load_config
printf "%s\n" \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${REACT_MODEL_SPEC}" "${REACT_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}" "${FORCE_CONFIRM}"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "env/planner:plan.gguf" ]
	[ "${lines[1]}" = "env-plan" ]
	[ "${lines[2]}" = "env/react:react.gguf" ]
	[ "${lines[3]}" = "env-react" ]
	[ "${lines[4]}" = "2" ]
	[ "${lines[5]}" = "true" ]
	[ "${lines[6]}" = "false" ]
}

@test "write_config_file emits shell-parsable assignments" {
	run bash <<'SCRIPT'
set -euo pipefail
config_file="$(mktemp)"
PLANNER_MODEL_SPEC="planner/model:planner.gguf"
PLANNER_MODEL_BRANCH="planner-branch"
REACT_MODEL_SPEC="react/model:react.gguf"
REACT_MODEL_BRANCH="react-branch"
VERBOSITY=2
APPROVE_ALL=true
FORCE_CONFIRM=false
CONFIG_FILE="${config_file}"
source ./src/lib/config.sh
write_config_file >/dev/null
bash -n "${config_file}"
PLANNER_MODEL_SPEC="placeholder"
PLANNER_MODEL_BRANCH="placeholder"
REACT_MODEL_SPEC="placeholder"
REACT_MODEL_BRANCH="placeholder"
VERBOSITY=0
APPROVE_ALL=false
FORCE_CONFIRM=true
source "${config_file}"
printf '%s\n' \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${REACT_MODEL_SPEC}" "${REACT_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}" "${FORCE_CONFIRM}" \
        "$(wc -l < "${config_file}" | tr -d ' ')"
rm -f "${config_file}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "planner/model:planner.gguf" ]
	[ "${lines[1]}" = "planner-branch" ]
	[ "${lines[2]}" = "react/model:react.gguf" ]
	[ "${lines[3]}" = "react-branch" ]
	[ "${lines[4]}" = "2" ]
	[ "${lines[5]}" = "true" ]
	[ "${lines[6]}" = "false" ]
	[ "${lines[7]}" = "7" ]
}

@test "okso init writes clean config without stray characters" {
	run bash <<'SCRIPT'
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
config_dir="$(mktemp -d)"
config_file="${config_dir}/config.env"
model_spec="custom/model:quant demo.gguf"
model_branch="stable/2024-08"
cd "${repo_root}"
./src/bin/okso init --config "${config_file}" --model "${model_spec}" --model-branch "${model_branch}" --yes >/dev/null
bash -n "${config_file}"
unset PLANNER_MODEL_SPEC PLANNER_MODEL_BRANCH REACT_MODEL_SPEC REACT_MODEL_BRANCH VERBOSITY APPROVE_ALL FORCE_CONFIRM
source "${config_file}"
printf '%s\n' \
        "${PLANNER_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" \
        "${REACT_MODEL_SPEC}" "${REACT_MODEL_BRANCH}" \
        "${VERBOSITY}" "${APPROVE_ALL}" "${FORCE_CONFIRM}" \
        "$(grep -E '^[A-Z_]+=.*' "${config_file}" | wc -l | tr -d ' ')" \
        "$(wc -l < "${config_file}" | tr -d ' ')"
rm -rf "${config_dir}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "custom/model:quant demo.gguf" ]
	[ "${lines[1]}" = "stable/2024-08" ]
	[ "${lines[2]}" = "custom/model:quant demo.gguf" ]
	[ "${lines[3]}" = "stable/2024-08" ]
	[ "${lines[4]}" = "1" ]
	[ "${lines[5]}" = "true" ]
	[ "${lines[6]}" = "false" ]
	[ "${lines[7]}" = "7" ]
	[ "${lines[8]}" = "7" ]
}

@test "planner and react specs hydrate defaults and shared overrides" {
	run bash <<'SCRIPT'
set -euo pipefail
CONFIG_FILE="$(mktemp)"
NOTES_DIR="$(mktemp -d)"
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
	[ "${lines[0]}" = "bartowski/Qwen_Qwen3-8B-GGUF" ]
	[ "${lines[1]}" = "Qwen_Qwen3-8B-Q4_K_M.gguf" ]
	[ "${lines[2]}" = "bartowski/Qwen_Qwen3-1.7B-GGUF" ]
	[ "${lines[3]}" = "Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
	[ "${lines[4]}" = "bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf" ]
	[ "${lines[5]}" = "bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
	[ "${lines[6]}" = "bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf" ]
	[ "${lines[7]}" = "bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
	[ "${lines[8]}" = "main" ]
	[ "${lines[9]}" = "main" ]
	[ "${lines[10]}" = "planner/model:plan.gguf" ]
	[ "${lines[11]}" = "react/model:react.gguf" ]
	[ "${lines[12]}" = "stable" ]
	[ "${lines[13]}" = "beta" ]
}

@test "cli shared model flags populate planner and react when unset" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/cli/cli.sh
COMMAND="run"
DEFAULT_MODEL_BRANCH_BASE=${DEFAULT_MODEL_BRANCH_BASE:-main}
DEFAULT_PLANNER_MODEL_BRANCH_BASE=${DEFAULT_PLANNER_MODEL_BRANCH_BASE:-main}
DEFAULT_REACT_MODEL_BRANCH_BASE=${DEFAULT_REACT_MODEL_BRANCH_BASE:-main}
PLANNER_MODEL_BRANCH="${DEFAULT_PLANNER_MODEL_BRANCH_BASE}"
REACT_MODEL_BRANCH="${DEFAULT_REACT_MODEL_BRANCH_BASE}"
parse_args --model shared/repo:shared.gguf --model-branch release -- "demo query"
printf '%s\n' "${PLANNER_MODEL_SPEC}" "${REACT_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" "${REACT_MODEL_BRANCH}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "shared/repo:shared.gguf" ]
	[ "${lines[1]}" = "shared/repo:shared.gguf" ]
	[ "${lines[2]}" = "release" ]
	[ "${lines[3]}" = "release" ]
}

@test "cli planner flags override shared selections" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/cli/cli.sh
COMMAND="run"
DEFAULT_MODEL_BRANCH_BASE=${DEFAULT_MODEL_BRANCH_BASE:-main}
DEFAULT_PLANNER_MODEL_BRANCH_BASE=${DEFAULT_PLANNER_MODEL_BRANCH_BASE:-main}
DEFAULT_REACT_MODEL_BRANCH_BASE=${DEFAULT_REACT_MODEL_BRANCH_BASE:-main}
PLANNER_MODEL_BRANCH="${DEFAULT_PLANNER_MODEL_BRANCH_BASE}"
REACT_MODEL_BRANCH="${DEFAULT_REACT_MODEL_BRANCH_BASE}"
parse_args --model shared/repo:shared.gguf --planner-model dedicated/planner:plan.gguf --planner-model-branch nightly -- "demo query"
printf '%s\n' "${PLANNER_MODEL_SPEC}" "${REACT_MODEL_SPEC}" "${PLANNER_MODEL_BRANCH}" "${REACT_MODEL_BRANCH}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "dedicated/planner:plan.gguf" ]
	[ "${lines[1]}" = "shared/repo:shared.gguf" ]
	[ "${lines[2]}" = "nightly" ]
	[ "${lines[3]}" = "main" ]
}
