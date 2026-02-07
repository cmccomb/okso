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
  -v, --verbose [LEVEL] Stream progress events (LEVEL: 1 progress, 2 trace, 3 trace+schemas).
  -vv, -vvv             Shorthand for trace levels 2/3.
  -q, --quiet           Final summary only (no progress events).
  --progress            Alias for level 1 progress mode.
  --trace[=1|0]         Alias for trace mode on/off.
USAGE
}

render_cli_version() {
	local version
	version="${OKSO_VERSION:-${VERSION:-0.1.0}}"
	printf 'okso %s\n' "${version}"
}
