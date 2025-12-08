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
#   - jq
#
# Exit codes:
#   None directly; callers handle failures.

# shellcheck source=./errors.sh disable=SC1091
source "${BASH_SOURCE[0]%/logging.sh}/errors.sh"

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
		jq -cn \
			--arg time "${timestamp}" \
			--arg level "${level}" \
			--arg message "${message}" \
			--arg detail "${detail}" \
			'{time:$time, level:$level, message:$message, detail:$detail}'
	fi
}
