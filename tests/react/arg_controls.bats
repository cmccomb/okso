#!/usr/bin/env bats

setup() {
        unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "apply_plan_arg_controls fills context args and locks planner values" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/loop.sh

tool_args_schema() {
        printf '{"properties":{"title":{"type":"string"},"body":{"type":"string"}}}'
}

plan_entry='{"tool":"notes_create","args":{"title":"Planner Title","body":"Original body"},"args_control":{"title":"locked","body":"context"}}'
executor_args='{"title":"User Title","body":"__MISSING__"}'
user_query='Provide meeting summary'
resolved=$(apply_plan_arg_controls "notes_create" "${executor_args}" "${plan_entry}" "${user_query}" "__MISSING__")
jq -r '.title,.body' <<<"${resolved}"
SCRIPT

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "Planner Title" ]
        [ "${lines[1]}" = "Provide meeting summary" ]
}

