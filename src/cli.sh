#!/usr/bin/env bash
# shellcheck shell=bash
#
# CLI-facing helpers for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/cli.sh}/cli.sh"
#
# Environment variables:
#   COMMAND (string): operational mode, defaults to run.
#   USER_QUERY (string): captured user input after options parsing.
#
# Dependencies:
#   - bash 5+
#   - gum (optional, for styled help output)
#
# Exit codes:
#   0 for help/version responses; 1 for argument errors.

# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/cli.sh}/logging.sh"

build_usage_text() {
	cat <<'USAGE'
Usage: ./src/main.sh [OPTIONS] -- "user query"

Options:
  -h, --help            Show help text.
  -V, --version         Show version information.
  -y, --yes, --no-confirm
                        Approve all tool runs without prompting.
      --confirm         Always prompt before running tools.
      --dry-run         Print the planned tool calls without running them.
      --plan-only       Emit the planned calls as JSON and exit (implies --dry-run).
  -m, --model VALUE     HF repo[:file] for llama.cpp (default: Qwen/Qwen3-8B-GGUF:Qwen3-8B-Q4_K_M.gguf).
      --config FILE     Config file to load or create (default: ${XDG_CONFIG_HOME:-$HOME/.config}/okso/config.env).
  -v, --verbose         Increase log verbosity (JSON logs are always structured).
  -q, --quiet           Silence informational logs.

The script orchestrates a llama.cpp-backed planner with a registry of
machine-checkable tools (MCP-style). Provide a natural language query after
"--" to trigger planning, ranking, and execution.

Use "./src/main.sh init" with the same options to write a config file without
running a query. The config file stores model defaults and approval behavior
for future runs.
USAGE
}

render_usage() {
	local usage_text
	usage_text="$(build_usage_text)"

	if command -v gum >/dev/null 2>&1; then
		printf '%s\n' "${usage_text}" | gum format
		return
	fi

	printf '%s\n' "${usage_text}"
}

show_help() {
	render_usage
}

show_version() {
	printf 'okso assistant %s\n' "${VERSION}"
}

# shellcheck disable=SC2034
parse_args() {
	local positional
	positional=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		init | configure)
			COMMAND="init"
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		-V | --version)
			show_version
			exit 0
			;;
		-y | --yes | --no-confirm)
			APPROVE_ALL=true
			FORCE_CONFIRM=false
			shift
			;;
		--confirm)
			FORCE_CONFIRM=true
			APPROVE_ALL=false
			shift
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--plan-only)
			PLAN_ONLY=true
			DRY_RUN=true
			shift
			;;
		-m | --model)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--model requires an HF repo[:file] value"
				exit 1
			fi
			MODEL_SPEC="$2"
			shift 2
			;;
		--config)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--config requires a path"
				exit 1
			fi
			CONFIG_FILE="$2"
			shift 2
			;;
		-v | --verbose)
			VERBOSITY=2
			shift
			;;
		-q | --quiet)
			VERBOSITY=0
			shift
			;;
		--)
			shift
			break
			;;
		-*)
			log "ERROR" "Unknown option" "$1"
			exit 1
			;;
		*)
			positional+=("$1")
			shift
			;;
		esac
	done

	if [[ ${#positional[@]} -gt 0 ]]; then
		USER_QUERY="${positional[*]}"
	else
		USER_QUERY="$*"
	fi

	if [[ "${COMMAND}" == "run" && -z "${USER_QUERY:-}" ]]; then
		log "ERROR" "A user query is required. See --help for usage."
		exit 1
	fi
}
