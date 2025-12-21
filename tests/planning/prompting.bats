#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "plan_json_to_outline numbers steps from raw planner text" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
raw_plan='[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"final_answer","args":{},"thought":"wrap up"}]'
plan_json_to_outline "${raw_plan}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "1. list" ]
	[ "${lines[1]}" = "2. wrap up" ]
}

@test "build_planner_prompt_with_tools injects tool descriptions when provided" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
prompt=$(build_planner_prompt_with_tools "find files" terminal notes_create)
printf '%s' "${prompt}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"terminal"* ]]
	[[ "${output}" == *"notes_create"* ]]
}

@test "planner prompt static prefix stays constant across invocations" {
	run bash <<'SCRIPT'
set -euo pipefail
real_date="$(command -v date)"
mock_bin_dir="$(mktemp -d)"
cat >"${mock_bin_dir}/date" <<'DATE'
#!/usr/bin/env bash
if [[ "$1" == "-u" && "$2" == "+%Y-%m-%d" ]]; then
        if [[ "${MOCK_SLOT:-}" == "first" ]]; then
                printf '2024-01-01\n'
        else
                printf '2024-02-02\n'
        fi
elif [[ "$1" == "-u" && "$2" == "+%H:%M:%S" ]]; then
        if [[ "${MOCK_SLOT:-}" == "first" ]]; then
                printf '00:00:01\n'
        else
                printf '00:00:02\n'
        fi
elif [[ "$1" == "-u" && "$2" == "+%A" ]]; then
        printf 'Monday\n'
else
        exec "${real_date}" "$@"
fi
DATE
chmod +x "${mock_bin_dir}/date"
export PATH="${mock_bin_dir}:${PATH}"
source ./src/lib/planning/prompts.sh
prefix="$(build_planner_prompt_static_prefix)"
MOCK_SLOT=first
export MOCK_SLOT
first_prompt="$(build_planner_prompt "demo" "tool: summary")"
MOCK_SLOT=second
export MOCK_SLOT
second_prompt="$(build_planner_prompt "demo" "tool: summary")"
if [[ "${first_prompt}" != "${prefix}"* ]]; then
        exit 1
fi
if [[ "${second_prompt}" != "${prefix}"* ]]; then
        exit 1
fi
if [[ "${first_prompt}" == "${second_prompt}" ]]; then
        exit 1
fi
printf 'ok\n'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "ok" ]
}

@test "react prompt segments recombine into full prompt" {
	run bash <<'SCRIPT'
set -euo pipefail
real_date="$(command -v date)"
mock_bin_dir="$(mktemp -d)"
cat >"${mock_bin_dir}/date" <<'DATE'
#!/usr/bin/env bash
if [[ "$1" == "-u" && "$2" == "+%Y-%m-%d" ]]; then
        printf '2024-01-01\n'
elif [[ "$1" == "-u" && "$2" == "+%H:%M:%S" ]]; then
        printf '00:00:01\n'
elif [[ "$1" == "-u" && "$2" == "+%A" ]]; then
        printf 'Monday\n'
else
        exec "${real_date}" "$@"
fi
DATE
chmod +x "${mock_bin_dir}/date"
export PATH="${mock_bin_dir}:${PATH}"
source ./src/lib/planning/prompts.sh
prefix="$(build_react_prompt_static_prefix)"
suffix="$(build_react_prompt_dynamic_suffix "query" "tool list" "outline" "history" "{}" "step")"
full="$(build_react_prompt "query" "tool list" "outline" "history" "{}" "step")"
if [[ "${full}" != "${prefix}${suffix}" ]]; then
        exit 1
fi
printf 'ok\n'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "ok" ]
}
