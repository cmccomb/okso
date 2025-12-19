#!/usr/bin/env bats

@test "settings helpers persist arbitrary JSON fields" {
        run bash -lc '
                set -e
                source ./src/lib/runtime.sh
                create_default_settings compat
                settings_set_json compat sample "value"
                doc="$(settings_get_json_document compat)"
                printf "%s|%s|%s|%s" \
                        "$(settings_get_json compat sample)" \
                        "$(jq -r ".sample" <<<"${doc}")" \
                        "$(jq -r ".config_dir" <<<"${doc}")" \
                        "$(jq -r ".config_file" <<<"${doc}")"
        '
        [ "$status" -eq 0 ]
        config_dir_expected="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
        [ "$output" = "value|value|${config_dir_expected}|${config_dir_expected}/config.env" ]
}

@test "create_default_settings wires derived defaults and react toggle" {
        run bash -lc '
                set -e
                unset USE_REACT_LLAMA
                source ./src/lib/runtime.sh
                create_default_settings compat
                doc="$(settings_get_json_document compat)"
                printf "%s\n%s\n%s\n%s\n%s\n%s\n%s" \
                        "$(jq -r ".config_dir" <<<"${doc}")" \
                        "$(jq -r ".config_file" <<<"${doc}")" \
                        "$(jq -r ".use_react_llama" <<<"${doc}")" \
                        "$(jq -r ".planner_model_spec" <<<"${doc}")" \
                        "$(jq -r ".react_model_spec" <<<"${doc}")" \
                        "$(jq -r ".default_model_file" <<<"${doc}")" \
                        "$(jq -r ".default_planner_model_file" <<<"${doc}")"
        '
        [ "$status" -eq 0 ]
        config_dir_expected="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
        [ "${lines[0]}" = "${config_dir_expected}" ]
        [ "${lines[1]}" = "${config_dir_expected}/config.env" ]
        [ "${lines[2]}" = "true" ]
        [ "${lines[3]}" = "bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf" ]
        [ "${lines[4]}" = "bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
        [ "${lines[5]}" = "Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
        [ "${lines[6]}" = "Qwen_Qwen3-8B-Q4_K_M.gguf" ]
}

@test "settings json helpers round-trip through globals" {
        run bash -lc '
                set -e
                source ./src/lib/runtime.sh
                create_default_settings compat
                settings_set_json compat llama_bin "/custom/bin"
                apply_settings_to_globals compat
                before="${LLAMA_BIN}"
                LLAMA_BIN="/changed/bin"
                capture_globals_into_settings compat
                after="$(settings_get_json compat llama_bin)"
                printf "%s\n%s" "${before}" "${after}"
        '
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "/custom/bin" ]
        [ "${lines[1]}" = "/changed/bin" ]
}
