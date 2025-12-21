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
#   - bash 3.2+
#   - date (coreutils)
#   - jq
#
# Exit codes:
#   None directly; callers handle failures.

CORE_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./errors.sh disable=SC1091
source "${CORE_LIB_DIR}/errors.sh"

log_emit() {
	# Internal helper for emitting structured log entries.
	# Arguments:
	#   $1 - level (string: DEBUG|INFO|WARN|ERROR)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	#   $4 - format style (string: compact|pretty)
	local level message detail format_style timestamp should_emit verbosity payload
	level="$1"
	message="$2"
	detail=${3:-""}
	format_style="$4"
	timestamp="$(date +%Y-%m-%dT%H:%M:%S%z)"
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
		'{
			time: $time,
			level: $level,
			message: $message,
			detail: $detail
		}')

        case "${format_style}" in
        pretty)
                printf '%s\n' "${payload}" | jq '
                .detail |= (
                        if type == "string" then
                                . as $d
                                | if $d == "" then $d
                                        else (try ($d | fromjson) catch $d)
                                  end
                        else
                                .
                        end
                        | if type == "string" and (test("\n")) then split("\n") else . end
                )
        ' >&2
                ;;
        *)
		printf '%s\n' "${payload}" | jq -c '.' >&2
		;;
	esac
}

log() {
	# Emits a compact JSON log entry to stderr.
	# Arguments:
	#   $1 - level (string: DEBUG|INFO|WARN|ERROR)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	log_emit "$1" "$2" "${3:-""}" "compact"
}

log_pretty() {
	# Emits a pretty-printed JSON log entry to stderr.
	# Arguments:
	#   $1 - level (string: DEBUG|INFO|WARN|ERROR)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	log_emit "$1" "$2" "${3:-""}" "pretty"
}
