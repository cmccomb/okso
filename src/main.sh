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
#       --model-cache DIR      Directory that stores downloaded models (default: ~/.do/models).
#       --config FILE     Config file to load (default: ${XDG_CONFIG_HOME:-$HOME/.config}/do/config.env).
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
LLAMA_BIN=${LLAMA_BIN:-llama-cli}
DEFAULT_MODEL_FILE="qwen3-1.5b-instruct-q4_k_m.gguf"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/do"
CONFIG_FILE="${CONFIG_DIR}/config.env"
MODEL_SPEC="Qwen/Qwen3-1.5B-Instruct-GGUF:${DEFAULT_MODEL_FILE}"
MODEL_BRANCH="main"
MODEL_CACHE="${HOME}/.do/models"
MODEL_PATH=""
APPROVE_ALL=false
FORCE_CONFIRM=false
DRY_RUN=false
PLAN_ONLY=false
VERBOSITY=1
NOTES_DIR="${HOME}/.do"
LLAMA_AVAILABLE=false
IS_MACOS=false
COMMAND="run"
USER_QUERY=""

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./logging.sh disable=SC1091
source "${SCRIPT_DIR}/logging.sh"
# shellcheck source=./config.sh disable=SC1091
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./tools.sh disable=SC1091
source "${SCRIPT_DIR}/tools.sh"
# shellcheck source=./planner.sh disable=SC1091
source "${SCRIPT_DIR}/planner.sh"
# shellcheck source=./cli.sh disable=SC1091
source "${SCRIPT_DIR}/cli.sh"

main() {
	local ranked_tools
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
	printf '%s\n' "$(generate_tool_prompt "${USER_QUERY}" "${ranked_tools}")"
	planner_executor_loop "${ranked_tools}"
}

main "$@"
