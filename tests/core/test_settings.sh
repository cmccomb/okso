#!/usr/bin/env bats

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
