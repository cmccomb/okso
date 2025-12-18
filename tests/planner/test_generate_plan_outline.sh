#!/usr/bin/env bats
#
# Regression tests for generate_plan_outline.
#
# Usage:
#   bats tests/planner/test_generate_plan_outline.sh
#
# Dependencies:
#   - bats
#   - bash 5+

@test "generate_plan_outline works when mapfile builtin is unavailable" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                enable -n mapfile 2>/dev/null || true

                source ./src/lib/planner.sh

                log() { :; }

                LLAMA_AVAILABLE=false
                output="$(generate_plan_outline "Summarize request")"
                [[ "${output}" == "1. Respond directly to the user request." ]]
        '
	[ "$status" -eq 0 ]
}

@test "generate_plan_outline falls back to tool_names when TOOLS is unset" {
	run bash -lc "$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

source ./src/lib/planner.sh

tool_names() { printf "%s\n" "fallback_tool" "secondary_tool"; }
format_tool_descriptions() { printf "%s" "$1"; }
build_planner_prompt() { printf "TOOLS<<%s>>" "$2"; }
schema_path() { printf "/tmp/schema"; }
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

source ./src/lib/planner.sh

tool_names() { printf "%s\n" "fallback_tool"; }
format_tool_descriptions() { printf "%s" "$1"; }
build_planner_prompt() { printf "TOOLS<<%s>>" "$2"; }
schema_path() { printf "/tmp/schema"; }
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

source ./src/lib/planner.sh

tool_names() { printf "%s\n" "fallback_tool"; }
format_tool_descriptions() { printf "%s" "$1"; }
build_planner_prompt() { printf "TOOLS<<%s>>" "$2"; }
schema_path() { printf "/tmp/schema"; }
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
