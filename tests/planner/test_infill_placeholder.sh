#!/usr/bin/env bats

@test "planner schema allows executor fill placeholder for numeric fields" {
	run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/tools/registry.sh
source ./src/lib/planning/planner.sh
init_tool_registry
register_tool "numeric" "demo" "" "handler" '{"type":"object","properties":{"count":{"type":"number","minimum":1}},"required":["count"]}'
schema_json="$(planner_build_plan_schema numeric)"
printenv schema_json
jq -e '.items.anyOf[0].properties.args.anyOf[0].properties.count.anyOf[]
	| select(.type=="object" and .properties.__fill__.const==true and (.required | index("__fill__")))'
<<<"${schema_json}" >/dev/null
SCRIPT
}
