#!/usr/bin/env bats
#
# Tests for mapping structured JSON tool arguments to CLI flags.
#
# Usage:
#   bats tests/tools/test_tool_args_structured.sh
#
# Regression tests ensuring TOOL_ARGS drive tool handlers.

@test "final_answer requires structured TOOL_ARGS" {
	script=$(
		cat <<'INNERSCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

chpwd_functions=()
unset -f chpwd _mise_hook 2>/dev/null || true

source ./src/tools/final_answer/index.sh

output=$(TOOL_ARGS='{"input":"structured value"}' tool_final_answer)

if [[ "${output}" != "structured value" ]]; then
        echo "final_answer did not prefer structured args"
        exit 1
fi

if TOOL_ARGS="" tool_final_answer >/dev/null 2>&1; then
        echo "final_answer unexpectedly accepted missing TOOL_ARGS"
        exit 1
fi
INNERSCRIPT
	)

	run bash -lc "${script}"
	[ "${status}" -eq 0 ]
}
