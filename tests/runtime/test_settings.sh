#!/usr/bin/env bats

@test "settings helpers store and retrieve values without associative arrays" {
	run bash -lc 'source ./src/lib/runtime.sh; create_default_settings compat; settings_set_json compat sample "value"; json="$(settings_get_json_document compat)"; printf "%s|%s" "$(settings_get_json compat sample)" "$(jq -r ".sample" <<<"${json}")"'
	[ "$status" -eq 0 ]
	[ "$output" = "value|value" ]
}

@test "create_default_settings wires derived defaults" {
	run bash -lc 'source ./src/lib/runtime.sh; create_default_settings compat; config_dir="$(settings_get_json compat config_dir)"; config_file="$(settings_get_json compat config_file)"; printf "%s\n%s" "${config_dir}" "${config_file}"'
	[ "$status" -eq 0 ]
	[[ "${lines[1]}" = "${lines[0]}/config.env" ]]
}

@test "react llama assistance defaults to enabled" {
	run bash -lc 'unset USE_REACT_LLAMA; source ./src/lib/runtime.sh; create_default_settings compat; printf "%s" "$(settings_get_json compat use_react_llama)"'
	[ "$status" -eq 0 ]
	[ "$output" = "true" ]
}

@test "settings json helpers round-trip through globals" {
	run bash -lc 'source ./src/lib/runtime.sh; create_default_settings compat; settings_set_json compat llama_bin "/custom/bin"; apply_settings_to_globals compat; before="${LLAMA_BIN}"; LLAMA_BIN="/changed/bin"; capture_globals_into_settings compat; after="$(settings_get_json compat llama_bin)"; printf "%s\n%s" "${before}" "${after}"'
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "/custom/bin" ]
	[ "${lines[1]}" = "/changed/bin" ]
}
