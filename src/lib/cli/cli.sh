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
#
# Exit codes:
#   0 for help/version responses; 1 for argument errors.

CLI_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${CLI_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/cli/usage.sh
source "${CLI_LIB_DIR}/usage.sh"

render_usage() {
	# Renders the usage text for the okso CLI.
	# Returns:
	#   usage text on stdout (string)
	render_cli_usage
	cat <<'DETAILS'

The script orchestrates a llama.cpp-backed planner with a registry of
machine-checkable tools. Provide a natural language query after
"--" to trigger planning, ranking, and execution.
DETAILS
}

show_help() {
	render_usage
}

show_version() {
	render_cli_version
}

# shellcheck disable=SC2034 # TD-001: dynamic globals are intentionally consumed across sourced modules and tests.
parse_args() {
	# Parses CLI flags and captures positional query content.
	# Arguments:
	#   $@ - raw CLI argument list
	# Returns:
	#   0 on success; exits on help/version; non-zero on invalid usage.
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
			if [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]]; then
				VERBOSITY="$2"
				shift 2
			else
				VERBOSITY=1
				shift
			fi
			;;
		-vv)
			VERBOSITY=2
			shift
			;;
		-vvv)
			VERBOSITY=3
			shift
			;;
		--progress)
			OKSO_PROGRESS=1
			if ! [[ "${VERBOSITY:-0}" =~ ^[0-9]+$ ]] || ((VERBOSITY < 1)); then
				VERBOSITY=1
			fi
			shift
			;;
		--trace | --trace=1)
			OKSO_PROGRESS=1
			OKSO_TRACE=1
			if ! [[ "${VERBOSITY:-0}" =~ ^[0-9]+$ ]] || ((VERBOSITY < 2)); then
				VERBOSITY=2
			fi
			shift
			;;
		--trace=0)
			OKSO_TRACE=0
			shift
			;;
		-q | --quiet)
			VERBOSITY=0
			OKSO_PROGRESS=0
			OKSO_TRACE=0
			shift
			;;
		--)
			# Explicit end-of-options marker: everything after this is query text.
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
		# Preserve user spacing intent by joining captured positional tokens.
		USER_QUERY="${positional[*]}"
	else
		# Supports invocations that pass query only after `--`.
		USER_QUERY="$*"
	fi

	if [[ "${COMMAND}" == "run" && -z "${USER_QUERY:-}" ]]; then
		die "cli" "usage" "A user query is required. See --help for usage."
	fi
}
