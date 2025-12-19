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

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./errors.sh disable=SC1091
source "${LIB_DIR}/errors.sh"

log_emit() {
	# Arguments:
	#   $1 - level (string)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	#   $4 - format style (string: compact|pretty)
	local level message detail format_style timestamp should_emit verbosity payload
	level="$1"
	message="$2"
	detail=${3:-""}
	format_style="$4"
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

	if [[ ${should_emit} -eq 0 ]]; then
		return 0
	fi

	payload=$(jq -n \
		--arg time "${timestamp}" \
		--arg level "${level}" \
		--arg message "${message}" \
		--arg detail "${detail}" \
		'{time:$time, level:$level, message:$message, detail:$detail}')

	case "${format_style}" in
	pretty)
		printf '%s\n' "${payload}" | jq '.' >&2
		;;
	*)
		printf '%s\n' "${payload}" | jq -c '.' >&2
		;;
	esac
}

log() {
	# Arguments:
	#   $1 - level (string)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	log_emit "$1" "$2" "${3:-""}" "compact"
}

log_pretty() {
	# Arguments:
	#   $1 - level (string)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	log_emit "$1" "$2" "${3:-""}" "pretty"
}
