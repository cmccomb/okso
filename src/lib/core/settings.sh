#!/usr/bin/env bash
# shellcheck shell=bash
#
# Namespaced settings helpers built on top of json_state.
#
# Usage:
#   source "${BASH_SOURCE[0]%/settings.sh}/settings.sh"
#
# Environment variables:
#   DEFAULT_MODEL_FILE_BASE (string): Default ReAct GGUF filename.
#   DEFAULT_PLANNER_MODEL_FILE_BASE (string): Default planner GGUF filename.
#   DEFAULT_PLANNER_MODEL_SPEC_BASE (string): Default planner repo[:file] spec.
#   DEFAULT_REACT_MODEL_SPEC_BASE (string): Default ReAct repo[:file] spec.
#   DEFAULT_PLANNER_MODEL_BRANCH_BASE (string): Default planner branch/tag.
#   DEFAULT_REACT_MODEL_BRANCH_BASE (string): Default ReAct branch/tag.
#   USE_REACT_LLAMA (bool string): Toggle ReAct llama usage ("true"/"false").
#   LLAMA_BIN (string): Path to the llama.cpp binary.
#   XDG_CONFIG_HOME (string): Config directory base; defaults to ${HOME}/.config.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - logging.sh (indirect via json_state.sh)
#
# Exit codes:
#   Functions return non-zero on misuse or jq failures; callers should handle failures.

CORE_SETTINGS_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./json_state.sh disable=SC1091
source "${CORE_SETTINGS_LIB_DIR}/json_state.sh"

settings_namespace_json_var() {
	# Generates the shell variable name for a settings namespace.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	json_state_namespace_var "$@"
}

settings_get_json_document() {
	# Retrieves the JSON document for a namespace with optional fallback.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - fallback JSON (string, optional; defaults to '{}')
	#   $3 - output variable name (string, optional)
	json_state_get_document "$@"
}

settings_set_json_document() {
	# Sets the JSON document for a namespace after validating JSON.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - JSON document (string)
	json_state_set_document "$@"
}

settings_clear_namespace() {
	# Clears a settings namespace to an empty JSON document or provided value.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - JSON document to write (string, optional; defaults to '{}')
	local prefix document
	prefix="$1"
	document="${2:-{}}"
	settings_set_json_document "${prefix}" "${document}"
}

settings_set() {
	# Sets a logical key in the settings document.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	#   $3 - value (string)
	settings_set_json "$@"
}

settings_get() {
	# Fetches a logical key from the settings document.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	settings_get_json "$@"
}

settings_set_json() {
	# Writes a JSON-serializable value at the provided key.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	#   $3 - value (string)
	json_state_set_key "$@"
}

settings_get_json() {
	# Reads a JSON value at the provided key.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - logical key (string)
	json_state_get_key "$@"
}

create_default_settings() {
	# Builds and stores the default settings document for the namespace.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - overrides JSON to merge with defaults (string, optional)
	local settings_prefix overrides default_model_file default_planner_model_file config_dir config_file
	local planner_model_spec react_model_spec default_json override_json
	settings_prefix="$1"
	overrides="${2:-}"

	config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
	default_model_file="${DEFAULT_MODEL_FILE_BASE:-Qwen_Qwen3-4B-Q4_K_M.gguf}"
	default_planner_model_file="${DEFAULT_PLANNER_MODEL_FILE_BASE:-Qwen_Qwen3-8B-Q4_K_M.gguf}"
	config_file="${config_dir}/config.env"
	planner_model_spec="${DEFAULT_PLANNER_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-8B-GGUF:${default_planner_model_file}}"
	react_model_spec="${DEFAULT_REACT_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-4B-GGUF:${default_model_file}}"

	default_json=$(jq -c -n \
		--arg version "0.1.0" \
		--arg llama_bin "${LLAMA_BIN:-llama-cli}" \
		--arg default_model_file "${default_model_file}" \
		--arg default_planner_model_file "${default_planner_model_file}" \
		--arg config_dir "${config_dir}" \
		--arg config_file "${config_file}" \
		--arg planner_model_spec "${planner_model_spec}" \
		--arg react_model_spec "${react_model_spec}" \
		--arg planner_model_branch "${DEFAULT_PLANNER_MODEL_BRANCH_BASE:-main}" \
		--arg react_model_branch "${DEFAULT_REACT_MODEL_BRANCH_BASE:-main}" \
		--arg notes_dir "${HOME}/.okso" \
		--arg use_react_llama "${USE_REACT_LLAMA:-true}" \
		'{
                        version: $version,
                        llama_bin: $llama_bin,
                        default_model_file: $default_model_file,
                        default_planner_model_file: $default_planner_model_file,
                        config_dir: $config_dir,
                        config_file: $config_file,
                        planner_model_spec: $planner_model_spec,
                        planner_model_branch: $planner_model_branch,
                        react_model_spec: $react_model_spec,
                        react_model_branch: $react_model_branch,
                        planner_model_repo: "",
                        planner_model_file: "",
                        react_model_repo: "",
                        react_model_file: "",
                        approve_all: "false",
                        force_confirm: "false",
                        dry_run: "false",
                        plan_only: "false",
                        verbosity: "1",
                        notes_dir: $notes_dir,
                        llama_available: "true",
                        use_react_llama: $use_react_llama,
                        is_macos: "false",
                        command: "run",
                        user_query: ""
                }')

	if [[ -n "${overrides}" ]]; then
		if override_json=$(printf '%s' "${overrides}" | jq -c '.' 2>/dev/null); then
			default_json=$(jq -c --argjson overrides "${override_json}" '. * $overrides' <<<"${default_json}")
		else
			log "ERROR" "create_default_settings: invalid overrides JSON" "namespace=${settings_prefix}" || true
		fi
	fi

	settings_set_json_document "${settings_prefix}" "${default_json}"
}
