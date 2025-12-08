#!/usr/bin/env bats

@test "settings helpers store and retrieve values without associative arrays" {
	run bash -lc 'source ./src/runtime.sh; create_default_settings compat; settings_set compat sample "value"; printf "%s" "$(settings_get compat sample)"'
	[ "$status" -eq 0 ]
	[ "$output" = "value" ]
}

@test "render_plan_outputs sets action when plan-only is enabled" {
	run bash -lc 'source ./src/runtime.sh; create_default_settings compat; settings_set compat plan_only true; render_plan_outputs action compat "terminal" "tool|echo 1|0.2" "outline"; printf "%s" "${action}"'
	[ "$status" -eq 0 ]
	[[ "$output" == *"exit" ]]
	[[ "$output" == *"Suggested tools"* ]]
}
