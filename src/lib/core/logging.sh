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
#   - src/lib/llm/tokens.sh
#
# Exit codes:
#   None directly; callers handle failures.

CORE_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LLM_LIB_DIR="${CORE_LIB_DIR%/core}/llm"

# shellcheck source=src/lib/core/errors.sh
source "${CORE_LIB_DIR}/errors.sh"
# shellcheck source=src/lib/llm/tokens.sh
source "${LLM_LIB_DIR}/tokens.sh"

log_should_emit() {
	# Determine if a log should emit based on level and verbosity.
	# Arguments:
	#   $1 - level (string: DEBUG|INFO|WARN|ERROR)
	#   $2 - verbosity (int)
	# Returns:
	#   Prints 1 if the log should emit, otherwise 0.
	local level verbosity
	level="$1"
	verbosity="$2"

	case "${level}" in
	DEBUG)
		((verbosity >= 2)) && printf '1' || printf '0'
		;;
	INFO)
		((verbosity >= 1)) && printf '1' || printf '0'
		;;
	ERROR | WARN)
		printf '1'
		;;
	*)
		((verbosity >= 1)) && printf '1' || printf '0'
		;;
	esac
}

log_truncate_detail() {
	# Truncate detail text to a maximum token count.
	# Arguments:
	#   $1 - detail (string)
	#   $2 - max_tokens (int)
	# Returns:
	#   Prints the (possibly truncated) detail string.
	local detail max_tokens detail_tokens truncated_detail truncated_tokens
	detail="$1"
	max_tokens="$2"

	detail_tokens=$(estimate_token_count "${detail}")
	if ((detail_tokens > max_tokens)); then
		truncated_detail="${detail:0:$((max_tokens * 4))}"
		truncated_tokens=$(estimate_token_count "${truncated_detail}")
		printf '%s...[first %s tokens of %s (%s%%)]' \
			"${truncated_detail}" \
			"${truncated_tokens}" \
			"${detail_tokens}" \
			"$((100 * truncated_tokens / detail_tokens))"
	else
		printf '%s' "${detail}"
	fi
}

log_build_payload() {
	# Build a log payload as compact JSON.
	# Arguments:
	#   $1 - timestamp (string)
	#   $2 - level (string)
	#   $3 - message (string)
	#   $4 - detail (string)
	# Returns:
	#   Prints compact JSON for the log payload.
	local timestamp level message detail
	timestamp="$1"
	level="$2"
	message="$3"
	detail="$4"

	jq -cn \
		--arg time "${timestamp}" \
		--arg level "${level}" \
		--arg message "${message}" \
		--arg detail "${detail}" \
		'{
			time: $time,
			level: $level,
			message: $message,
			detail: $detail
		}'
}

log_emit() {
	# Internal helper for emitting structured log entries.
	# Arguments:
	#   $1 - level (string: DEBUG|INFO|WARN|ERROR)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	#   $4 - format style (string: compact|pretty)
	local level message detail format_style timestamp verbosity should_emit payload max_detail_tokens
	level="$1"
	message="$2"
	detail=${3:-""}
	format_style="$4"
	timestamp="$(date +%Y-%m-%dT%H:%M:%S%z)"
	verbosity=${VERBOSITY:-1}
	should_emit="$(log_should_emit "${level}" "${verbosity}")"

	if [[ "${level}" != "DEBUG" && "${level}" != "INFO" && "${level}" != "WARN" && "${level}" != "ERROR" ]]; then
		level="INFO"
	fi

	# Skip emission if verbosity is too low
	if [[ "${should_emit}" -eq 0 ]]; then
		return 0
	fi

	max_detail_tokens=1000
	detail="$(log_truncate_detail "${detail}" "${max_detail_tokens}")"
	payload="$(log_build_payload "${timestamp}" "${level}" "${message}" "${detail}")"

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
