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
#   - bash 3.2+
#   - gum (optional, for styled help output)
#
# Exit codes:
#   0 for help/version responses; 1 for argument errors.

CLI_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${CLI_LIB_DIR}/../core/logging.sh"

build_usage_text() {
	local entrypoint_display
	entrypoint_display="${OKSO_ENTRYPOINT:-./src/bin/okso}"

	cat <<USAGE
Usage: ${entrypoint_display} [OPTIONS] -- "user query"

Options:
  -h, --help            Show help text.
  -V, --version         Show version information.
  -y, --yes, --no-confirm
                        Approve all tool runs without prompting.
  -v, --verbose LEVEL   Set log verbosity level (integer, e.g., -v 1, -v 2).
  -q, --quiet           Silence informational logs.

The script orchestrates a llama.cpp-backed planner with a registry of
machine-checkable tools. Provide a natural language query after
"--" to trigger planning, ranking, and execution.
USAGE
}

render_usage() {
	local usage_text
	usage_text="$(build_usage_text)"

	if command -v gum >/dev/null 2>&1; then
		# gum formatting keeps help text readable when available but the
		# plain fallback ensures portability.
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
			# Accept both verbs for parity with hosted setup flows.
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
			shift
			;;
		-v | --verbose)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "-v/--verbose requires a verbosity level (integer)"
			fi
			VERBOSITY="$2"
			shift 2
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
			die "cli" "usage" "Unknown option: ${1}"
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
		die "cli" "usage" "A user query is required. See --help for usage."
	fi
}
