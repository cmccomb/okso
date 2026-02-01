#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	export VERBOSITY=0
}

@test "register_workflow_tools registers pseudo-tools with schemas" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./tests/fixtures/workflows/valid
source ./src/lib/workflows/loader.sh
source ./src/tools/registry.sh
init_tool_registry
register_workflow_tools
tool_names | sort
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "workflow_example_json" ]
}

@test "register_workflow_tools preserves parameter schemas" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./tests/fixtures/workflows/valid
source ./src/lib/workflows/loader.sh
source ./src/tools/registry.sh
init_tool_registry
register_workflow_tools
tool_args_schema "workflow_example_json" | jq -r '.required[0]'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "project" ]
}

@test "expand_workflow_plan expands steps with interpolation" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./tests/fixtures/workflows/valid
source ./src/lib/workflows/loader.sh
plan='[{"tool":"workflow_example_json","args":{"project":"okso"},"thought":"invoke"}]'
expanded=$(expand_workflow_plan "${plan}")
printf '%s\n' "${expanded}" | jq -r '.[0].tool,.[0].args.command,.[0].thought'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "terminal" ]
	[ "${lines[1]}" = "echo \"okso\"" ]
	[ "${lines[2]}" = "Ping okso" ]
}

@test "expand_workflow_plan fails when workflow is missing" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./tests/fixtures/workflows/valid
source ./src/lib/workflows/loader.sh
plan='[{"tool":"workflow_missing","args":{},"thought":"invoke"}]'
expand_workflow_plan "${plan}"
SCRIPT

	[ "$status" -ne 0 ]
}

@test "workflows_load_specs fails for malformed workflow specs" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./tests/fixtures/workflows/invalid
source ./src/lib/workflows/loader.sh
workflows_load_specs
SCRIPT

	[ "$status" -ne 0 ]
}
