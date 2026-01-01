#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "plan_json_to_outline numbers steps from raw planner text" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
raw_plan='[{"tool":"terminal","args":{"command":"ls"},"thought":"list"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"wrap up"}]'
plan_json_to_outline "${raw_plan}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "1. list" ]
	[ "${lines[1]}" = "2. wrap up" ]
}

@test "plan_json_to_outline unwraps planner response objects" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
response='{"plan":[{"tool":"terminal","args":{"command":"ls"},"thought":"step one"},{"tool":"final_answer","args":{"input":"wrap"},"thought":"finish"}]}'
plan_json_to_outline "${response}"
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "1. step one" ]
	[ "${lines[1]}" = "2. finish" ]
}

@test "build_planner_prompt_with_tools injects tool descriptions when provided" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
tool_description() { printf "desc-%s" "$1"; }
tool_command() { printf "cmd-%s" "$1"; }
tool_safety() { printf "safe-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
prompt=$(build_planner_prompt_with_tools "find files" terminal notes_create)
printf '%s' "${prompt}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *"terminal"* ]]
	[[ "${output}" == *"notes_create"* ]]
}

@test "build_planner_prompt_with_tools renders args schema for tools" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/planning/prompting.sh
tool_description() { printf "desc-%s" "$1"; }
tool_command() { printf "cmd-%s" "$1"; }
tool_safety() { printf "safe-%s" "$1"; }
tool_args_schema() { printf '{"type":"object","properties":{"input":{"type":"string"}}}'; }
prompt=$(build_planner_prompt_with_tools "collect data" terminal)
printf '%s' "${prompt}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${output}" == *'Args Schema: {"type":"object","properties":{"input"'* ]]
}

@test "planner prompt prefix tracks rendered runtime fields across invocations" {
        run bash <<'SCRIPT'
set -euo pipefail
real_date="$(command -v date)"
mock_bin_dir="$(mktemp -d)"
  cat >"${mock_bin_dir}/date" <<'DATE'
  #!/usr/bin/env bash
  fmt="${1-}"
  if [[ "${fmt}" == "-u" ]]; then
          fmt="${2-}"
  fi

  if [[ "${fmt}" == "+%Y-%m-%d" ]]; then
          if [[ "${MOCK_SLOT:-}" == "first" ]]; then
                  printf '2024-01-01\n'
          else
                  printf '2024-02-02\n'
          fi
  elif [[ "${fmt}" == "+%H:%M:%S" ]]; then
          if [[ "${MOCK_SLOT:-}" == "first" ]]; then
                  printf '00:00:01\n'
          else
                  printf '00:00:02\n'
          fi
  elif [[ "${fmt}" == "+%A" ]]; then
          printf 'Monday\n'
  else
          exec "${real_date}" "$@"
  fi
DATE
chmod +x "${mock_bin_dir}/date"
export PATH="${mock_bin_dir}:${PATH}"
source ./src/lib/prompt/build_planner.sh
MOCK_SLOT=first
export MOCK_SLOT
prefix_first="$(build_planner_prompt_static_prefix "demo" "tool: summary" "seeded search context")"
first_prompt="$(build_planner_prompt "demo" "tool: summary" "seeded search context")"
MOCK_SLOT=second
export MOCK_SLOT
prefix_second="$(build_planner_prompt_static_prefix "demo" "tool: summary" "seeded search context")"
second_prompt="$(build_planner_prompt "demo" "tool: summary" "seeded search context")"
if [[ "${first_prompt}" != "${prefix_first}"* ]]; then
        exit 1
fi
if [[ "${second_prompt}" != "${prefix_second}"* ]]; then
        exit 1
fi
if [[ "${prefix_first}" == "${prefix_second}" ]]; then
        exit 1
fi
printf 'ok\n'
SCRIPT

        [ "$status" -eq 0 ]
        [ "${output}" = "ok" ]
}

@test "planner prompt prefix matches rendered prompt start and survives suffix changes" {
        run bash <<'SCRIPT'
set -euo pipefail
real_date="$(command -v date)"
mock_bin_dir="$(mktemp -d)"
  cat >"${mock_bin_dir}/date" <<'DATE'
  #!/usr/bin/env bash
  fmt="${1-}"
  if [[ "${fmt}" == "-u" ]]; then
          fmt="${2-}"
  fi

  if [[ "${fmt}" == "+%Y-%m-%d" ]]; then
          printf '2024-03-03\n'
  elif [[ "${fmt}" == "+%H:%M:%S" ]]; then
          printf '00:00:03\n'
  elif [[ "${fmt}" == "+%A" ]]; then
          printf 'Sunday\n'
  else
          exec "${real_date}" "$@"
  fi
DATE
chmod +x "${mock_bin_dir}/date"
export PATH="${mock_bin_dir}:${PATH}"
source ./src/lib/prompt/build_planner.sh

tool_lines="tool: summary"
search_one="seeded search context"
search_two="updated search context"

prefix_one="$(build_planner_prompt_static_prefix "demo" "${tool_lines}" "${search_one}")"
prompt_one="$(build_planner_prompt "demo" "${tool_lines}" "${search_one}")"

if [[ "${prompt_one}" != "${prefix_one}"* ]]; then
        exit 1
fi

prefix_two="$(build_planner_prompt_static_prefix "changed" "${tool_lines}" "${search_two}")"
prompt_two="$(build_planner_prompt "changed" "${tool_lines}" "${search_two}")"

if [[ "${prompt_two}" != "${prefix_two}"* ]]; then
        exit 1
fi

if [[ "${prefix_one}" != "${prefix_two}" ]]; then
        exit 1
fi

printf 'ok\n'
SCRIPT

        [ "$status" -eq 0 ]
        [ "${output}" = "ok" ]
}

@test "executor prompt template exposes infill placeholders" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/prompt/templates.sh
template="$(load_prompt_template executor)"
grep -F '${tool}' <<<"${template}"
grep -F '${args_json}' <<<"${template}"
grep -F '${context_fields}' <<<"${template}"
SCRIPT

	[ "$status" -eq 0 ]
}
