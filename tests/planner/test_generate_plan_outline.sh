#!/usr/bin/env bats
#
# Regression tests for generate_plan_outline.
#
# Usage:
#   bats tests/planner/test_generate_plan_outline.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "generate_plan_outline falls back to tool_names when TOOLS is unset" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh

 tool_names() { printf "%s\n" "fallback_tool" "secondary_tool"; }
 format_tool_descriptions() { printf "%s" "$1"; }
 build_planner_prompt_static_prefix() { printf ''; }
 build_planner_prompt_dynamic_suffix() { printf "TOOLS<<%s>>" "$2"; }
 schema_path() { printf "/tmp/schema"; }
 load_schema_text() { printf '{}'; }
 planner_fetch_search_context() { printf 'Search context unavailable.'; }
llama_infer() { printf "%s" "$1" > /tmp/planner_prompt; printf '[{"tool":"alpha","args":{},"thought":"step"}]'; }

LLAMA_AVAILABLE=true
unset TOOLS

output="$(generate_plan_outline "Query")"

expected_prompt=$'TOOLS<<fallback_tool
secondary_tool>>'
actual_prompt="$(cat /tmp/planner_prompt)"

[[ "${actual_prompt}" == "${expected_prompt}" ]]
[[ "${output}" == $'1. step
2. Summarize the result for the user.' ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}

@test "generate_plan_outline falls back to tool_names when TOOLS is scalar" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh

 tool_names() { printf "%s\n" "fallback_tool"; }
 format_tool_descriptions() { printf "%s" "$1"; }
 build_planner_prompt_static_prefix() { printf ''; }
 build_planner_prompt_dynamic_suffix() { printf "TOOLS<<%s>>" "$2"; }
 schema_path() { printf "/tmp/schema"; }
 load_schema_text() { printf '{}'; }
 planner_fetch_search_context() { printf 'Search context unavailable.'; }
llama_infer() { printf "%s" "$1" > /tmp/planner_prompt; printf '[{"tool":"alpha","args":{},"thought":"step"}]'; }

LLAMA_AVAILABLE=true
TOOLS="scalar_tool"

output="$(generate_plan_outline "Query")"

expected_prompt=$'TOOLS<<fallback_tool>>'
actual_prompt="$(cat /tmp/planner_prompt)"

[[ "${actual_prompt}" == "${expected_prompt}" ]]
[[ "${output}" == $'1. step
2. Summarize the result for the user.' ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}

@test "generate_plan_outline uses TOOLS array when provided" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh

 tool_names() { printf "%s\n" "fallback_tool"; }
 format_tool_descriptions() { printf "%s" "$1"; }
 build_planner_prompt_static_prefix() { printf ''; }
 build_planner_prompt_dynamic_suffix() { printf "TOOLS<<%s>>" "$2"; }
 schema_path() { printf "/tmp/schema"; }
 load_schema_text() { printf '{}'; }
 planner_fetch_search_context() { printf 'Search context unavailable.'; }
llama_infer() { printf "%s" "$1" > /tmp/planner_prompt; printf '[{"tool":"alpha","args":{},"thought":"step"}]'; }

LLAMA_AVAILABLE=true
declare -a TOOLS=("preferred_tool" "support_tool")

output="$(generate_plan_outline "Query")"

expected_prompt=$'TOOLS<<preferred_tool
support_tool>>'
actual_prompt="$(cat /tmp/planner_prompt)"

[[ "${actual_prompt}" == "${expected_prompt}" ]]
[[ "${output}" == $'1. step
2. Summarize the result for the user.' ]]
INNERSCRIPT
	)"
	[ "$status" -eq 0 ]
}
