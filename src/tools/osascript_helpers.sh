#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for AppleScript-driven tooling that relies on osascript.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/osascript_helpers.sh}/tools/osascript_helpers.sh"
#
# Environment variables:
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   VERBOSITY (int): logging verbosity; see logging.sh.
#
# Dependencies:
#   - bash 5+
#   - osascript (optional; required when IS_MACOS=true)
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions emit warnings and return non-zero when requirements are unmet.

# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/osascript_helpers.sh}/logging.sh"

assert_osascript_available() {
	# Ensures osascript-based tools only run on macOS with the binary available.
	# Arguments:
	#   $1 - warning message when the platform is unsupported (string; required)
	#   $2 - warning message when osascript is missing (string; required)
	#   $3 - osascript binary path or name (string; optional; default "osascript")
	#   $4 - detail value to include in logs (string; optional)
	local platform_warning missing_warning osascript_bin detail
	platform_warning="$1"
	missing_warning="$2"
	osascript_bin="${3:-osascript}"
	detail="$4"

	if [[ -z "${platform_warning}" || -z "${missing_warning}" ]]; then
		log "ERROR" "assert_osascript_available requires warning messages" "${detail}" || true
		return 2
	fi

	if [[ "${IS_MACOS}" != true ]]; then
		log "WARN" "${platform_warning}" "${detail}" || true
		return 1
	fi

	if ! command -v "${osascript_bin}" >/dev/null 2>&1; then
		log "WARN" "${missing_warning}" "${detail}" || true
		return 1
	fi

	return 0
}
