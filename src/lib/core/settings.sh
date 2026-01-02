#!/usr/bin/env bash
# shellcheck shell=bash
#
# Namespaced settings helpers built on top of json_state.
#
# Usage:
#   source "${BASH_SOURCE[0]%/settings.sh}/settings.sh"
#
# Environment variables:
#   DEFAULT_EXECUTOR_MODEL_FILE (string): Default executor GGUF filename.
#   DEFAULT_PLANNER_MODEL_FILE (string): Default planner GGUF filename.
#   DEFAULT_PLANNER_MODEL_SPEC_BASE (string): Default planner repo[:file] spec.
#   DEFAULT_EXECUTOR_MODEL_SPEC_BASE (string): Default executor repo[:file] spec.
#   DEFAULT_PLANNER_MODEL_BRANCH_BASE (string): Default planner branch/tag.
#   DEFAULT_EXECUTOR_MODEL_BRANCH_BASE (string): Default executor branch/tag.
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

# shellcheck source=src/lib/core/json_state.sh
source "${CORE_SETTINGS_LIB_DIR}/json_state.sh"

# Settings consumers should call json_state_* helpers directly for reads and writes
# to avoid duplicating wrapper functions. This module provides only the
# settings-specific bootstrapping needed to materialize defaults.

create_default_settings() {
	# Builds and stores the default settings document for the namespace.
	# Arguments:
	#   $1 - settings namespace prefix (string)
	#   $2 - overrides JSON to merge with defaults (string, optional)
	local settings_prefix overrides default_model_file default_planner_model_file config_dir config_file
	local planner_model_spec executor_model_spec rephraser_model_spec default_json override_json cache_dir run_id
	local planner_cache_file executor_cache_file rephraser_cache_file executor_model_branch
	settings_prefix="$1"
	overrides="${2:-}"

	# Allow autotuned model defaults to be set by external code
	if declare -f set_autotuned_model_defaults >/dev/null 2>&1; then
		set_autotuned_model_defaults
	fi

	# Build paths and specs
	config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
	cache_dir="${OKSO_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/okso}"
	run_id="${OKSO_RUN_ID:-$(date -u +"%Y%m%dT%H%M%SZ")}"
	default_model_file="${DEFAULT_MODEL_FILE_BASE:-${DEFAULT_EXECUTOR_MODEL_FILE:-Qwen_Qwen3-4B-Q4_K_M.gguf}}"
	default_planner_model_file="${DEFAULT_PLANNER_MODEL_FILE_BASE:-${DEFAULT_PLANNER_MODEL_FILE:-Qwen_Qwen3-8B-Q4_K_M.gguf}}"
	config_file="${config_dir}/config.env"
	planner_model_spec="${DEFAULT_PLANNER_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-8B-GGUF:${default_planner_model_file}}"
	executor_model_spec="${EXECUTOR_MODEL_SPEC:-${DEFAULT_EXECUTOR_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-4B-GGUF:${default_model_file}}}"
	rephraser_model_spec="${DEFAULT_REPHRASER_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-1.7B-GGUF:${DEFAULT_REPHRASER_MODEL_FILE:-Qwen_Qwen3-1.7B-Q4_K_M.gguf}}"
	planner_cache_file="${OKSO_PLANNER_CACHE_FILE:-${cache_dir}/planner.prompt-cache}"
	executor_cache_file="${OKSO_EXECUTOR_CACHE_FILE:-${cache_dir}/runs/${run_id}/executor.prompt-cache}"
	rephraser_cache_file="${OKSO_REPHRASER_CACHE_FILE:-${cache_dir}/rephraser.prompt-cache}"
	executor_model_branch="${EXECUTOR_MODEL_BRANCH:-${DEFAULT_EXECUTOR_MODEL_BRANCH_BASE:-main}}"

	# Build default JSON document
	default_json=$(jq -c -n \
		--arg version "0.1.0" \
		--arg llama_bin "${LLAMA_BIN:-llama-completion}" \
		--arg default_model_file "${default_model_file}" \
		--arg default_planner_model_file "${default_planner_model_file}" \
		--arg config_dir "${config_dir}" \
		--arg config_file "${config_file}" \
		--arg cache_dir "${cache_dir}" \
		--arg planner_cache_file "${planner_cache_file}" \
		--arg executor_cache_file "${executor_cache_file}" \
		--arg rephraser_cache_file "${rephraser_cache_file}" \
		--arg run_id "${run_id}" \
		--arg planner_model_spec "${planner_model_spec}" \
		--arg executor_model_spec "${executor_model_spec}" \
		--arg rephraser_model_spec "${rephraser_model_spec}" \
		--arg planner_model_branch "${DEFAULT_PLANNER_MODEL_BRANCH_BASE:-main}" \
		--arg executor_model_branch "${executor_model_branch}" \
		--arg rephraser_model_branch "${DEFAULT_REPHRASER_MODEL_BRANCH_BASE:-main}" \
		--arg notes_dir "${HOME}/.okso" \
		--arg use_executor_llama "${USE_EXECUTOR_LLAMA:-true}" \
		'{
                        version: $version,
                        llama_bin: $llama_bin,
                        default_model_file: $default_model_file,
                        default_planner_model_file: $default_planner_model_file,
                        config_dir: $config_dir,
                        config_file: $config_file,
                        run_id: $run_id,
                        planner_model_spec: $planner_model_spec,
                        planner_model_branch: $planner_model_branch,
                        executor_model_spec: $executor_model_spec,
                        executor_model_branch: $executor_model_branch,
                        rephraser_model_spec: $rephraser_model_spec,
                        rephraser_model_branch: $rephraser_model_branch,
                        planner_model_repo: "",
                        planner_model_file: "",
                        executor_model_repo: "",
                        executor_model_file: "",
                        rephraser_model_repo: "",
                        rephraser_model_file: "",
                        approve_all: "false",
                        verbosity: "1",
                        notes_dir: $notes_dir,
                        llama_available: "true",
                        use_executor_llama: $use_executor_llama,
                        is_macos: "false",
                        command: "run",
                        user_query: ""
                }')

	# Apply overrides if provided
	if [[ -n "${overrides}" ]]; then
		if override_json=$(printf '%s' "${overrides}" | jq -c '.' 2>/dev/null); then
			default_json=$(jq -c --argjson overrides "${override_json}" '. * $overrides' <<<"${default_json}")
		else
			log "ERROR" "create_default_settings: invalid overrides JSON" "namespace=${settings_prefix}" || true
		fi
	fi

	# Store the default settings document
	json_state_set_document "${settings_prefix}" "${default_json}"
}
