#!/usr/bin/env bats

@test "create_default_settings seeds derived defaults" {
	run bash -lc '
                set -e
                source ./src/lib/core/settings.sh
                create_default_settings compat
                doc="$(settings_get_json_document compat)"
                printf "%s\n%s\n%s\n%s\n%s" \
                        "$(jq -r ".config_dir" <<<"${doc}")" \
                        "$(jq -r ".config_file" <<<"${doc}")" \
                        "$(jq -r ".planner_model_spec" <<<"${doc}")" \
                        "$(jq -r ".react_model_spec" <<<"${doc}")" \
                        "$(jq -r ".use_react_llama" <<<"${doc}")"
        '
	[ "$status" -eq 0 ]
	config_dir_expected="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
	[ "${lines[0]}" = "${config_dir_expected}" ]
	[ "${lines[1]}" = "${config_dir_expected}/config.env" ]
	[ "${lines[2]}" = "bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf" ]
	[ "${lines[3]}" = "bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf" ]
	[ "${lines[4]}" = "true" ]
}

@test "settings persist across shells using cache" {
	run bash -lc '
                set -e
                prefix="persist_${RANDOM}"
                source ./src/lib/core/settings.sh
                create_default_settings "${prefix}"
                settings_set_json "${prefix}" example "value"
                cache_var="$(settings_namespace_json_var "${prefix}")"
                unset "${cache_var}"
                printf "%s" "$(settings_get_json_document "${prefix}" | jq -r ".example")"
        '
	[ "$status" -eq 0 ]
	[ "$output" = "value" ]
}

@test "default overrides merge onto base settings" {
	run bash -lc '
                set -e
                prefix="override_${RANDOM}"
                export DEFAULT_MODEL_FILE_BASE="Alt.gguf"
                source ./src/lib/core/settings.sh
                create_default_settings "${prefix}" "{\"verbosity\":\"5\",\"notes_dir\":\"/tmp/custom_notes\"}"
                doc="$(settings_get_json_document "${prefix}")"
                printf "%s|%s|%s" \
                        "$(jq -r ".default_model_file" <<<"${doc}")" \
                        "$(jq -r ".verbosity" <<<"${doc}")" \
                        "$(jq -r ".notes_dir" <<<"${doc}")"
        '
	[ "$status" -eq 0 ]
	[ "$output" = "Alt.gguf|5|/tmp/custom_notes" ]
}
