#!/usr/bin/env bash
# shellcheck shell=bash
#
# Logging helpers for the okso assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/logging.sh}/logging.sh"
#
# Environment variables:
#   VERBOSITY (int): 0=quiet, 1=info (default), 2=debug.
#
# Dependencies:
#   - bash 5+
#   - date (coreutils)
#
# Exit codes:
#   None directly; callers handle failures.

log() {
	# Arguments:
	#   $1 - level (string)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	local level message detail timestamp should_emit verbosity
	level="$1"
	message="$2"
	detail=${3:-""}
	timestamp="$(date -Iseconds)"
	verbosity=${VERBOSITY:-1}
	should_emit=1

	case "${level}" in
	DEBUG)
		[[ ${verbosity} -lt 2 ]] && should_emit=0
		;;
	INFO)
		[[ ${verbosity} -lt 1 ]] && should_emit=0
		;;
	ERROR | WARN) ;;
	*)
		level="INFO"
		[[ ${verbosity} -lt 1 ]] && should_emit=0
		;;
	esac

	if [[ ${should_emit} -eq 1 ]]; then
		printf '{"time":"%s","level":"%s","message":"%s","detail":"%s"}\n' \
			"${timestamp}" "${level}" "${message}" "${detail}"
	fi
}

json_escape() {
	# Arguments:
	#   $1 - raw string
	local raw escaped
	raw="$1"
	escaped="${raw//\\/\\\\}"
	escaped="${escaped//"/\\"/}"
	escaped="${escaped//$'\n'/\\n}"
	printf '%s' "${escaped}"
}
