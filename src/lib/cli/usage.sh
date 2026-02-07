#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared CLI usage/version rendering for the okso entrypoint and argument parser.
#
# Usage:
#   source "${BASH_SOURCE[0]%/usage.sh}/usage.sh"

render_cli_usage() {
	local entrypoint_display
	entrypoint_display="${OKSO_ENTRYPOINT:-./src/bin/okso}"

	cat <<USAGE
Usage: ${entrypoint_display} [OPTIONS] -- "user query"

Options:
  -h, --help            Show help text.
  -V, --version         Show version information.
  -y, --yes, --no-confirm
                        Approve all tool runs without prompting.
  -v, --verbose [LEVEL] Enable verbose logs (optionally set integer level).
  -vv, -vvv             Increase verbosity (INFO/DEBUG).
  -q, --quiet           Silence informational logs.
USAGE
}

render_cli_version() {
	local version
	version="${OKSO_VERSION:-${VERSION:-0.1.0}}"
	printf 'okso %s\n' "${version}"
}
