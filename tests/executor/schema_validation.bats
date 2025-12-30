#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "executor schema rejects missing required args" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/schema.sh

tool_registry_json() {
        cat <<'JSON'
{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","properties":{"needed":{"type":"string"},"nested":{"type":"object","properties":{"inner":{"type":"integer"}},"required":["inner"]}},"required":["needed","nested"],"additionalProperties":false}}}}
JSON
}

tool_names() {
        printf 'alpha\n'
}

schema_path=$(build_executor_action_schema "alpha")
invalid_action='{"action":{"tool":"alpha","args":{"optional":"ok"}}}'
validate_executor_action "${invalid_action}" "${schema_path}" 2>&1
rm -f "${schema_path}"
SCRIPT

	[ "$status" -ne 0 ]
}

@test "executor schema surfaces argument type failures" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/executor/schema.sh

tool_registry_json() {
        cat <<'JSON'
{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","properties":{"count":{"type":"integer"}},"required":["count"],"additionalProperties":false}}}}
JSON
}

tool_names() {
        printf 'alpha\n'
}

schema_path=$(build_executor_action_schema "alpha")
invalid_action='{"action":{"tool":"alpha","args":{"count":"oops"}}}'

set +e
validate_executor_action "${invalid_action}" "${schema_path}" 2>err.log
status=$?
set -e

rm -f "${schema_path}"

if [[ ${status} -eq 0 ]]; then
        echo "validation unexpectedly succeeded"
        exit 1
fi

cat err.log
grep -F "action/args/count: 'oops' is not of type 'integer'" err.log
rm -f err.log
SCRIPT

	[ "$status" -eq 0 ]
}
