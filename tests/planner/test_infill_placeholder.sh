#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for test_infill_placeholder.sh.

@test "planner schema allows executor fill placeholder for numeric fields" {
	run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/tools/registry.sh
source ./src/lib/planning/planner.sh
	init_tool_registry
	register_tool "numeric" "demo" "handler" '{"type":"object","properties":{"count":{"type":"number","minimum":1}},"required":["count"]}'
	schema_json="$(planner_build_plan_schema numeric)"
	printf '%s\n' "${schema_json}"
	jq -e '
	[
		.anyOf[]
		| .prefixItems[]
		| .anyOf[]?
		| select((.properties.tool.enum? // []) | index("numeric"))
		| .properties.args.anyOf[0].properties.count.anyOf[]?
		| select(.type == "object" and .properties.__fill__.const == true and (.required | index("__fill__")))
	] | length > 0
	' <<<"${schema_json}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "planner schema expands required-only anyOf branches for llama compatibility" {
	run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/tools/registry.sh
source ./src/lib/planning/planner.sh
init_tool_registry
	register_tool "alias_demo" "demo" "handler" '{"type":"object","additionalProperties":false,"properties":{"query":{"type":"string"},"input":{"type":"string"}},"anyOf":[{"required":["query"]},{"required":["input"]}]}'
	schema_json="$(planner_build_plan_schema alias_demo)"
	printf '%s' "${schema_json}" | jq -e '
	[
		.anyOf[]
		| .prefixItems[]
		| .anyOf[]?
		| select((.properties.tool.enum? // []) | index("alias_demo"))
		| .properties.args.anyOf[0].anyOf
		| all(
			(type != "object")
			or (has("required") | not)
			or ((keys | length) > 1)
		)
	] | any
	' >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "planner schema encodes final_answer as the terminal step" {
	run env -i PATH="$PATH" HOME="$HOME" VERBOSITY=0 PLANNER_MAX_PLAN_STEPS=4 bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/tools/registry.sh
source ./src/lib/planning/planner.sh
init_tool_registry
register_tool "terminal" "demo" "handler" '{"type":"object","required":["command"],"properties":{"command":{"type":"string","minLength":1},"cwd":{"type":"string"}},"additionalProperties":false}'
register_tool "final_answer" "demo" "handler" '{"type":"object","required":["input"],"properties":{"input":{"type":"string","minLength":1}},"additionalProperties":false}'
schema_json="$(planner_build_plan_schema terminal final_answer)"
printf '%s' "${schema_json}" | jq -e '
	(.anyOf | length) == 4
	and all(.anyOf[]; (.items == false) and (.prefixItems[-1].properties.tool.const == "final_answer"))
	and (
		[
			.anyOf[]
			| .prefixItems[0:-1][]
			| .anyOf[]?
			| ((.properties.tool.enum? // []) | index("final_answer"))
		]
		| all(. == null)
	)
' >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
