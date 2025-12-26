#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "planner schema rejects args_control nested under args" {
	run bash <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
schema_path="./src/schemas/planner_plan.schema.json"
jq -e '.properties.plan.items.properties.args.propertyNames | (.type == "string" and .not.const == "args_control")' "${schema_path}"
SCRIPT

	[ "$status" -eq 0 ]
}
