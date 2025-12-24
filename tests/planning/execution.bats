#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "should_prompt_for_tool respects approval flags" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/exec/dispatch.sh
PLAN_ONLY=true
DRY_RUN=false
FORCE_CONFIRM=false
APPROVE_ALL=false
if should_prompt_for_tool; then
        echo "prompt"
else
        echo "skip"
fi
SCRIPT

	[ "$status" -eq 0 ]
	[ "${output}" = "skip" ]
}

@test "execute_tool_with_query runs handler and emits structured response" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/exec/dispatch.sh
APPROVE_ALL=true
PLAN_ONLY=false
DRY_RUN=false
FORCE_CONFIRM=false

tool_handler() { printf 'fake_handler'; }
fake_handler() {
        printf 'ran:%s:%s' "${TOOL_QUERY}" "${TOOL_ARGS}"
}

execute_tool_with_query "example" "do it" "context" '{"foo":1}'
SCRIPT

	[ "$status" -eq 0 ]
	payload=$(printf '%s' "${output}")
	body=$(printf '%s' "${payload}" | jq -r '.output')
	exit_code=$(printf '%s' "${payload}" | jq -r '.exit_code')
	summary_exit=$(printf '%s' "${payload}" | jq -r '.summary | fromjson | .exit_code')
	[ "${body}" = 'ran:do it:{"foo":1}' ]
	[ "${exit_code}" -eq 0 ]
	[ "${summary_exit}" -eq 0 ]
}
