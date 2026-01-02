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

# shellcheck source=src/lib/core/errors.sh
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

	# Determine if the log should be emitted based on level and verbosity
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

	# Skip emission if verbosity is too low
	if [[ ${should_emit} -eq 0 ]]; then
		return 0
	fi

	# Trim detail if too long
	if [[ ${#detail} -gt 1000 ]]; then
		detail="${detail:0:1000}...[first 1000 chars of ${#detail} ($((100 * 1000 / ${#detail}))%)]"
	fi

	# Construct the log payload
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

	# Emit the log in the requested format
	case "${format_style}" in
	pretty)
		# Emit pretty-printed JSON with special handling for detail field
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
		# Emit compact JSON
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
