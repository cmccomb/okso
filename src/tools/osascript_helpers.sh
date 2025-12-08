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
#   OSASCRIPT_ALLOWED_FLAGS (array): optional allowlist for flags forwarded to osascript.
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

osascript_disallow_argument() {
	# Rejects suspect arguments that could alter osascript invocation.
	# Arguments:
	#   $1 - argument to validate (string)
	# Returns:
	#   0 when the argument is safe to pass, 1 otherwise.
	local argument allowed_flag
	argument="$1"

	if [[ "${argument}" == -* ]]; then
		if [[ -z "${OSASCRIPT_ALLOWED_FLAGS[*]:-}" ]]; then
			log "ERROR" "osascript flags are disallowed" "${argument}" || true
			return 1
		fi

		for allowed_flag in "${OSASCRIPT_ALLOWED_FLAGS[@]}"; do
			if [[ "${argument}" == "${allowed_flag}" ]]; then
				return 0
			fi
		done

		log "ERROR" "osascript flag not allowed" "${argument}" || true
		return 1
	fi

	if [[ "${argument}" == *\`* || "${argument}" == *\$\(* ]]; then
		log "ERROR" "osascript arguments may not include shell substitution" "${argument}" || true
		return 1
	fi

	return 0
}

sanitize_osascript_arguments() {
	# Validates all provided arguments using osascript_disallow_argument.
	# Arguments:
	#   $@ - candidate arguments destined for osascript
	local argument
	for argument in "$@"; do
		if ! osascript_disallow_argument "${argument}"; then
			return 1
		fi
	done
	return 0
}

osascript_run_evaluated() {
	# Invokes osascript with a single -e expression after sanitizing inputs.
	# Arguments:
	#   $1 - osascript binary (string; defaults to "osascript")
	#   $2 - script expression (string; required)
	#   $@ - additional arguments passed through after validation
	local bin expression
	bin="${1:-osascript}"
	expression="$2"
	shift 2

	OSASCRIPT_ALLOWED_FLAGS=("-e")
	if ! sanitize_osascript_arguments "-e" "${expression}" "$@"; then
		return 1
	fi

	"${bin}" -e "${expression}" "$@"
}

osascript_run_piped() {
	# Invokes osascript reading a script from stdin after sanitizing inputs.
	# Arguments:
	#   $1 - osascript binary (string; defaults to "osascript")
	#   $@ - arguments forwarded to osascript after validation
	local bin
	bin="${1:-osascript}"
	shift

	OSASCRIPT_ALLOWED_FLAGS=("-")
	if ! sanitize_osascript_arguments "-" "$@"; then
		return 1
	fi

	"${bin}" - "$@"
}
