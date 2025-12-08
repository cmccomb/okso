#!/usr/bin/env bash
# shellcheck disable=SC2034
#
# Entrypoint for the local MCP-inspired assistant harness.
#
# Usage:
#   ./src/main.sh [OPTIONS] -- "user query"
#
# Options:
#   -h, --help            Show help text.
#   -V, --version         Show version information.
#   -y, --yes, --no-confirm
#                         Approve all tool runs without prompting.
#       --confirm         Always prompt before running tools.
#       --dry-run         Print the planned tool calls without running them.
#       --plan-only       Emit the planned calls as JSON and exit.
#   -m, --model VALUE     HF repo[:file] for llama.cpp download (default: Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf).
#       --model-branch BRANCH  HF branch or tag for the model download.
#       --config FILE     Config file to load (default: ${XDG_CONFIG_HOME:-$HOME/.config}/okso/config.env).
#   -v, --verbose         Increase log verbosity (JSON logs are always structured).
#   -q, --quiet           Silence informational logs.
#
# Environment:
#   LLAMA_BIN       llama.cpp binary (default: llama-cli).
#
# Dependencies:
#   - bash 5+
#   - Optional: llama.cpp binary available on PATH for real scoring.
#   - Optional: fd, rg for faster search tooling.
#
# Exit codes:
#   0 on success, non-zero on argument or runtime errors.
set -euo pipefail

resolve_script_dir() {
	local source_path source_dir
	source_path="${BASH_SOURCE[0]}"

	while [ -h "${source_path}" ]; do
		source_dir=$(cd -P -- "$(dirname -- "${source_path}")" && pwd)
		source_path=$(readlink "${source_path}")
		if [[ "${source_path}" != /* ]]; then
			source_path="${source_dir}/${source_path}"
		fi
	done

	cd -P -- "$(dirname -- "${source_path}")" && pwd
}

SCRIPT_DIR=$(resolve_script_dir)
# shellcheck source=./logging.sh disable=SC1091
source "${SCRIPT_DIR}/logging.sh"
# shellcheck source=./config.sh disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./tools.sh disable=SC1091
source "${SCRIPT_DIR}/tools.sh"
# shellcheck source=./planner.sh disable=SC1091
source "${SCRIPT_DIR}/planner.sh"
# shellcheck source=./respond.sh disable=SC1091
source "${SCRIPT_DIR}/respond.sh"
# shellcheck source=./cli.sh disable=SC1091
source "${SCRIPT_DIR}/cli.sh"
# shellcheck source=./runtime.sh disable=SC1091
source "${SCRIPT_DIR}/runtime.sh"

main() {
	local -A settings
	local plan_outline required_tools plan_entries plan_action

	load_runtime_settings settings "$@"

	if [[ "${settings[command]}" == "init" ]]; then
		apply_settings_to_globals settings
		write_config_file
		return 0
	fi

	prepare_environment_with_settings settings
	log "INFO" "Starting plan generation" "${settings[user_query]}"
	plan_outline="$(generate_plan_outline "${settings[user_query]}")"
	required_tools="$(extract_tools_from_plan "${plan_outline}")"
	log "INFO" "Planner identified tools" "${required_tools}"
	plan_entries="$(build_plan_entries_from_tools "${required_tools}" "${settings[user_query]}")"

	render_plan_outputs plan_action settings "${required_tools}" "${plan_entries}" "${plan_outline}"
	if [[ "${plan_action}" == "exit" ]]; then
		return 0
	fi

	select_response_strategy settings "${required_tools}" "${plan_entries}" "${plan_outline}"
}

main "$@"
