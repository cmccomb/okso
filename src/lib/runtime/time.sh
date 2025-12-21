#!/usr/bin/env bash
# shellcheck shell=bash
#
# UTC time helpers for prompt rendering.
#
# Usage:
#   source "${BASH_SOURCE[0]%/time.sh}/time.sh"
#
# Dependencies:
#   - bash 3.2+
#   - coreutils date
#
# Exit codes:
#   Functions print derived values and return 0 on success.

current_date_utc() {
	date -u '+%Y-%m-%d'
}

current_time_utc() {
	date -u '+%H:%M:%S'
}

current_weekday_utc() {
	date -u '+%A'
}

export -f current_date_utc
export -f current_time_utc
export -f current_weekday_utc
