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

VERSION="0.1.0"
LLAMA_BIN=${LLAMA_BIN:-"llama-cli"}
DEFAULT_MODEL_FILE="Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
CONFIG_FILE="${CONFIG_DIR}/config.env"
MODEL_SPEC="bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF:${DEFAULT_MODEL_FILE}"
MODEL_BRANCH="main"
MODEL_REPO=""
MODEL_FILE=""
APPROVE_ALL=false
FORCE_CONFIRM=false
DRY_RUN=false
PLAN_ONLY=false
VERBOSITY=1
NOTES_DIR="${HOME}/.okso"
LLAMA_AVAILABLE=false
USE_REACT_LLAMA=${USE_REACT_LLAMA:-false}
IS_MACOS=false
COMMAND="run"
USER_QUERY=""

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

main() {
	local ranked_tools plan_entries
	detect_config_file "$@"
	load_config
	parse_args "$@"

	normalize_approval_flags

	if [[ "${COMMAND}" == "init" ]]; then
		write_config_file
		return 0
	fi

	init_environment
	init_tool_registry
	initialize_tools
	log "DEBUG" "Starting tool selection" "${USER_QUERY}"
	ranked_tools="$(rank_tools "${USER_QUERY}")"
	plan_entries="$(build_plan_entries "${ranked_tools}" "${USER_QUERY}")"
	printf '%s\n' "$(generate_tool_prompt "${USER_QUERY}" "${ranked_tools}")"

	if [[ "${PLAN_ONLY}" == true ]]; then
		emit_plan_json "${plan_entries}"
		return 0
	fi

	if [[ "${DRY_RUN}" == true ]]; then
		printf 'Dry run: planned tool calls (no execution).\n'
		emit_plan_json "${plan_entries}"
		while IFS='|' read -r tool query score; do
			[[ -z "${tool}" ]] && continue
			printf '%s\n' "${query}"
		done <<<"${plan_entries}"
		return 0
	fi

	if [[ -z "${ranked_tools}" ]]; then
		emit_plan_json "${plan_entries}"
		log "WARN" "No tools selected; responding directly" "${USER_QUERY}"
		printf '%s\n' "$(respond_text "${USER_QUERY}" "${plan_entries}")"
		return 0
	fi

	react_loop "${USER_QUERY}" "${ranked_tools}" "${plan_entries}"
}

main "$@"
